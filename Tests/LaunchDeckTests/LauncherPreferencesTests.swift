import Foundation
import XCTest
@testable import LaunchDeck

@MainActor
final class LauncherPreferencesTests: XCTestCase {
    func testDefaultsUseZeroPrefetchDepth() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = LauncherPreferences(userDefaults: defaults)

        XCTAssertEqual(preferences.prefetchPageDepth, 0)
        XCTAssertEqual(preferences.snapshot.prefetchPageDepth, 0)
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

        XCTAssertEqual(
            preferences.snapshot,
            LauncherPreferencesSnapshot(
                appearanceMode: .dark,
                focusSearchOnLaunch: false,
                enableWheelPaging: false,
                restoreLastSession: false,
                showStatusDetails: false,
                prefetchPageDepth: 3,
                folderPageSize: 24
            )
        )
    }

    func testNormalizationClampsOutOfRangeValues() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = LauncherPreferences(userDefaults: defaults)

        preferences.prefetchPageDepth = 9
        preferences.folderPageSize = 99

        XCTAssertEqual(preferences.prefetchPageDepth, 3)
        XCTAssertEqual(preferences.folderPageSize, 30)
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
