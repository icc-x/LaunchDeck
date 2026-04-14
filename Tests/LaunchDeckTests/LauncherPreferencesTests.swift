import Foundation
import XCTest
@testable import LaunchDeck

@MainActor
final class LauncherPreferencesTests: XCTestCase {
    func testDefaultsUseZeroPrefetchDepth() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = LauncherPreferences(userDefaults: defaults)

        XCTAssertFalse(preferences.focusSearchOnLaunch)
        XCTAssertEqual(preferences.prefetchPageDepth, 0)
        XCTAssertEqual(preferences.minimumVisibleIcons, 30)
        XCTAssertEqual(preferences.defaultWindowVisibleAreaPercent, 40)
        XCTAssertEqual(preferences.startupWindowTopInset, 96)
        XCTAssertFalse(preferences.snapshot.focusSearchOnLaunch)
        XCTAssertEqual(preferences.snapshot.prefetchPageDepth, 0)
        XCTAssertEqual(preferences.snapshot.minimumVisibleIcons, 30)
        XCTAssertEqual(preferences.snapshot.defaultWindowVisibleAreaPercent, 40)
        XCTAssertEqual(preferences.snapshot.startupWindowTopInset, 96)
    }

    func testSnapshotReflectsCurrentValues() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = LauncherPreferences(userDefaults: defaults)

        preferences.appearanceMode = .dark
        preferences.focusSearchOnLaunch = false
        preferences.enableWheelPaging = false
        preferences.restoreLastSession = false
        preferences.showStatusDetails = false
        preferences.prefetchPageDepth = 3
        preferences.folderPageSize = 24
        preferences.minimumVisibleIcons = 42
        preferences.defaultWindowVisibleAreaPercent = 55
        preferences.startupWindowTopInset = 120

        XCTAssertEqual(
            preferences.snapshot,
            LauncherPreferencesSnapshot(
                appearanceMode: .dark,
                focusSearchOnLaunch: false,
                enableWheelPaging: false,
                restoreLastSession: false,
                showStatusDetails: false,
                prefetchPageDepth: 3,
                folderPageSize: 24,
                minimumVisibleIcons: 42,
                defaultWindowVisibleAreaPercent: 55,
                startupWindowTopInset: 120
            )
        )
    }

    func testNormalizationClampsOutOfRangeValues() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = LauncherPreferences(userDefaults: defaults)

        preferences.prefetchPageDepth = 9
        preferences.folderPageSize = 99
        preferences.minimumVisibleIcons = 99
        preferences.defaultWindowVisibleAreaPercent = 99
        preferences.startupWindowTopInset = 999

        XCTAssertEqual(preferences.prefetchPageDepth, 3)
        XCTAssertEqual(preferences.folderPageSize, 30)
        XCTAssertEqual(preferences.minimumVisibleIcons, 72)
        XCTAssertEqual(preferences.defaultWindowVisibleAreaPercent, 70)
        XCTAssertEqual(preferences.startupWindowTopInset, 240)
    }

    func testResetRestoresDefaultConfiguration() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = LauncherPreferences(userDefaults: defaults)

        preferences.appearanceMode = .dark
        preferences.focusSearchOnLaunch = false
        preferences.enableWheelPaging = false
        preferences.restoreLastSession = false
        preferences.showStatusDetails = false
        preferences.prefetchPageDepth = 3
        preferences.folderPageSize = 24
        preferences.minimumVisibleIcons = 42
        preferences.defaultWindowVisibleAreaPercent = 55
        preferences.startupWindowTopInset = 120

        preferences.reset()

        XCTAssertEqual(preferences.snapshot, .defaults)
        XCTAssertTrue(preferences.isDefaultConfiguration)
    }

    func testAppearanceModePersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = LauncherPreferences(userDefaults: defaults)

        preferences.appearanceMode = .light

        let restored = LauncherPreferences(userDefaults: defaults)
        XCTAssertEqual(restored.appearanceMode, .light)
    }
}
