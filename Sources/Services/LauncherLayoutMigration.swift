import Foundation

struct LauncherLayoutMigration {
    enum MigrationError: Error {
        case unsupportedSchema(Int)
    }

    struct MigrationResult {
        var snapshot: LauncherLayoutSnapshot
        var didMigrate: Bool
    }

    private struct VersionProbe: Decodable {
        var schemaVersion: Int
    }

    private struct V1Snapshot: Decodable {
        var schemaVersion: Int
        var entries: [LauncherLayoutSnapshot.Entry]
    }

    static func decodeAndMigrate(from data: Data) throws -> MigrationResult? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let version = try decoder.decode(VersionProbe.self, from: data).schemaVersion
        switch version {
        case LauncherLayoutSnapshot.currentSchemaVersion:
            let snapshot = try decoder.decode(LauncherLayoutSnapshot.self, from: data)
            return MigrationResult(snapshot: normalized(snapshot), didMigrate: false)
        case 1:
            let legacy = try decoder.decode(V1Snapshot.self, from: data)
            let migrated = LauncherLayoutSnapshot(
                schemaVersion: LauncherLayoutSnapshot.currentSchemaVersion,
                updatedAt: Date(),
                entries: legacy.entries
            )
            return MigrationResult(snapshot: normalized(migrated), didMigrate: true)
        default:
            throw MigrationError.unsupportedSchema(version)
        }
    }

    private static func normalized(_ snapshot: LauncherLayoutSnapshot) -> LauncherLayoutSnapshot {
        LauncherLayoutSnapshot(
            schemaVersion: LauncherLayoutSnapshot.currentSchemaVersion,
            updatedAt: snapshot.updatedAt,
            entries: snapshot.entries
        )
    }
}
