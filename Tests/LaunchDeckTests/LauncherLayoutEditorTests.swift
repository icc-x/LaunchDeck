import Foundation
import XCTest
@testable import LaunchDeck

final class LauncherLayoutEditorTests: XCTestCase {
    func testReorderRootEntryMovesDraggedEntryBeforeTarget() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        var editor = LauncherLayoutEditor(entries: [.app(safari), .app(terminal)])

        let didChange = editor.reorderRootEntry(
            draggedID: terminal.entryID,
            targetID: safari.entryID
        )

        XCTAssertTrue(didChange)
        XCTAssertEqual(editor.entries.map(\.id), [terminal.entryID, safari.entryID])
    }

    func testGroupCreatesFolderAtOriginalPosition() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        var editor = LauncherLayoutEditor(entries: [.app(safari), .app(terminal)])

        let folder = editor.group(
            draggedID: terminal.entryID,
            targetID: safari.entryID
        )

        XCTAssertNotNil(folder)
        XCTAssertEqual(editor.entries.count, 1)
        XCTAssertEqual(editor.entries.first?.folderValue?.apps.map(\.id), [safari.id, terminal.id])
    }

    func testMoveRootEntryToInsertionIndexMovesDraggedEntryToEnd() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let xcode = app("Xcode", path: "/Applications/Xcode.app")
        var editor = LauncherLayoutEditor(entries: [.app(safari), .app(terminal), .app(xcode)])

        let didChange = editor.moveRootEntryToInsertionIndex(id: safari.entryID, insertionIndex: 2)

        XCTAssertTrue(didChange)
        XCTAssertEqual(editor.entries.map(\.id), [terminal.entryID, xcode.entryID, safari.entryID])
    }

    func testExtractFolderAppCollapsesFolderWhenOneAppRemains() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let xcode = app("Xcode", path: "/Applications/Xcode.app")
        let folder = FolderItem(id: "dev-folder", name: "开发", apps: [safari, terminal])
        var editor = LauncherLayoutEditor(entries: [.folder(folder), .app(xcode)])

        let extracted = editor.extractFolderAppToRoot(folderID: folder.id, appID: terminal.id)

        XCTAssertEqual(extracted, terminal)
        XCTAssertEqual(editor.entries.map(\.id), [safari.entryID, terminal.entryID, xcode.entryID])
    }

    func testMoveFolderAppMovesDraggedAppToInsertionIndex() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let xcode = app("Xcode", path: "/Applications/Xcode.app")
        let folder = FolderItem(id: "dev-folder", name: "开发", apps: [safari, terminal, xcode])
        var editor = LauncherLayoutEditor(entries: [.folder(folder)])

        let updatedFolder = editor.moveFolderAppToInsertionIndex(
            folderID: folder.id,
            draggedAppID: safari.id,
            insertionIndex: 2
        )

        XCTAssertEqual(updatedFolder?.apps.map(\.id), [terminal.id, xcode.id, safari.id])
        XCTAssertEqual(editor.entries.first?.folderValue?.apps.map(\.id), [terminal.id, xcode.id, safari.id])
    }

    private func app(_ name: String, path: String) -> AppItem {
        AppItem(name: name, url: URL(fileURLWithPath: path), bundleIdentifier: "test.\(name)")
    }
}
