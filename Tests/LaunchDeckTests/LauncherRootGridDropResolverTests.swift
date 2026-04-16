import XCTest
@testable import LaunchDeck

final class LauncherRootGridDropResolverTests: XCTestCase {
    func testGlobalInsertionIndexAdjustsForDraggedEntryBeforeCurrentPage() {
        let apps = makeApps(["A", "B", "C", "D"])
        let entries = apps.map(LauncherEntry.app)

        let resolved = LauncherRootGridDropResolver.globalInsertionIndex(
            allEntries: entries,
            visibleEntries: entries[2..<4],
            draggingEntryID: apps[1].entryID,
            localInsertionIndex: 0
        )

        XCTAssertEqual(resolved, 1)
    }

    func testGlobalInsertionIndexSupportsDroppingAtEndOfLaterPage() {
        let apps = makeApps(["A", "B", "C", "D"])
        let entries = apps.map(LauncherEntry.app)

        let resolved = LauncherRootGridDropResolver.globalInsertionIndex(
            allEntries: entries,
            visibleEntries: entries[2..<4],
            draggingEntryID: apps[0].entryID,
            localInsertionIndex: 2
        )

        XCTAssertEqual(resolved, 3)
    }

    func testCanGroupUsesFullRootEntriesInsteadOfCurrentPageSlice() {
        let apps = makeApps(["A", "B", "C"])
        let entries = apps.map(LauncherEntry.app)

        XCTAssertTrue(
            LauncherRootGridDropResolver.canGroup(
                allEntries: entries,
                draggingEntryID: apps[0].entryID,
                targetEntry: .app(apps[1])
            )
        )
    }

    private func makeApps(_ names: [String]) -> [AppItem] {
        names.enumerated().map { index, name in
            AppItem(
                name: name,
                url: URL(fileURLWithPath: "/Applications/\(index)-\(name).app"),
                bundleIdentifier: "test.\(name)"
            )
        }
    }
}
