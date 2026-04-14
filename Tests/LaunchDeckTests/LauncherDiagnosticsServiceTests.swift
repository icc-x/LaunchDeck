import Foundation
import XCTest
@testable import LaunchDeck

@MainActor
final class LauncherDiagnosticsServiceTests: XCTestCase {
    func testMakeReportCapturesStateSummary() {
        let service = LauncherDiagnosticsService()
        let safari = AppItem(
            name: "Safari",
            url: URL(fileURLWithPath: "/Applications/Safari.app"),
            bundleIdentifier: "com.apple.Safari"
        )
        let folder = FolderItem(id: "dev-folder", name: "开发", apps: [safari])

        let report = service.makeReport(
            preferences: LauncherPreferencesSnapshot(
                appearanceMode: .dark,
                focusSearchOnLaunch: true,
                enableWheelPaging: true,
                restoreLastSession: true,
                showStatusDetails: true,
                prefetchPageDepth: 1,
                folderPageSize: 18,
                minimumVisibleIcons: 30,
                defaultWindowVisibleAreaPercent: 40,
                startupWindowTopInset: 96
            ),
            restoredSession: LauncherSessionSnapshot(
                query: "",
                currentPage: 1,
                activeFolderID: "dev-folder",
                updatedAt: Date()
            ),
            layoutPath: "/tmp/layout.json",
            sessionPath: "/tmp/session.json",
            allAppsCount: 1,
            rootEntries: [.folder(folder)],
            query: "",
            currentPage: 1,
            pagesCount: 2,
            activeFolder: folder,
            isEditing: false,
            isLoading: false,
            lastError: nil,
            statusMessage: "ok"
        )

        XCTAssertEqual(report.layout.totalApps, 1)
        XCTAssertEqual(report.layout.folderCount, 1)
        XCTAssertEqual(report.layout.activeFolderID, "dev-folder")
        XCTAssertEqual(report.storage.layoutPath, "/tmp/layout.json")
        XCTAssertEqual(report.storage.sessionPath, "/tmp/session.json")
    }
}
