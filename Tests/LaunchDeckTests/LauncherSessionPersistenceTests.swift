import Foundation
import XCTest
@testable import LaunchDeck

final class LauncherSessionPersistenceTests: XCTestCase {
    func testSaveLoadAndDeleteRoundTrip() async throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let persistence = LauncherSessionPersistence(fileManager: fileManager, baseDirectory: directory)
        let snapshot = LauncherSessionSnapshot(
            query: "xcode",
            currentPage: 2,
            activeFolderID: "dev-folder",
            updatedAt: Date()
        )

        try await persistence.saveAsync(snapshot)
        let loaded = persistence.load()
        XCTAssertEqual(loaded?.query, snapshot.query)
        XCTAssertEqual(loaded?.currentPage, snapshot.currentPage)
        XCTAssertEqual(loaded?.activeFolderID, snapshot.activeFolderID)

        try await persistence.deleteAsync()
        XCTAssertNil(persistence.load())
    }

    private func makeTemporaryDirectory(fileManager: FileManager) -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("LaunchDeckSessionTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
