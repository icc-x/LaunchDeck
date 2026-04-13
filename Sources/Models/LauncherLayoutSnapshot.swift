import Foundation

struct LauncherLayoutSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var updatedAt: Date
    var entries: [Entry]

    init(
        schemaVersion: Int = LauncherLayoutSnapshot.currentSchemaVersion,
        updatedAt: Date = Date(),
        entries: [Entry]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.distantPast
        entries = try container.decode([Entry].self, forKey: .entries)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(entries, forKey: .entries)
    }

    static func == (lhs: LauncherLayoutSnapshot, rhs: LauncherLayoutSnapshot) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion && lhs.entries == rhs.entries
    }

    enum Entry: Codable, Equatable, Sendable {
        case app(id: String)
        case folder(Folder)

        struct Folder: Codable, Equatable, Sendable {
            var id: String
            var name: String
            var appIDs: [String]
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case appID
            case folder
        }

        private enum Kind: String, Codable {
            case app
            case folder
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .app:
                self = .app(id: try container.decode(String.self, forKey: .appID))
            case .folder:
                self = .folder(try container.decode(Folder.self, forKey: .folder))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .app(id):
                try container.encode(Kind.app, forKey: .kind)
                try container.encode(id, forKey: .appID)
            case let .folder(folder):
                try container.encode(Kind.folder, forKey: .kind)
                try container.encode(folder, forKey: .folder)
            }
        }
    }
}

extension LauncherLayoutSnapshot {
    init(rootEntries: [LauncherEntry]) {
        var snapshotEntries: [Entry] = []
        snapshotEntries.reserveCapacity(rootEntries.count)

        for entry in rootEntries {
            switch entry {
            case let .app(app):
                snapshotEntries.append(.app(id: app.id))
            case let .folder(folder):
                let uniqueAppIDs = Self.deduplicated(folder.apps.map(\.id))
                if uniqueAppIDs.count >= 2 {
                    let normalizedName = Self.normalizedFolderName(folder.name)
                    snapshotEntries.append(
                        .folder(.init(
                            id: folder.id,
                            name: normalizedName,
                            appIDs: uniqueAppIDs
                        ))
                    )
                } else {
                    snapshotEntries.append(contentsOf: uniqueAppIDs.map { Entry.app(id: $0) })
                }
            }
        }

        self.init(entries: snapshotEntries)
    }

    private static func normalizedFolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? LaunchDeckStrings.defaultFolderName : trimmed
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(values.count)

        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
