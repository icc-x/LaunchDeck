import Foundation
import XCTest
@testable import LaunchDeck

final class LauncherLayoutMergerTests: XCTestCase {
    func testMergePreservesUserLayoutAndAppendsNewApps() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let xcode = app("Xcode", path: "/Applications/Xcode.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")
        let preview = app("Preview", path: "/System/Applications/Preview.app")

        let snapshot = LauncherLayoutSnapshot(entries: [
            .folder(.init(id: "dev-folder", name: "开发", appIDs: [xcode.id, safari.id])),
            .app(id: terminal.id)
        ])

        let merged = LauncherLayoutMerger.merge(
            apps: [safari, xcode, terminal, preview],
            persisted: snapshot
        )

        XCTAssertEqual(merged.map(\.id), [
            "folder:dev-folder",
            "app:\(terminal.id)",
            "app:\(preview.id)"
        ])

        let folderApps = merged.first?.folderValue?.apps.map(\.id) ?? []
        XCTAssertEqual(folderApps, [xcode.id, safari.id])
    }

    func testMergeDropsMissingAppsAndCollapsesInvalidFolders() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")

        let snapshot = LauncherLayoutSnapshot(entries: [
            .folder(.init(id: "broken", name: "", appIDs: ["/Missing.app", safari.id])),
            .app(id: safari.id),
            .folder(.init(id: "single", name: "单个", appIDs: [terminal.id]))
        ])

        let merged = LauncherLayoutMerger.merge(
            apps: [safari, terminal],
            persisted: snapshot
        )

        XCTAssertEqual(merged.map(\.id), [
            "app:\(safari.id)",
            "app:\(terminal.id)"
        ])
        XCTAssertTrue(merged.compactMap(\.folderValue).isEmpty)
    }

    func testSnapshotRoundTripPreservesOrderAndFolder() {
        let safari = app("Safari", path: "/Applications/Safari.app")
        let xcode = app("Xcode", path: "/Applications/Xcode.app")
        let terminal = app("Terminal", path: "/System/Applications/Utilities/Terminal.app")

        let rootEntries: [LauncherEntry] = [
            .folder(.init(id: "dev-tools", name: "开发工具", apps: [xcode, safari])),
            .app(terminal)
        ]

        let snapshot = LauncherLayoutSnapshot(rootEntries: rootEntries)
        let merged = LauncherLayoutMerger.merge(
            apps: [safari, xcode, terminal],
            persisted: snapshot
        )

        XCTAssertEqual(merged, rootEntries)
    }

    private func app(_ name: String, path: String) -> AppItem {
        AppItem(name: name, url: URL(fileURLWithPath: path), bundleIdentifier: "test.\(name)")
    }
}
