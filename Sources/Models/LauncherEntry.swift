import Foundation

enum LauncherEntry: Identifiable, Hashable, Sendable {
    case app(AppItem)
    case folder(FolderItem)

    var id: String {
        switch self {
        case let .app(app):
            return app.entryID
        case let .folder(folder):
            return folder.entryID
        }
    }

    var displayName: String {
        switch self {
        case let .app(app):
            return app.name
        case let .folder(folder):
            return folder.name
        }
    }

    var flattenedApps: [AppItem] {
        switch self {
        case let .app(app):
            return [app]
        case let .folder(folder):
            return folder.apps
        }
    }

    var appValue: AppItem? {
        guard case let .app(app) = self else { return nil }
        return app
    }

    var folderValue: FolderItem? {
        guard case let .folder(folder) = self else { return nil }
        return folder
    }

    static func == (lhs: LauncherEntry, rhs: LauncherEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.app(left), .app(right)):
            return left == right
        case let (.folder(left), .folder(right)):
            return left == right
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .app(app):
            hasher.combine(0)
            hasher.combine(app)
        case let .folder(folder):
            hasher.combine(1)
            hasher.combine(folder)
        }
    }
}
