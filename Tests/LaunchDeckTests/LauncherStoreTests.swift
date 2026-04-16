import CoreGraphics
import Foundation
import XCTest
@testable import LaunchDeck

@MainActor
final class LauncherStoreTests: XCTestCase {
    private final class LaunchErrorBox: @unchecked Sendable {
        var value: String?

        init(_ value: String? = nil) {
            self.value = value
        }
    }

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

    func testGroupingDropKeepsFolderClosed() async {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = LauncherStore(
            preferences: preferences,
            catalogClient: LauncherCatalogClient(
                loadApplications: { [safari, terminal] },
                enrichApplications: { $0 }
            ),
            appLauncher: .noop,
            autoReload: false
        )

        await store.reload()
        store.beginDragging(.app(terminal))
        store.handleDrop(
            on: .app(safari),
            location: CGPoint(x: 52, y: 48),
            tileSize: CGSize(width: 104, height: 118)
        )

        XCTAssertNil(store.activeFolder)
        XCTAssertEqual(store.rootEntries.count, 1)
        XCTAssertEqual(store.rootEntries.first?.folderValue?.apps.map(\.id), [safari.id, terminal.id])
    }

    func testDropOnRightHalfMovesDraggedEntryAfterTarget() async {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let xcode = app("Xcode", path: "/Applications/Xcode.app")
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = LauncherStore(
            preferences: preferences,
            catalogClient: LauncherCatalogClient(
                loadApplications: { [safari, terminal, xcode] },
                enrichApplications: { $0 }
            ),
            appLauncher: .noop,
            autoReload: false
        )

        await store.reload()
        let initialOrder = store.rootEntries.map(\.id)
        XCTAssertEqual(Set(initialOrder), Set([safari.entryID, terminal.entryID, xcode.entryID]))

        store.beginDragging(.app(safari))
        store.handleDrop(
            on: .app(terminal),
            location: CGPoint(x: 100, y: 48),
            tileSize: CGSize(width: 104, height: 118)
        )

        let updatedOrder = store.rootEntries.map(\.id)
        XCTAssertEqual(updatedOrder.count, 3)
        XCTAssertLessThan(updatedOrder.firstIndex(of: terminal.entryID) ?? .max, updatedOrder.firstIndex(of: safari.entryID) ?? .max)
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

    func testSuccessfulLaunchClearsPreviousError() async {
        let launchError = LaunchErrorBox("launch failed")
        let safari = app("Safari", path: "/Applications/Safari.app")
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = LauncherStore(
            preferences: preferences,
            catalogClient: LauncherCatalogClient(
                loadApplications: { [safari] },
                enrichApplications: { $0 }
            ),
            appLauncher: AppLaunchClient { _, completion in
                completion(launchError.value)
            },
            autoReload: false
        )

        await store.reload()
        store.launch(safari)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(store.lastError, "launch failed")

        launchError.value = nil
        store.launch(safari)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.statusMessage, LaunchDeckStrings.openedApp(safari.name))
    }

    func testSuccessfulSessionClearClearsPreviousError() async throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let launchError = LaunchErrorBox("launch failed")
        let safari = app("Safari", path: "/Applications/Safari.app")
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let sessionPersistence = LauncherSessionPersistence(fileManager: fileManager, baseDirectory: directory)
        let store = LauncherStore(
            preferences: preferences,
            layoutPersistence: LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory),
            sessionPersistence: sessionPersistence,
            catalogClient: LauncherCatalogClient(
                loadApplications: { [safari] },
                enrichApplications: { $0 }
            ),
            appLauncher: AppLaunchClient { _, completion in
                completion(launchError.value)
            },
            autoReload: false
        )

        await store.reload()
        store.launch(safari)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(store.lastError, "launch failed")

        await store.clearRestoredSession()

        XCTAssertNil(store.lastError)
        XCTAssertEqual(store.statusMessage, LaunchDeckStrings.sessionCleared)
    }

    func testReloadRewritesArchivedIncompatibleLayoutInSameSession() async throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let unsupportedPayload = """
        {
          "schemaVersion" : 99,
          "entries" : []
        }
        """
        let persistence = LauncherLayoutPersistence(fileManager: fileManager, baseDirectory: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(unsupportedPayload.utf8).write(to: persistence.layoutFileURL, options: [.atomic])

        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let preferences = LauncherPreferences(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
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

        let archivedDirectory = directory.appendingPathComponent("Unsupported", isDirectory: true)
        let archived = (try? fileManager.contentsOfDirectory(atPath: archivedDirectory.path)) ?? []
        XCTAssertFalse(archived.isEmpty)
        guard let archivedFile = archived.first else {
            XCTFail("expected archived incompatible layout")
            return
        }

        XCTAssertEqual(
            store.lastError,
            LaunchDeckStrings.persistenceIncompatible(
                version: 99,
                backupPath: archivedDirectory.appendingPathComponent(archivedFile, isDirectory: false).path
            )
        )

        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(
            store.lastError,
            LaunchDeckStrings.persistenceIncompatible(
                version: 99,
                backupPath: archivedDirectory.appendingPathComponent(archivedFile, isDirectory: false).path
            )
        )

        let loaded = try persistence.load()
        XCTAssertEqual(loaded?.entries, [
            .app(id: safari.id),
            .app(id: terminal.id)
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
