import Foundation

struct InputSource: Identifiable, Hashable, Codable {
    let id: String
    let localizedName: String
}

struct Rule: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String
    var appPath: String?
    var inputSourceID: String
    var inputSourceName: String
}
