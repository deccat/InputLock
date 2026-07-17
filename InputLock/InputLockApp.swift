import SwiftUI
import AppKit

@main
struct InputLockApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("InputLock", systemImage: "keyboard.badge.ellipsis") {
            MenuBarView()
                .environmentObject(appDelegate.sources)
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.engine)
                .environmentObject(appDelegate.login)
                .environmentObject(appDelegate.firstRun)
                .environmentObject(appDelegate.focusMonitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsScene()
                .environmentObject(appDelegate.sources)
                .environmentObject(appDelegate.store)
                .environmentObject(appDelegate.engine)
                .environmentObject(appDelegate.login)
                .environmentObject(appDelegate.firstRun)
                .environmentObject(appDelegate.focusMonitor)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    let sources = InputSourceService()
    let store = RuleStore()
    lazy var engine = RuleEngine(store: store, sources: sources)
    let monitor = AppActivationMonitor()
    let focusMonitor = FocusedWindowMonitor()
    let login = LoginItemService()
    let firstRun = FirstRunCoordinator()

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            monitor.start(engine: engine)
            focusMonitor.start(engine: engine)
            firstRun.runIfNeeded()
            if firstRun.showSheet {
                openSettings()
            }
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            monitor.stop()
            focusMonitor.stop()
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
