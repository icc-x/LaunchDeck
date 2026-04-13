import SwiftUI

@main
struct LaunchDeckApp: App {
    private enum WindowLayout {
        static let minimumVisibleIcons = 30
        static let minimumSize = AppGridPageView.minimumWindowSize(for: minimumVisibleIcons)
    }

    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences: LauncherPreferences
    @StateObject private var store: LauncherStore

    init() {
        let preferences = LauncherPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        _store = StateObject(wrappedValue: LauncherStore(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup(LaunchDeckStrings.windowTitle, id: "main") {
            ContentView(store: store, preferences: preferences)
                .frame(minWidth: WindowLayout.minimumSize.width, minHeight: WindowLayout.minimumSize.height)
                .preferredColorScheme(preferences.appearanceMode.preferredColorScheme)
                .task {
                    appDelegate.onWillTerminate = { [store] in
                        await store.flushPendingPersistence()
                    }
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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: WindowLayout.minimumSize.width, height: WindowLayout.minimumSize.height)
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

        Settings {
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
    }
}
