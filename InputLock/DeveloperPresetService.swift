import Foundation
import AppKit

struct DetectedApp: Identifiable, Hashable {
    let id: String
    let bundleID: String
    let name: String
    let url: URL

    init(bundleID: String, name: String, url: URL) {
        self.id = bundleID
        self.bundleID = bundleID
        self.name = name
        self.url = url
    }
}

@MainActor
enum DeveloperPresetService {

    static let candidates: [(bundleID: String, fallbackName: String)] = [
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("com.apple.dt.Xcode", "Xcode"),
        ("com.mitchellh.ghostty", "Ghostty")
    ]

    static func detectInstalled() -> [DetectedApp] {
        candidates.compactMap { entry in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) else {
                return nil
            }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return DetectedApp(
                bundleID: entry.bundleID,
                name: name.isEmpty ? entry.fallbackName : name,
                url: url
            )
        }
    }
}
