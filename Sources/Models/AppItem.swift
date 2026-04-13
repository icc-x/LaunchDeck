import Foundation

struct AppItem: Identifiable, Hashable, Sendable {
    let id: String
    let entryID: String
    let name: String
    let url: URL
    let bundleIdentifier: String?

    init(name: String, url: URL, bundleIdentifier: String?) {
        self.id = url.path
        self.entryID = "app:\(url.path)"
        self.name = name
        self.url = url
        self.bundleIdentifier = bundleIdentifier
    }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(bundleIdentifier)
    }
}
