import Foundation
import Combine

@MainActor
final class FirstRunCoordinator: ObservableObject {

    @Published var showSheet: Bool = false
    @Published var detected: [DetectedApp] = []

    private let defaults: UserDefaults
    private let key = "InputLock.didCompleteFirstRun.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func runIfNeeded() {
        guard defaults.bool(forKey: key) == false else { return }
        detected = DeveloperPresetService.detectInstalled()
        if detected.isEmpty {
            markComplete()
            return
        }
        showSheet = true
    }

    func dismiss() {
        showSheet = false
        markComplete()
    }

    private func markComplete() {
        defaults.set(true, forKey: key)
    }
}
