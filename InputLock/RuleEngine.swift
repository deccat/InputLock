import Foundation
import Combine

@MainActor
final class RuleEngine: ObservableObject {

    @Published private(set) var lastSwitch: SwitchEvent?

    struct SwitchEvent: Equatable {
        let bundleID: String
        let inputSourceID: String
        let inputSourceName: String
        let at: Date
    }

    private let store: RuleStore
    private let sources: InputSourceService
    private var pending: DispatchWorkItem?
    private let debounce: TimeInterval = 0.1

    init(store: RuleStore, sources: InputSourceService) {
        self.store = store
        self.sources = sources
    }

    func handleActivation(bundleID: String) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.apply(bundleID: bundleID)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func apply(bundleID: String) {
        guard let rule = store.rule(for: bundleID) else { return }
        guard sources.currentSource()?.id != rule.inputSourceID else { return }
        if sources.select(id: rule.inputSourceID) {
            lastSwitch = SwitchEvent(
                bundleID: bundleID,
                inputSourceID: rule.inputSourceID,
                inputSourceName: rule.inputSourceName,
                at: Date()
            )
        }
    }
}
