import Foundation

struct LauncherSearchIndex {
    private struct Item: Sendable {
        let app: AppItem
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
        return items
            .filter { $0.normalizedName.contains(normalizedKeyword) }
            .map { .app($0.app) }
    }

    private mutating func rebuildIfNeeded(entries: [LauncherEntry]) {
        guard isDirty else { return }
        let apps = entries.flatMap(\.flattenedApps)
        items = apps.map { app in
            Item(app: app, normalizedName: Self.normalize(app.name))
        }
        isDirty = false
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
