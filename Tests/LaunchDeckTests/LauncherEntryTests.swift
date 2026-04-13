import Foundation
import XCTest
@testable import LaunchDeck

final class LauncherEntryTests: XCTestCase {
    func testAppEntryComputedProperties() {
        let app = AppItem(
            name: "Safari",
            url: URL(fileURLWithPath: "/Applications/Safari.app"),
            bundleIdentifier: "com.apple.Safari"
        )
        let entry = LauncherEntry.app(app)

        XCTAssertEqual(entry.id, "app:/Applications/Safari.app")
        XCTAssertEqual(entry.displayName, "Safari")
        XCTAssertEqual(entry.flattenedApps, [app])
        XCTAssertEqual(entry.appValue, app)
        XCTAssertNil(entry.folderValue)
    }

    func testFolderEntryComputedProperties() {
        let firstApp = AppItem(
            name: "Xcode",
            url: URL(fileURLWithPath: "/Applications/Xcode.app"),
            bundleIdentifier: "com.apple.dt.Xcode"
        )
        let secondApp = AppItem(
            name: "Terminal",
            url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            bundleIdentifier: "com.apple.Terminal"
        )
        let folder = FolderItem(id: "dev-tools", name: "开发工具", apps: [firstApp, secondApp])
        let entry = LauncherEntry.folder(folder)

        XCTAssertEqual(entry.id, "folder:dev-tools")
        XCTAssertEqual(entry.displayName, "开发工具")
        XCTAssertEqual(entry.flattenedApps, [firstApp, secondApp])
        XCTAssertNil(entry.appValue)
        XCTAssertEqual(entry.folderValue, folder)
    }
}
