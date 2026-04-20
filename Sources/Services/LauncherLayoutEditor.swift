import CoreGraphics
import Foundation

struct LauncherLayoutEditor {
    private(set) var entries: [LauncherEntry]

    init(entries: [LauncherEntry]) {
        self.entries = entries
    }

    func currentFolder(id folderID: String) -> FolderItem? {
        entries
            .compactMap(\.folderValue)
            .first(where: { $0.id == folderID })
    }

    func folderApps(in folder: FolderItem) -> [AppItem] {
        currentFolder(id: folder.id)?.apps ?? folder.apps
    }

    func rootEntry(id: String) -> LauncherEntry? {
        entries.first(where: { $0.id == id })
    }

    func canGroup(draggedID: String, targetID: String) -> Bool {
        guard let dragged = rootEntry(id: draggedID), let target = rootEntry(id: targetID) else {
            return false
        }

        switch (dragged, target) {
        case (.app, .app), (.app, .folder):
            return true
        default:
            return false
        }
    }

    @discardableResult
    mutating func reorderRootEntry(
        draggedID: String,
        targetID: String,
        placeAfterTarget: Bool = false
    ) -> Bool {
        guard let from = rootIndex(id: draggedID), let to = rootIndex(id: targetID), from != to else {
            return false
        }

        let targetIndex = placeAfterTarget ? to + 1 : to
        moveRootEntry(from: from, to: targetIndex)
        return true
    }

    /// Move a root entry to an absolute position.
    ///
    /// `insertionIndex` is interpreted in the **post-removal** array — i.e. after the
    /// dragged entry has been taken out, where should the caller want it to land.
    /// Valid range: `0 ... (entries.count - 1)` after removal.
    @discardableResult
    mutating func moveRootEntryToInsertionIndex(id: String, insertionIndex: Int) -> Bool {
        guard let from = rootIndex(id: id) else { return false }

        let entry = entries.remove(at: from)
        let clamped = max(0, min(insertionIndex, entries.count))
        entries.insert(entry, at: clamped)
        return true
    }

    mutating func group(draggedID: String, targetID: String) -> FolderItem? {
        guard let dragged = rootEntry(id: draggedID), let target = rootEntry(id: targetID) else {
            return nil
        }

        switch (dragged, target) {
        case let (.app(draggedApp), .app(targetApp)):
            return createFolder(draggedApp: draggedApp, targetApp: targetApp, draggedID: draggedID, targetID: targetID)
        case let (.app(draggedApp), .folder(folder)):
            return append(app: draggedApp, into: folder, draggedID: draggedID)
        default:
            return nil
        }
    }

