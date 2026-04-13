import CoreGraphics
import Foundation
import XCTest
@testable import LaunchDeck

@MainActor
final class LauncherStoreTests: XCTestCase {
    func testReloadFlushesPendingLayoutChangesBeforeReloadingPersistedLayout() async throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let persistence = LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory)

        try persistence.save(
            LauncherLayoutSnapshot(entries: [
                .app(id: safari.id),
                .app(id: terminal.id)
            ])
        )

        let store = LauncherStore(
            layoutPersistence: persistence,
            catalogClient: LauncherCatalogClient(
                loadApplications: { [safari, terminal] },
                enrichApplications: { $0 }
            ),
            appLauncher: .noop,
            autoReload: false
        )

        await store.reload()
        XCTAssertEqual(store.rootEntries.map(\.id), [safari.entryID, terminal.entryID])

        store.beginDragging(.app(terminal))
        store.handleDrop(
            on: .app(safari),
            location: CGPoint(x: 0, y: 0),
            tileSize: CGSize(width: 104, height: 118)
        )
        XCTAssertEqual(store.rootEntries.map(\.id), [terminal.entryID, safari.entryID])

        await store.reload()

        XCTAssertEqual(store.rootEntries.map(\.id), [terminal.entryID, safari.entryID])
        let snapshot = try persistence.load()
        XCTAssertEqual(snapshot?.entries, [
            .app(id: terminal.id),
            .app(id: safari.id)
        ])
    }

    private func app(_ name: String, path: String) -> AppItem {
        AppItem(name: name, url: URL(fileURLWithPath: path), bundleIdentifier: "test.\(name)")
    }

    private func makeTemporaryDirectory(fileManager: FileManager) -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("LaunchDeckStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
