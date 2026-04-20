import SwiftUI

@main
struct LaunchDeckApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences: LauncherPreferences
    @StateObject private var store: LauncherStore

    init() {
        let preferences = LauncherPreferences()
        let store = LauncherStore(preferences: preferences)
        _preferences = StateObject(wrappedValue: preferences)
        _store = StateObject(wrappedValue: store)

        // Install the termination hook exactly once during App construction so that it
        // cannot be overwritten by a later Scene re-creation (e.g. multi-window future).
        AppDelegate.installTerminationHook { [weak store] in
            await store?.flushPendingPersistence()
        }
    }

    private var minimumWindowSize: CGSize {
        AppGridPageView.minimumWindowSize(for: preferences.minimumVisibleIcons)
    }

    var body: some Scene {
        WindowGroup(LaunchDeckStrings.windowTitle, id: "main") {
            ContentView(store: store, preferences: preferences)
                .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
                .preferredColorScheme(preferences.appearanceMode.preferredColorScheme)
                .onAppear {
                    appDelegate.updateMainWindowMinimumSize()
                }
                .onChange(of: preferences.restoreLastSession) { _, _ in
                    Task {
                        await store.handleRestoreLastSessionPreferenceChange()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        Task {
                            await store.flushPendingPersistence()
                        }
                    }
                }
                .onChange(of: preferences.minimumVisibleIcons) { _, _ in
                    appDelegate.updateMainWindowMinimumSize()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: minimumWindowSize.width, height: minimumWindowSize.height)
        .commands {
            LaunchDeckCommands(
                onReload: {
                    Task { await store.reload() }
                },
                onExportDiagnostics: {
                    Task { await store.exportDiagnostics() }
                }
            )
        }

        Window(LaunchDeckStrings.settingsTitle, id: "settings") {
            SettingsView(
                preferences: preferences,
                layoutStoragePath: store.layoutStoragePath,
                sessionStoragePath: store.sessionStoragePath,
                onExportDiagnostics: {
                    Task { await store.exportDiagnostics() }
                },
                onClearSession: {
                    Task { await store.clearRestoredSession() }
                },
                onResetPreferences: {
                    preferences.reset()
                    store.notePreferencesReset()
                }
            )
            .preferredColorScheme(preferences.appearanceMode.preferredColorScheme)
        }
        .defaultSize(width: 520, height: 420)
    }
}
