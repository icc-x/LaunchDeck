import Foundation

struct FolderItem: Identifiable, Hashable, Sendable {
    let id: String
    let entryID: String
    var name: String
    var apps: [AppItem]

    init(id: String, name: String, apps: [AppItem]) {
        self.id = id
        self.entryID = "folder:\(id)"
        self.name = name
        self.apps = apps
    }

    static func == (lhs: FolderItem, rhs: FolderItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.apps == rhs.apps
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(apps)
    }
}
