import Foundation

struct LauncherPreferencesSnapshot: Codable, Equatable, Sendable {
    var focusSearchOnLaunch: Bool
    var enableWheelPaging: Bool
    var restoreLastSession: Bool
    var showStatusDetails: Bool
    var prefetchPageDepth: Int
    var folderPageSize: Int

    static let defaults = LauncherPreferencesSnapshot(
        focusSearchOnLaunch: true,
        enableWheelPaging: true,
        restoreLastSession: true,
        showStatusDetails: true,
        prefetchPageDepth: 1,
        folderPageSize: 18
    )
}

@MainActor
final class LauncherPreferences: ObservableObject {
    private enum Key {
        static let focusSearchOnLaunch = "preferences.focusSearchOnLaunch"
        static let enableWheelPaging = "preferences.enableWheelPaging"
        static let restoreLastSession = "preferences.restoreLastSession"
        static let showStatusDetails = "preferences.showStatusDetails"
        static let prefetchPageDepth = "preferences.prefetchPageDepth"
        static let folderPageSize = "preferences.folderPageSize"
    }

    private let userDefaults: UserDefaults

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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        focusSearchOnLaunch = userDefaults.object(forKey: Key.focusSearchOnLaunch) as? Bool ?? true
        enableWheelPaging = userDefaults.object(forKey: Key.enableWheelPaging) as? Bool ?? true
        restoreLastSession = userDefaults.object(forKey: Key.restoreLastSession) as? Bool ?? true
        showStatusDetails = userDefaults.object(forKey: Key.showStatusDetails) as? Bool ?? true
        prefetchPageDepth = Self.normalizedPrefetchPageDepth(userDefaults.object(forKey: Key.prefetchPageDepth) as? Int ?? 1)
        folderPageSize = Self.normalizedFolderPageSize(userDefaults.object(forKey: Key.folderPageSize) as? Int ?? 18)
    }

    var snapshot: LauncherPreferencesSnapshot {
        LauncherPreferencesSnapshot(
            focusSearchOnLaunch: focusSearchOnLaunch,
            enableWheelPaging: enableWheelPaging,
            restoreLastSession: restoreLastSession,
            showStatusDetails: showStatusDetails,
            prefetchPageDepth: prefetchPageDepth,
            folderPageSize: folderPageSize
        )
    }

    var isDefaultConfiguration: Bool {
        snapshot == .defaults
    }

    func reset() {
        focusSearchOnLaunch = LauncherPreferencesSnapshot.defaults.focusSearchOnLaunch
        enableWheelPaging = LauncherPreferencesSnapshot.defaults.enableWheelPaging
        restoreLastSession = LauncherPreferencesSnapshot.defaults.restoreLastSession
        showStatusDetails = LauncherPreferencesSnapshot.defaults.showStatusDetails
        prefetchPageDepth = LauncherPreferencesSnapshot.defaults.prefetchPageDepth
        folderPageSize = LauncherPreferencesSnapshot.defaults.folderPageSize
    }

    private func persist(key: String, value: Any) {
        userDefaults.set(value, forKey: key)
    }

    private static func normalizedPrefetchPageDepth(_ value: Int) -> Int {
        max(0, min(value, 3))
    }

    private static func normalizedFolderPageSize(_ value: Int) -> Int {
        max(9, min(value, 30))
    }
}
