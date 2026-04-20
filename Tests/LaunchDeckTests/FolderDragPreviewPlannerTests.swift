import XCTest
@testable import LaunchDeck

final class FolderDragPreviewPlannerTests: XCTestCase {
    private func makeApp(_ name: String) -> AppItem {
        AppItem(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleIdentifier: "com.example.\(name)"
        )
    }

    func testMakeDisplaySlotsInsertsPlaceholderAtIndex() {
        let apps = ["a", "b", "c"].map(makeApp)
        let slots = FolderDragPreviewPlanner.makeDisplaySlots(
            visibleApps: apps,
            draggingAppID: apps[1].id,
            previewInsertionIndex: 2
        )
        XCTAssertEqual(slots.map(\.id), [apps[0].id, apps[2].id, "folder-placeholder-\(apps[1].id)"])
    }

    func testMakeDisplaySlotsWithoutDragReturnsAppsInOrder() {
        let apps = ["a", "b", "c"].map(makeApp)
        let slots = FolderDragPreviewPlanner.makeDisplaySlots(
            visibleApps: apps,
            draggingAppID: nil,
            previewInsertionIndex: 1
        )
        XCTAssertEqual(slots.map(\.id), apps.map(\.id))
    }

    func testMakeDisplaySlotsClampsOutOfRangeIndex() {
        let apps = ["a", "b", "c"].map(makeApp)
        let slots = FolderDragPreviewPlanner.makeDisplaySlots(
            visibleApps: apps,
            draggingAppID: apps[0].id,
            previewInsertionIndex: 99
        )
        XCTAssertEqual(slots.map(\.id), [apps[1].id, apps[2].id, "folder-placeholder-\(apps[0].id)"])
    }

    func testInsertionIndexLeftHalfOfTargetPutsDraggedBefore() {
        let apps = ["a", "b", "c"].map(makeApp)
        let metrics = FolderGridLayout.metrics(for: CGSize(width: 640, height: 400))
        let slots = apps.map(FolderGridSlot.app)

        // With "a" being dragged, remaining order is [b, c]. Slot list rendered before the
        // placeholder lands is the unchanged [a, b, c]; hitting the left-half of index 1
        // (the "b" tile in the rendered grid) should produce insertion index 0 in the
        // remaining-apps coordinate system.
        let leftOfSecondTile = CGPoint(
            x: (metrics.tileWidth + metrics.columnSpacing) + metrics.tileWidth * 0.2,
            y: FolderGridLayout.verticalPadding + metrics.tileHeight * 0.3
        )
        let idx = FolderDragPreviewPlanner.insertionIndex(
            draggingAppID: apps[0].id,
            visibleApps: apps,
            displaySlots: slots,
            metrics: metrics,
            location: leftOfSecondTile,
            previewInsertionIndex: nil
        )
        XCTAssertEqual(idx, 0)
    }

    func testInsertionIndexOutsideGridIsNil() {
        let apps = ["a", "b"].map(makeApp)
        let metrics = FolderGridLayout.metrics(for: CGSize(width: 640, height: 400))
        let slots = apps.map(FolderGridSlot.app)
        let idx = FolderDragPreviewPlanner.insertionIndex(
            draggingAppID: apps[0].id,
            visibleApps: apps,
            displaySlots: slots,
            metrics: metrics,
            location: CGPoint(x: -10, y: -10),
            previewInsertionIndex: nil
        )
        XCTAssertNil(idx)
    }
}
