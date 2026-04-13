import Foundation

struct LauncherLayoutMerger {
    static func merge(apps: [AppItem], persisted: LauncherLayoutSnapshot?) -> [LauncherEntry] {
        guard let persisted,
              persisted.schemaVersion == LauncherLayoutSnapshot.currentSchemaVersion else {
            return apps.map(LauncherEntry.app)
        }

        let appByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var usedAppIDs = Set<String>()
        var mergedEntries: [LauncherEntry] = []
        mergedEntries.reserveCapacity(max(persisted.entries.count, apps.count))

        for entry in persisted.entries {
            switch entry {
            case let .app(id):
                guard let app = appByID[id], usedAppIDs.insert(app.id).inserted else { continue }
                mergedEntries.append(.app(app))

            case let .folder(folderPayload):
                let folderApps = resolveApps(
                    ids: folderPayload.appIDs,
                    appByID: appByID,
                    usedAppIDs: &usedAppIDs
                )

                if folderApps.count >= 2 {
                    let folderID = folderPayload.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    let folderName = normalizedFolderName(folderPayload.name, apps: folderApps)
                    mergedEntries.append(
                        .folder(.init(
                            id: folderID.isEmpty ? UUID().uuidString : folderID,
                            name: folderName,
                            apps: folderApps
                        ))
                    )
                } else if let remaining = folderApps.first {
                    mergedEntries.append(.app(remaining))
                }
            }
        }

        for app in apps where usedAppIDs.insert(app.id).inserted {
            mergedEntries.append(.app(app))
        }

        return normalize(entries: mergedEntries)
    }

    private static func resolveApps(
        ids: [String],
        appByID: [String: AppItem],
        usedAppIDs: inout Set<String>
    ) -> [AppItem] {
        var resolved: [AppItem] = []
        resolved.reserveCapacity(ids.count)

        for appID in ids {
            guard let app = appByID[appID], usedAppIDs.insert(appID).inserted else { continue }
            resolved.append(app)
        }
        return resolved
    }

    private static func normalize(entries: [LauncherEntry]) -> [LauncherEntry] {
        var seenApps = Set<String>()
        var normalized: [LauncherEntry] = []
        normalized.reserveCapacity(entries.count)

        for entry in entries {
            switch entry {
            case let .app(app):
                guard seenApps.insert(app.id).inserted else { continue }
                normalized.append(.app(app))

            case let .folder(folder):
                let uniqueApps = folder.apps.filter { seenApps.insert($0.id).inserted }
                if uniqueApps.count >= 2 {
                    let folderName = normalizedFolderName(folder.name, apps: uniqueApps)
                    normalized.append(.folder(.init(id: folder.id, name: folderName, apps: uniqueApps)))
                } else if let remaining = uniqueApps.first {
                    normalized.append(.app(remaining))
                }
            }
        }

        return normalized
    }

    private static func normalizedFolderName(_ candidate: String, apps: [AppItem]) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return apps.first?.name ?? "文件夹"
    }
}
