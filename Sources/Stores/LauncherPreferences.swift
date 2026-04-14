import Foundation
import SwiftUI

enum LauncherAppearanceMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var localizedTitle: String {
        switch self {
        case .system:
            LaunchDeckStrings.appearanceFollowSystem
        case .light:
            LaunchDeckStrings.appearanceLight
        case .dark:
            LaunchDeckStrings.appearanceDark
        }
    }
}

struct LauncherPreferencesSnapshot: Codable, Equatable, Sendable {
    var appearanceMode: LauncherAppearanceMode
    var focusSearchOnLaunch: Bool
    var enableWheelPaging: Bool
    var restoreLastSession: Bool
    var showStatusDetails: Bool
    var prefetchPageDepth: Int
    var folderPageSize: Int
    var minimumVisibleIcons: Int
    var defaultWindowVisibleAreaPercent: Int
    var startupWindowTopInset: Int

    static let defaults = LauncherPreferencesSnapshot(
        appearanceMode: .system,
        focusSearchOnLaunch: false,
        enableWheelPaging: true,
        restoreLastSession: true,
        showStatusDetails: true,
        prefetchPageDepth: 0,
        folderPageSize: 18,
        minimumVisibleIcons: 30,
        defaultWindowVisibleAreaPercent: 40,
        startupWindowTopInset: 96
    )

    var defaultWindowVisibleAreaRatio: CGFloat {
        CGFloat(defaultWindowVisibleAreaPercent) / 100
    }
}

@MainActor
final class LauncherPreferences: ObservableObject {
    enum Key {
        static let appearanceMode = "preferences.appearanceMode"
        static let focusSearchOnLaunch = "preferences.focusSearchOnLaunch"
        static let enableWheelPaging = "preferences.enableWheelPaging"
        static let restoreLastSession = "preferences.restoreLastSession"
        static let showStatusDetails = "preferences.showStatusDetails"
        static let prefetchPageDepth = "preferences.prefetchPageDepth"
        static let folderPageSize = "preferences.folderPageSize"
        static let minimumVisibleIcons = "preferences.minimumVisibleIcons"
        static let defaultWindowVisibleAreaPercent = "preferences.defaultWindowVisibleAreaPercent"
        static let startupWindowTopInset = "preferences.startupWindowTopInset"
    }

    private let userDefaults: UserDefaults

