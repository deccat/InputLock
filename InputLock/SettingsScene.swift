import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsScene: View {

    @EnvironmentObject private var sources: InputSourceService
    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var login: LoginItemService
    @EnvironmentObject private var firstRun: FirstRunCoordinator

    var body: some View {
        TabView {
            RulesTab()
                .tabItem { Label("规则", systemImage: "list.bullet.rectangle") }
                .environmentObject(sources)
                .environmentObject(store)

            PresetsTab()
                .tabItem { Label("预设", systemImage: "wand.and.stars") }
                .environmentObject(sources)
                .environmentObject(store)

            GeneralTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .environmentObject(sources)
                .environmentObject(store)
                .environmentObject(login)
        }
        .frame(width: 680, height: 460)
        .sheet(isPresented: $firstRun.showSheet) {
            WelcomeSheet()
                .environmentObject(sources)
                .environmentObject(store)
                .environmentObject(firstRun)
        }
    }
}

// MARK: - Rules tab

private struct RulesTab: View {
    @EnvironmentObject private var sources: InputSourceService
    @EnvironmentObject private var store: RuleStore
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if store.rules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.rules) { rule in
                            RuleCard(rule: rule)
                                .environmentObject(sources)
                                .environmentObject(store)
                        }
                    }
                    .padding(16)
                }
            }
            HStack {
                Button {
                    pickApp()
                } label: {
                    Label("添加应用…", systemImage: "plus")
                }
                Spacer()
                Text("共 \(store.rules.count) 条规则")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .padding(12)
            .background(.bar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("还没有规则")
                .font(.headline)
            Text("添加一个应用，并选择当它切到前台时要使用的输入法。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        let displayName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        let defaultSource = preferredDefaultSource()
        let rule = Rule(
            bundleID: bundleID,
            appName: displayName,
            appPath: url.path,
            inputSourceID: defaultSource.id,
            inputSourceName: defaultSource.localizedName
        )
        store.upsert(rule)
    }

    private func preferredDefaultSource() -> InputSource {
        let all = sources.listEnabledSources()
        if let abc = all.first(where: { $0.id == "com.apple.keylayout.ABC" }) {
            return abc
        }
        return all.first ?? InputSource(id: "com.apple.keylayout.ABC", localizedName: "ABC")
    }
}

private struct RuleCard: View {
    let rule: Rule
    @EnvironmentObject private var sources: InputSourceService
    @EnvironmentObject private var store: RuleStore
    @State private var allSources: [InputSource] = []
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.appName)
                    .font(.headline)
                    .lineLimit(1)
                Text(rule.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Picker("", selection: Binding(
                get: { rule.inputSourceID },
                set: { newID in
                    guard let pick = allSources.first(where: { $0.id == newID }) else { return }
                    var updated = rule
                    updated.inputSourceID = pick.id
                    updated.inputSourceName = pick.localizedName
                    store.upsert(updated)
                }
            )) {
                ForEach(allSources) { src in
                    Text(src.localizedName).tag(src.id)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            Button(role: .destructive) {
                store.remove(rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .onAppear {
            allSources = sources.listEnabledSources()
            if !allSources.contains(where: { $0.id == rule.inputSourceID }) {
                allSources.append(InputSource(id: rule.inputSourceID, localizedName: rule.inputSourceName))
            }
        }
    }

    private var icon: NSImage {
        if let path = rule.appPath, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

// MARK: - Presets tab

private struct PresetsTab: View {
    @EnvironmentObject private var sources: InputSourceService
    @EnvironmentObject private var store: RuleStore
    @State private var detected: [DetectedApp] = []
    @State private var selected: Set<String> = []
    @State private var targetSourceID: String = "com.apple.keylayout.ABC"
    @State private var allSources: [InputSource] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("开发者模式")
                        .font(.title2.weight(.semibold))
                    Text("把常用开发者应用锁定到同一种输入法。我们在你的 Mac 上检测到以下应用。")
                        .foregroundStyle(.secondary)
                }

                if detected.isEmpty {
                    Text("未检测到开发者应用（Terminal、iTerm、VS Code、Xcode、Ghostty）。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    VStack(spacing: 8) {
                        ForEach(detected) { app in
                            HStack(spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { selected.contains(app.bundleID) },
                                    set: { yes in
                                        if yes { selected.insert(app.bundleID) }
                                        else { selected.remove(app.bundleID) }
                                    }
                                ))
                                .labelsHidden()
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 30, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name).font(.body)
                                    Text(app.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.rule(for: app.bundleID) != nil {
                                    Text("已有规则")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }

                    HStack {
                        Text("锁定为：")
                        Picker("", selection: $targetSourceID) {
                            ForEach(allSources) { src in
                                Text(src.localizedName).tag(src.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Spacer()
                        Button {
                            apply()
                        } label: {
                            Label("应用到选中的 \(selected.count) 项",
                                  systemImage: "checkmark.circle.fill")
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selected.isEmpty)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(20)
        }
        .onAppear(perform: load)
    }

    private func load() {
        detected = DeveloperPresetService.detectInstalled()
        selected = Set(detected.map { $0.bundleID })
        allSources = sources.listEnabledSources()
        if !allSources.contains(where: { $0.id == targetSourceID }) {
            targetSourceID = allSources.first?.id ?? targetSourceID
        }
    }

    private func apply() {
        guard let target = allSources.first(where: { $0.id == targetSourceID }) else { return }
        for app in detected where selected.contains(app.bundleID) {
            let rule = Rule(
                bundleID: app.bundleID,
                appName: app.name,
                appPath: app.url.path,
                inputSourceID: target.id,
                inputSourceName: target.localizedName
            )
            store.upsert(rule)
        }
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    @EnvironmentObject private var sources: InputSourceService
    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var login: LoginItemService
    @EnvironmentObject private var focusMonitor: FocusedWindowMonitor
    @State private var currentName: String = "—"
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle("开机自动启动", isOn: Binding(
                    get: { login.enabled },
                    set: { login.setEnabled($0) }
                ))
            }
            Section("当前输入法") {
                LabeledContent("正在使用", value: currentName)
            }
            Section {
                Toggle(isOn: Binding(
                    get: { focusMonitor.isEnabled },
                    set: { focusMonitor.setEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("监控应用内新建窗口")
                            .font(.callout)
                        Text("开启后，当你在已设置规则的应用中按 ⌘N 打开新窗口时，会自动重新切换到对应的输入法。需要授予「辅助功能」权限。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if focusMonitor.isEnabled {
                    HStack {
                        Image(systemName: focusMonitor.isTrusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(focusMonitor.isTrusted ? Color.green : Color.orange)
                        Text(focusMonitor.isTrusted ? "已授予辅助功能权限" : "尚未授予辅助功能权限")
                            .font(.callout)
                        Spacer()
                        if focusMonitor.isTrusted {
                            Button("打开系统设置") { focusMonitor.openAccessibilityPane() }
                        } else {
                            Button("授权…") {
                                _ = focusMonitor.requestPermission()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if !focusMonitor.isTrusted {
                                        focusMonitor.openAccessibilityPane()
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("按窗口生效")
            }
            Section("危险操作") {
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("删除全部规则", systemImage: "trash")
                }
                .confirmationDialog(
                    "确定要删除全部规则吗？",
                    isPresented: $confirmReset,
                    titleVisibility: .visible
                ) {
                    Button("全部删除", role: .destructive) { store.removeAll() }
                    Button("取消", role: .cancel) { }
                }
            }
            Section("关于") {
                LabeledContent("版本", value: Bundle.main.appVersion)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            currentName = sources.currentSource()?.localizedName ?? "—"
            login.refresh()
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Welcome sheet (first-run)

struct WelcomeSheet: View {
    @EnvironmentObject private var sources: InputSourceService
    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var firstRun: FirstRunCoordinator
    @State private var selected: Set<String> = []
    @State private var targetSourceID: String = "com.apple.keylayout.ABC"
    @State private var allSources: [InputSource] = []

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                Text("欢迎使用 InputLock")
                    .font(.title2.weight(.semibold))
                Text("选择要锁定输入法的应用，打开它们时我们会自动切换。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .padding(.top, 20)

            VStack(spacing: 8) {
                ForEach(firstRun.detected) { app in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { selected.contains(app.bundleID) },
                            set: { yes in
                                if yes { selected.insert(app.bundleID) }
                                else { selected.remove(app.bundleID) }
                            }
                        ))
                        .labelsHidden()
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 28, height: 28)
                        Text(app.name)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }
            .padding(.horizontal, 24)

            HStack(spacing: 8) {
                Text("切换为：")
                Picker("", selection: $targetSourceID) {
                    ForEach(allSources) { src in
                        Text(src.localizedName).tag(src.id)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            HStack {
                Button("跳过") { firstRun.dismiss() }
                Spacer()
                Button {
                    apply()
                    firstRun.dismiss()
                } label: {
                    Text("添加 \(selected.count) 条规则")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 460)
        .onAppear {
            selected = Set(firstRun.detected.map { $0.bundleID })
            allSources = sources.listEnabledSources()
            if !allSources.contains(where: { $0.id == targetSourceID }) {
                targetSourceID = allSources.first?.id ?? targetSourceID
            }
        }
    }

    private func apply() {
        guard let target = allSources.first(where: { $0.id == targetSourceID }) else { return }
        for app in firstRun.detected where selected.contains(app.bundleID) {
            let rule = Rule(
                bundleID: app.bundleID,
                appName: app.name,
                appPath: app.url.path,
                inputSourceID: target.id,
                inputSourceName: target.localizedName
            )
            store.upsert(rule)
        }
    }
}
