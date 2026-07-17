import Foundation
import AppKit
import ApplicationServices
import Combine

@MainActor
final class FocusedWindowMonitor: ObservableObject {

    private static let enabledKey = "perWindowEnforcementEnabled"

    @Published private(set) var isTrusted: Bool = false
    @Published private(set) var isEnabled: Bool

    private weak var engine: RuleEngine?
    private var observer: AXObserver?
    private var currentPID: pid_t = 0
    private var workspaceObserver: NSObjectProtocol?
    private var trustPollTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        isTrusted = AXIsProcessTrusted()
    }

    func start(engine: RuleEngine) {
        self.engine = engine
        guard isEnabled else { return }
        startMonitoring()
    }

    func stop() {
        stopMonitoring()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            startMonitoring()
            _ = requestPermission()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        if workspaceObserver == nil {
            workspaceObserver = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.attachToFrontmost() }
            }
        }
        attachToFrontmost()
        startTrustPolling()
    }

    private func stopMonitoring() {
        detach()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        trustPollTimer?.invalidate()
        trustPollTimer = nil
    }

    /// Triggers the system's permission prompt the first time it is called. On
    /// subsequent calls (after the user has already responded) it just returns
    /// the current trust state.
    @discardableResult
    func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [key: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isTrusted = trusted
        if trusted {
            attachToFrontmost()
        }
        return trusted
    }

    func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startTrustPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTrust() }
        }
    }

    private func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            if trusted {
                attachToFrontmost()
            } else {
                detach()
            }
        }
    }

    private func attachToFrontmost() {
        guard isEnabled else { return }
        guard AXIsProcessTrusted() else {
            isTrusted = false
            detach()
            return
        }
        isTrusted = true
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        if pid == currentPID, observer != nil { return }
        detach()

        var newObserver: AXObserver?
        let result = AXObserverCreate(pid, focusedWindowChangedCallback, &newObserver)
        guard result == .success, let obs = newObserver else { return }

        let element = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let addResult = AXObserverAddNotification(
            obs,
            element,
            kAXFocusedWindowChangedNotification as CFString,
            context
        )
        guard addResult == .success else { return }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(obs),
            .commonModes
        )
        observer = obs
        currentPID = pid
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        currentPID = 0
    }

    fileprivate func handleFocusedWindowChange() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return }
        engine?.handleActivation(bundleID: bundleID)
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
    }
}

private func focusedWindowChangedCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<FocusedWindowMonitor>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        monitor.handleFocusedWindowChange()
    }
}
