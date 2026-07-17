import Foundation
import Carbon

@MainActor
final class InputSourceService: ObservableObject {

    func listEnabledSources() -> [InputSource] {
        guard let cfArray = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else {
            return []
        }
        let count = CFArrayGetCount(cfArray)
        var results: [InputSource] = []
        results.reserveCapacity(count)

        for index in 0..<count {
            let raw = CFArrayGetValueAtIndex(cfArray, index)
            let source = Unmanaged<TISInputSource>.fromOpaque(raw!).takeUnretainedValue()

            guard let category = property(source, kTISPropertyInputSourceCategory) as? String,
                  category == (kTISCategoryKeyboardInputSource as String) else { continue }

            if let selectable = property(source, kTISPropertyInputSourceIsSelectCapable) as? Bool,
               selectable == false { continue }

            guard let id = property(source, kTISPropertyInputSourceID) as? String,
                  let name = property(source, kTISPropertyLocalizedName) as? String else { continue }

            results.append(InputSource(id: id, localizedName: name))
        }

        return results.sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
    }

    func currentSource() -> InputSource? {
        guard let raw = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let id = property(raw, kTISPropertyInputSourceID) as? String,
              let name = property(raw, kTISPropertyLocalizedName) as? String else { return nil }
        return InputSource(id: id, localizedName: name)
    }

    @discardableResult
    func select(id: String) -> Bool {
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: id]
        guard let cfArray = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue(),
              CFArrayGetCount(cfArray) > 0 else { return false }
        let raw = CFArrayGetValueAtIndex(cfArray, 0)
        let source = Unmanaged<TISInputSource>.fromOpaque(raw!).takeUnretainedValue()
        return TISSelectInputSource(source) == noErr
    }

    private func property(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }
}
