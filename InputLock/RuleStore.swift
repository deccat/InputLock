import Foundation
import Combine

@MainActor
final class RuleStore: ObservableObject {

    @Published private(set) var rules: [Rule] = []
    private var index: [String: Rule] = [:]

    private let defaultsKey = "InputLock.rules.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func rule(for bundleID: String) -> Rule? {
        index[bundleID]
    }

    func upsert(_ rule: Rule) {
        if let idx = rules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
        rebuildIndex()
        save()
    }

    func remove(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        rebuildIndex()
        save()
    }

    func removeAll() {
        rules.removeAll()
        rebuildIndex()
        save()
    }

    private func rebuildIndex() {
        index = Dictionary(uniqueKeysWithValues: rules.map { ($0.bundleID, $0) })
    }

    private func load() {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Rule].self, from: data) else { return }
        rules = decoded
        rebuildIndex()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