    @Published var appearanceMode: LauncherAppearanceMode {
        didSet { persist(key: Key.appearanceMode, value: appearanceMode.rawValue) }
    }
    @Published var focusSearchOnLaunch: Bool {
        didSet { persist(key: Key.focusSearchOnLaunch, value: focusSearchOnLaunch) }
    }
    @Published var enableWheelPaging: Bool {
        didSet { persist(key: Key.enableWheelPaging, value: enableWheelPaging) }
    }
    @Published var restoreLastSession: Bool {
        didSet { persist(key: Key.restoreLastSession, value: restoreLastSession) }
    }
    @Published var showStatusDetails: Bool {
        didSet { persist(key: Key.showStatusDetails, value: showStatusDetails) }
    }
    @Published var prefetchPageDepth: Int {
        didSet {
            let normalized = Self.normalizedPrefetchPageDepth(prefetchPageDepth)
            if normalized != prefetchPageDepth {
                prefetchPageDepth = normalized
                return
            }
            persist(key: Key.prefetchPageDepth, value: normalized)
        }
    }
    @Published var folderPageSize: Int {
        didSet {
            let normalized = Self.normalizedFolderPageSize(folderPageSize)
            if normalized != folderPageSize {
                folderPageSize = normalized
                return
            }
            persist(key: Key.folderPageSize, value: normalized)
        }
    }
    @Published var minimumVisibleIcons: Int {
        didSet {
            let normalized = Self.normalizedMinimumVisibleIcons(minimumVisibleIcons)
            if normalized != minimumVisibleIcons {
                minimumVisibleIcons = normalized
                return
            }
            persist(key: Key.minimumVisibleIcons, value: normalized)
        }
    }
    @Published var defaultWindowVisibleAreaPercent: Int {
        didSet {
            let normalized = Self.normalizedDefaultWindowVisibleAreaPercent(defaultWindowVisibleAreaPercent)
            if normalized != defaultWindowVisibleAreaPercent {
                defaultWindowVisibleAreaPercent = normalized
                return
            }
            persist(key: Key.defaultWindowVisibleAreaPercent, value: normalized)
        }
    }
    @Published var startupWindowTopInset: Int {
        didSet {
            let normalized = Self.normalizedStartupWindowTopInset(startupWindowTopInset)
            if normalized != startupWindowTopInset {
                startupWindowTopInset = normalized
                return
            }
            persist(key: Key.startupWindowTopInset, value: normalized)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let resolved = Self.resolvedSnapshot(userDefaults: userDefaults)
        appearanceMode = resolved.appearanceMode
        focusSearchOnLaunch = resolved.focusSearchOnLaunch
        enableWheelPaging = resolved.enableWheelPaging
        restoreLastSession = resolved.restoreLastSession
        showStatusDetails = resolved.showStatusDetails
        prefetchPageDepth = resolved.prefetchPageDepth
        folderPageSize = resolved.folderPageSize
        minimumVisibleIcons = resolved.minimumVisibleIcons
        defaultWindowVisibleAreaPercent = resolved.defaultWindowVisibleAreaPercent
        startupWindowTopInset = resolved.startupWindowTopInset
    }

    var snapshot: LauncherPreferencesSnapshot {
        LauncherPreferencesSnapshot(
            appearanceMode: appearanceMode,
            focusSearchOnLaunch: focusSearchOnLaunch,
            enableWheelPaging: enableWheelPaging,
            restoreLastSession: restoreLastSession,
            showStatusDetails: showStatusDetails,
            prefetchPageDepth: prefetchPageDepth,
            folderPageSize: folderPageSize,
            minimumVisibleIcons: minimumVisibleIcons,
            defaultWindowVisibleAreaPercent: defaultWindowVisibleAreaPercent,
            startupWindowTopInset: startupWindowTopInset
        )
    }

    var isDefaultConfiguration: Bool {
        snapshot == .defaults
    }

    func reset() {
        appearanceMode = LauncherPreferencesSnapshot.defaults.appearanceMode
        focusSearchOnLaunch = LauncherPreferencesSnapshot.defaults.focusSearchOnLaunch
        enableWheelPaging = LauncherPreferencesSnapshot.defaults.enableWheelPaging
        restoreLastSession = LauncherPreferencesSnapshot.defaults.restoreLastSession
        showStatusDetails = LauncherPreferencesSnapshot.defaults.showStatusDetails
        prefetchPageDepth = LauncherPreferencesSnapshot.defaults.prefetchPageDepth
        folderPageSize = LauncherPreferencesSnapshot.defaults.folderPageSize
        minimumVisibleIcons = LauncherPreferencesSnapshot.defaults.minimumVisibleIcons
        defaultWindowVisibleAreaPercent = LauncherPreferencesSnapshot.defaults.defaultWindowVisibleAreaPercent
        startupWindowTopInset = LauncherPreferencesSnapshot.defaults.startupWindowTopInset
    }

    static func resolvedSnapshot(userDefaults: UserDefaults = .standard) -> LauncherPreferencesSnapshot {
        LauncherPreferencesSnapshot(
            appearanceMode: LauncherAppearanceMode(rawValue: userDefaults.string(forKey: Key.appearanceMode) ?? "") ?? .system,
            focusSearchOnLaunch: userDefaults.object(forKey: Key.focusSearchOnLaunch) as? Bool ?? LauncherPreferencesSnapshot.defaults.focusSearchOnLaunch,
            enableWheelPaging: userDefaults.object(forKey: Key.enableWheelPaging) as? Bool ?? LauncherPreferencesSnapshot.defaults.enableWheelPaging,
            restoreLastSession: userDefaults.object(forKey: Key.restoreLastSession) as? Bool ?? LauncherPreferencesSnapshot.defaults.restoreLastSession,
            showStatusDetails: userDefaults.object(forKey: Key.showStatusDetails) as? Bool ?? LauncherPreferencesSnapshot.defaults.showStatusDetails,
            prefetchPageDepth: normalizedPrefetchPageDepth(
                userDefaults.object(forKey: Key.prefetchPageDepth) as? Int ?? LauncherPreferencesSnapshot.defaults.prefetchPageDepth
            ),
            folderPageSize: normalizedFolderPageSize(
                userDefaults.object(forKey: Key.folderPageSize) as? Int ?? LauncherPreferencesSnapshot.defaults.folderPageSize
            ),
            minimumVisibleIcons: normalizedMinimumVisibleIcons(
                userDefaults.object(forKey: Key.minimumVisibleIcons) as? Int ?? LauncherPreferencesSnapshot.defaults.minimumVisibleIcons
            ),
            defaultWindowVisibleAreaPercent: normalizedDefaultWindowVisibleAreaPercent(
                userDefaults.object(forKey: Key.defaultWindowVisibleAreaPercent) as? Int ?? LauncherPreferencesSnapshot.defaults.defaultWindowVisibleAreaPercent
            ),
            startupWindowTopInset: normalizedStartupWindowTopInset(
                userDefaults.object(forKey: Key.startupWindowTopInset) as? Int ?? LauncherPreferencesSnapshot.defaults.startupWindowTopInset
            )
        )
    }

    private func persist(key: String, value: Any) {
        userDefaults.set(value, forKey: key)
    }

    static func normalizedPrefetchPageDepth(_ value: Int) -> Int {
        max(0, min(value, 3))
    }

    static func normalizedFolderPageSize(_ value: Int) -> Int {
        max(9, min(value, 30))
    }

    static func normalizedMinimumVisibleIcons(_ value: Int) -> Int {
        max(12, min(value, 72))
    }

    static func normalizedDefaultWindowVisibleAreaPercent(_ value: Int) -> Int {
        max(20, min(value, 70))
    }

    static func normalizedStartupWindowTopInset(_ value: Int) -> Int {
        max(24, min(value, 240))
    }
}
