import Foundation

struct LauncherSearchIndex {
    private struct Item: Sendable {
        let appID: String
        let normalizedName: String
    }

    private var items: [Item] = []
    private var isDirty = true

    mutating func markDirty() {
        isDirty = true
    }

    mutating func filter(entries: [LauncherEntry], keyword: String) -> [LauncherEntry] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return entries
        }

        rebuildIfNeeded(entries: entries)
        let normalizedKeyword = Self.normalize(trimmed)
        let matchedIDs = Set(
            items.lazy
                .filter { $0.normalizedName.contains(normalizedKeyword) }
                .map(\.appID)
        )

        guard !matchedIDs.isEmpty else { return [] }

        var results: [LauncherEntry] = []
        results.reserveCapacity(matchedIDs.count)

        for entry in entries {
            switch entry {
            case let .app(app):
                if matchedIDs.contains(app.id) {
                    results.append(.app(app))
                }
            case let .folder(folder):
                for app in folder.apps where matchedIDs.contains(app.id) {
                    results.append(.app(app))
                }
            }
        }

        return results
    }

    private mutating func rebuildIfNeeded(entries: [LauncherEntry]) {
        guard isDirty else { return }
        items = entries.flatMap(\.flattenedApps).map { app in
            Item(appID: app.id, normalizedName: Self.normalize(app.name))
        }
        isDirty = false
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
