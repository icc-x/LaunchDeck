import Foundation
import XCTest
@testable import LaunchDeck

final class LauncherLayoutPersistenceTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let persistence = LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory)
        let snapshot = LauncherLayoutSnapshot(entries: [
            .folder(.init(
                id: "dev-folder",
                name: "开发",
                appIDs: ["/Applications/Xcode.app", "/Applications/Safari.app"]
            )),
            .app(id: "/System/Applications/Utilities/Terminal.app")
        ])

        try persistence.save(snapshot)
        let loaded = try persistence.load()

        XCTAssertEqual(loaded, snapshot)
        XCTAssertTrue(fileManager.fileExists(atPath: persistence.layoutFileURL.path))
    }

    func testCorruptLayoutIsQuarantined() throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let persistence = LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: persistence.layoutFileURL, options: [.atomic])

        do {
            _ = try persistence.load()
            XCTFail("expected load() to throw for corrupted layout")
        } catch {
            // expected
        }

        XCTAssertFalse(fileManager.fileExists(atPath: persistence.layoutFileURL.path))
        let corruptedDirectory = directory.appendingPathComponent("Corrupted", isDirectory: true)
        let quarantined = (try? fileManager.contentsOfDirectory(atPath: corruptedDirectory.path)) ?? []
        XCTAssertFalse(quarantined.isEmpty)
    }

    func testMigratesLegacyV1LayoutFile() throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let persistence = LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let legacyPayload = """
        {
          "schemaVersion" : 1,
          "entries" : [
            {
              "kind" : "folder",
              "folder" : {
                "appIDs" : [
                  "/Applications/Safari.app",
                  "/Applications/Xcode.app"
                ],
                "id" : "dev-folder",
                "name" : "开发"
              }
            },
            {
              "kind" : "app",
              "appID" : "/System/Applications/Utilities/Terminal.app"
            }
          ]
        }
        """
        let legacyFile = directory.appendingPathComponent("layout-v1.json", isDirectory: false)
        try Data(legacyPayload.utf8).write(to: legacyFile, options: [.atomic])

        let loaded = try persistence.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.schemaVersion, LauncherLayoutSnapshot.currentSchemaVersion)
        XCTAssertTrue(fileManager.fileExists(atPath: persistence.layoutFileURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: legacyFile.path))
    }

    func testUnsupportedSchemaIsArchivedInsteadOfOverwritten() throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let persistence = LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let unsupportedPayload = """
        {
          "schemaVersion" : 99,
          "entries" : []
        }
        """
        try Data(unsupportedPayload.utf8).write(to: persistence.layoutFileURL, options: [.atomic])

        do {
            _ = try persistence.load()
            XCTFail("expected incompatible schema error")
        } catch let error as LauncherLayoutPersistenceError {
            switch error {
            case let .incompatibleSchema(version, backupPath):
                XCTAssertEqual(version, 99)
                XCTAssertTrue(fileManager.fileExists(atPath: backupPath))
            }
        } catch {
            XCTFail("expected LauncherLayoutPersistenceError, got: \(error)")
        }

        XCTAssertFalse(fileManager.fileExists(atPath: persistence.layoutFileURL.path))
        let unsupportedDirectory = directory.appendingPathComponent("Unsupported", isDirectory: true)
        let archived = (try? fileManager.contentsOfDirectory(atPath: unsupportedDirectory.path)) ?? []
        XCTAssertFalse(archived.isEmpty)
    }

    func testIOErrorDoesNotQuarantineAsCorrupted() throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let persistence = LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory)
        try fileManager.createDirectory(at: persistence.layoutFileURL, withIntermediateDirectories: true)

        do {
            _ = try persistence.load()
            XCTFail("expected load() to throw when layout path is a directory")
        } catch {
            // expected
        }

        XCTAssertTrue(fileManager.fileExists(atPath: persistence.layoutFileURL.path))
        let corruptedDirectory = directory.appendingPathComponent("Corrupted", isDirectory: true)
        XCTAssertFalse(fileManager.fileExists(atPath: corruptedDirectory.path))
    }

    private func makeTemporaryDirectory(fileManager: FileManager) -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("LaunchDeckTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
