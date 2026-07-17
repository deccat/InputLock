import SwiftUI
import AppKit

struct MenuBarView: View {

    @EnvironmentObject private var sources: InputSourceService
    @EnvironmentObject private var store: RuleStore
    @EnvironmentObject private var engine: RuleEngine
    @EnvironmentObject private var login: LoginItemService
    @EnvironmentObject private var firstRun: FirstRunCoordinator
    @EnvironmentObject private var focusMonitor: FocusedWindowMonitor
    @Environment(\.openSettings) private var openSettingsEnvironment

    @State private var currentName: String = "—"
    @State private var currentID: String = ""
    @State private var refreshTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            if focusMonitor.isEnabled && !focusMonitor.isTrusted {
                accessibilityBanner
                Divider()
            }
            header
            Divider()
            recentRules
            Divider()
            footer
        }
        .frame(width: 300)
        .padding(.vertical, 10)
        .onAppear {
            refresh()
            if firstRun.showSheet {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    openSettings()
                }
            }
        }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("需要辅助功能权限")
                    .font(.callout.weight(.semibold))
            }
            Text("未授权时，已设置规则的应用中通过 ⌘N 打开的新窗口将不会自动切换输入法。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("授权…") {
                    _ = focusMonitor.requestPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if !focusMonitor.isTrusted {
                            focusMonitor.openAccessibilityPane()
                        }
                    }
                }
                Button("打开系统设置") {
                    focusMonitor.openAccessibilityPane()
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前输入法")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currentName)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let last = engine.lastSwitch, Date().timeIntervalSince(last.at) < 2.5 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            statusLine
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var statusLine: some View {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let frontName = frontApp?.localizedName ?? "—"
        let ruled = bundleID.flatMap { store.rule(for: $0) }
        return HStack(spacing: 6) {
            Image(systemName: ruled == nil ? "circle.dashed" : "lock.fill")
                .foregroundStyle(ruled == nil ? Color.secondary : Color.blue)
                .font(.caption)
            Text(ruled == nil
                 ? "\(frontName) 暂无规则"
                 : "\(frontName) 已锁定为 \(ruled!.inputSourceName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var recentRules: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("规则")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            if store.rules.isEmpty {
                Text("还没有规则——打开「设置」添加。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(store.rules.prefix(4)) { rule in
                        ruleRow(rule)
                    }
                    if store.rules.count > 4 {
                        Text("还有 \(store.rules.count - 4) 条")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func ruleRow(_ rule: Rule) -> some View {
        HStack(spacing: 8) {
            appIcon(for: rule)
                .frame(width: 18, height: 18)
            Text(rule.appName)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(rule.inputSourceName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    private func appIcon(for rule: Rule) -> some View {
        let image: NSImage = {
            if let path = rule.appPath, FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }()
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { login.enabled },
                set: { login.setEnabled($0) }
            )) {
                Text("开机自动启动")
                    .font(.callout)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 14)

            HStack {
                Button("设置…") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("退出") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    private func refresh() {
        update()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in update() }
        }
    }

    private func update() {
        if let current = sources.currentSource() {
            currentName = current.localizedName
            currentID = current.id
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettingsEnvironment()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.title.lowercased().contains("settings")
                || window.title.lowercased().contains("preferences")
                || window.title == "InputLock" {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
