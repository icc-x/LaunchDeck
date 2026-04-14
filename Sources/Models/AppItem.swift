import Foundation

struct AppItem: Identifiable, Hashable, Sendable {
    private final class Storage: @unchecked Sendable {
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
    }

    private let storage: Storage

    var id: String { storage.id }
    var entryID: String { storage.entryID }
    var name: String { storage.name }
    var url: URL { storage.url }
    var bundleIdentifier: String? { storage.bundleIdentifier }

    init(name: String, url: URL, bundleIdentifier: String?) {
        self.storage = Storage(name: name, url: url, bundleIdentifier: bundleIdentifier)
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