    mutating func renameFolder(id folderID: String, to newName: String) -> FolderItem? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return mutateFolder(id: folderID) { folder in
            folder.name = trimmed
        }
    }

    mutating func reorderFolderApp(
        folderID: String,
        draggedAppID: String,
        targetAppID: String,
        placeAfterTarget: Bool = false
    ) -> FolderItem? {
        mutateFolder(id: folderID) { folder in
            guard let from = folder.apps.firstIndex(where: { $0.id == draggedAppID }),
                  let to = folder.apps.firstIndex(where: { $0.id == targetAppID }),
                  from != to else {
                return
            }

            let app = folder.apps.remove(at: from)
            let rawTargetIndex = placeAfterTarget ? to + 1 : to
            let clamped = max(0, min(rawTargetIndex, folder.apps.count))
            let adjusted = from < clamped ? clamped - 1 : clamped
            folder.apps.insert(app, at: adjusted)
        }
    }

    mutating func moveFolderAppToBoundary(
        folderID: String,
        draggedAppID: String,
        currentPage: Int?,
        direction: Int,
        pageSize: Int
    ) -> FolderItem? {
        mutateFolder(id: folderID) { folder in
            guard let from = folder.apps.firstIndex(where: { $0.id == draggedAppID }) else { return }
            let app = folder.apps.remove(at: from)

            guard let currentPage else {
                folder.apps.append(app)
                return
            }

            let resolvedPageSize = max(1, pageSize)
            let total = folder.apps.count
            let pageStart = max(0, min(currentPage * resolvedPageSize, total))
            let pageEndExclusive = max(pageStart, min((currentPage + 1) * resolvedPageSize, total))
            let targetIndex = direction < 0 ? pageStart : pageEndExclusive
            let clamped = max(0, min(targetIndex, folder.apps.count))
            folder.apps.insert(app, at: clamped)
        }
    }

    /// Move an app within a folder to an absolute position.
    ///
    /// `insertionIndex` follows the same post-removal semantics as
    /// ``moveRootEntryToInsertionIndex(id:insertionIndex:)``.
    mutating func moveFolderAppToInsertionIndex(
        folderID: String,
        draggedAppID: String,
        insertionIndex: Int
    ) -> FolderItem? {
        mutateFolder(id: folderID) { folder in
            guard let from = folder.apps.firstIndex(where: { $0.id == draggedAppID }) else { return }

            let app = folder.apps.remove(at: from)
            let clamped = max(0, min(insertionIndex, folder.apps.count))
            folder.apps.insert(app, at: clamped)
        }
    }

    mutating func extractFolderAppToRoot(folderID: String, appID: String) -> AppItem? {
        guard let folderIndex = entries.firstIndex(where: {
            guard case let .folder(folder) = $0 else { return false }
            return folder.id == folderID
        }), case var .folder(folder) = entries[folderIndex] else {
            return nil
        }

        guard let appIndex = folder.apps.firstIndex(where: { $0.id == appID }) else {
            return nil
        }

        let extractedApp = folder.apps.remove(at: appIndex)

        if folder.apps.isEmpty {
            entries.remove(at: folderIndex)
            entries.insert(.app(extractedApp), at: folderIndex)
        } else if folder.apps.count == 1 {
            let remainingApp = folder.apps[0]
            entries[folderIndex] = .app(remainingApp)
            entries.insert(.app(extractedApp), at: min(folderIndex + 1, entries.count))
        } else {
            entries[folderIndex] = .folder(folder)
            entries.insert(.app(extractedApp), at: min(folderIndex + 1, entries.count))
        }

        return extractedApp
    }

    /// Compute a value that changes whenever `entries` differs in structurally relevant ways
    /// (order, IDs, folder membership, folder names).
    ///
    /// - Important: This fingerprint is based on `Swift.Hasher`, whose seed is randomized per
    ///   process launch. The returned value is therefore stable **only within the current
    ///   process** and **must not** be persisted, transmitted, or compared across runs.
    ///   It is intended purely as a cheap change detector for in-memory caches (e.g. the
    ///   persistence scheduler that skips redundant saves).
    static func layoutFingerprint(of entries: [LauncherEntry]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(entries.count)

        for entry in entries {
            switch entry {
            case let .app(app):
                hasher.combine(0)
                hasher.combine(app.id)
            case let .folder(folder):
                hasher.combine(1)
                hasher.combine(folder.id)
                hasher.combine(folder.name)
                hasher.combine(folder.apps.count)
                for app in folder.apps {
                    hasher.combine(app.id)
                }
            }
        }

        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private mutating func createFolder(
        draggedApp: AppItem,
        targetApp: AppItem,
        draggedID: String,
        targetID: String
    ) -> FolderItem? {
        guard let draggedIndex = rootIndex(id: draggedID), let targetIndex = rootIndex(id: targetID) else {
            return nil
        }

        let insertIndex = min(draggedIndex, targetIndex)
        for index in [draggedIndex, targetIndex].sorted(by: >) {
            entries.remove(at: index)
        }

        let folder = FolderItem(
            id: UUID().uuidString,
            name: Self.defaultFolderName(first: targetApp, second: draggedApp),
            apps: [targetApp, draggedApp]
        )
        entries.insert(.folder(folder), at: insertIndex)
        return folder
    }

    private mutating func append(app: AppItem, into folder: FolderItem, draggedID: String) -> FolderItem? {
        guard let draggedIndex = rootIndex(id: draggedID), let folderIndex = rootIndex(id: folder.entryID) else {
            return nil
        }

        entries.remove(at: draggedIndex)
        let adjustedFolderIndex = draggedIndex < folderIndex ? folderIndex - 1 : folderIndex
        guard case var .folder(updatedFolder) = entries[adjustedFolderIndex] else { return nil }
        guard !updatedFolder.apps.contains(where: { $0.id == app.id }) else { return nil }
        updatedFolder.apps.append(app)
        entries[adjustedFolderIndex] = .folder(updatedFolder)
        return updatedFolder
    }

    private mutating func moveRootEntry(from: Int, to targetIndex: Int) {
        guard entries.indices.contains(from) else { return }

        let entry = entries.remove(at: from)
        let clamped = max(0, min(targetIndex, entries.count))
        let adjusted = from < clamped ? clamped - 1 : clamped
        entries.insert(entry, at: max(0, min(adjusted, entries.count)))
    }

    private func rootIndex(id: String) -> Int? {
        entries.firstIndex(where: { $0.id == id })
    }

    @discardableResult
    private mutating func mutateFolder(
        id folderID: String,
        mutate: (inout FolderItem) -> Void
    ) -> FolderItem? {
        guard let index = entries.firstIndex(where: {
            guard case let .folder(folder) = $0 else { return false }
            return folder.id == folderID
        }) else {
            return nil
        }

        guard case var .folder(folder) = entries[index] else { return nil }
        let originalFolder = folder
        mutate(&folder)
        guard folder != originalFolder else { return nil }
        entries[index] = .folder(folder)
        return folder
    }

    private static func defaultFolderName(first: AppItem, second: AppItem) -> String {
        let firstPrefix = first.name.split(separator: " ").first.map(String.init) ?? first.name
        let secondPrefix = second.name.split(separator: " ").first.map(String.init) ?? second.name
        if firstPrefix == secondPrefix {
            return firstPrefix
        }
        return LaunchDeckStrings.defaultFolderNamePair(first: firstPrefix, second: secondPrefix)
    }
}
