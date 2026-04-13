import Foundation

enum LauncherLayoutPersistenceError: Error {
    case incompatibleSchema(version: Int, backupPath: String)
}

struct LauncherLayoutPersistence: @unchecked Sendable {
    private actor SnapshotWriter {
        func write(
            payload: LauncherLayoutSnapshot,
            to url: URL,
            fileManager: FileManager
        ) throws {
            try LauncherLayoutPersistence.writeSnapshotData(
                payload: payload,
                to: url,
                fileManager: fileManager
            )
        }
    }

    private static let snapshotWriter = SnapshotWriter()

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let layoutFileName = "layout-v2.json"
    private let legacyLayoutFileName = "layout-v1.json"

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? Self.defaultBaseDirectory(fileManager: fileManager)
    }

    var layoutFileURL: URL {
        baseDirectory.appendingPathComponent(layoutFileName, isDirectory: false)
    }

    var storagePath: String {
        layoutFileURL.path
    }

    func load() throws -> LauncherLayoutSnapshot? {
        let primaryURL = layoutFileURL
        let legacyURL = baseDirectory.appendingPathComponent(legacyLayoutFileName, isDirectory: false)

        if fileManager.fileExists(atPath: primaryURL.path) {
            let result = try loadSnapshot(at: primaryURL)
            guard let result else { return nil }
            if result.didMigrate {
                try save(result.snapshot)
            }
            return result.snapshot
        }

        if fileManager.fileExists(atPath: legacyURL.path) {
            let result = try loadSnapshot(at: legacyURL)
            guard let result else {
                return nil
            }
            try save(result.snapshot)
            try? fileManager.removeItem(at: legacyURL)
            return result.snapshot
        }

        return nil
    }

    func save(_ snapshot: LauncherLayoutSnapshot) throws {
        try Self.writeSnapshotData(
            payload: payloadForWrite(snapshot),
            to: layoutFileURL,
            fileManager: fileManager
        )
    }

    func saveAsync(_ snapshot: LauncherLayoutSnapshot) async throws {
        let outputURL = layoutFileURL
        let payload = payloadForWrite(snapshot)

        try await Self.snapshotWriter.write(
            payload: payload,
            to: outputURL,
            fileManager: fileManager
        )
    }

    private func loadSnapshot(at fileURL: URL) throws -> LauncherLayoutMigration.MigrationResult? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try LauncherLayoutMigration.decodeAndMigrate(from: data)
        } catch let error as LauncherLayoutMigration.MigrationError {
            switch error {
            case let .unsupportedSchema(version):
                let backupURL = try archiveUnsupportedSchemaFile(at: fileURL, schemaVersion: version)
                throw LauncherLayoutPersistenceError.incompatibleSchema(
                    version: version,
                    backupPath: backupURL.path
                )
            }
        } catch let error as DecodingError {
            try quarantineCorruptedFile(at: fileURL)
            throw error
        } catch {
            throw error
        }
    }

    private func quarantineCorruptedFile(at source: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }

        let directory = baseDirectory.appendingPathComponent("Corrupted", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "layout-corrupted-\(timestamp)-\(UUID().uuidString).json"
        let target = directory.appendingPathComponent(fileName, isDirectory: false)
        try fileManager.moveItem(at: source, to: target)
    }

    private func payloadForWrite(_ snapshot: LauncherLayoutSnapshot) -> LauncherLayoutSnapshot {
        LauncherLayoutSnapshot(
            schemaVersion: LauncherLayoutSnapshot.currentSchemaVersion,
            updatedAt: Date(),
            entries: snapshot.entries
        )
    }

    private static func writeSnapshotData(
        payload: LauncherLayoutSnapshot,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let baseDirectory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
    }

    private func archiveUnsupportedSchemaFile(at source: URL, schemaVersion: Int) throws -> URL {
        let directory = baseDirectory.appendingPathComponent("Unsupported", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "layout-schema-\(schemaVersion)-\(timestamp)-\(UUID().uuidString).json"
        let target = directory.appendingPathComponent(fileName, isDirectory: false)
        try fileManager.moveItem(at: source, to: target)
        return target
    }

    private static func defaultBaseDirectory(fileManager: FileManager) -> URL {
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return appSupport.appendingPathComponent("LaunchDeck", isDirectory: true)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("LaunchDeck", isDirectory: true)
    }
}
