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
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)

        try persistence.save(
            LauncherLayoutSnapshot(entries: [
                .app(id: safari.id),
                .app(id: terminal.id)
            ])
        )

        let store = LauncherStore(
            preferences: preferences,
            layoutPersistence: persistence,
            sessionPersistence: LauncherSessionPersistence(fileManager: fileManager, baseDirectory: directory),
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

    func testReloadRestoresLatestPersistedSessionState() async throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sessionPersistence = LauncherSessionPersistence(fileManager: fileManager, baseDirectory: directory)

        let store = LauncherStore(
            preferences: preferences,
            layoutPersistence: LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory),
            sessionPersistence: sessionPersistence,
            catalogClient: LauncherCatalogClient(
                loadApplications: { [safari, terminal] },
                enrichApplications: { $0 }
            ),
            appLauncher: .noop,
            autoReload: false
        )

        await store.reload()
        store.updatePageSize(1)
        store.goToPage(1)

        await store.flushPendingPersistence()
        await store.reload()

        XCTAssertEqual(store.currentPage, 1)
        XCTAssertEqual(sessionPersistence.load()?.currentPage, 1)
    }

    func testEnablingRestoreLastSessionAppliesPersistedSessionImmediately() async throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.restoreLastSession = false

        let sessionPersistence = LauncherSessionPersistence(fileManager: fileManager, baseDirectory: directory)
        try await sessionPersistence.saveAsync(
            LauncherSessionSnapshot(
                query: "term",
                currentPage: 0,
                activeFolderID: nil,
                updatedAt: Date()
            )
        )

        let store = LauncherStore(
            preferences: preferences,
            layoutPersistence: LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory),
            sessionPersistence: sessionPersistence,
            catalogClient: LauncherCatalogClient(
                loadApplications: { [safari, terminal] },
                enrichApplications: { $0 }
            ),
            appLauncher: .noop,
            autoReload: false
        )

        await store.reload()
        XCTAssertEqual(store.query, "")

        preferences.restoreLastSession = true
        await store.handleRestoreLastSessionPreferenceChange()

        XCTAssertEqual(store.query, "term")
        XCTAssertEqual(store.statusMessage, LaunchDeckStrings.sessionRestored)
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
