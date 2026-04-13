import SwiftUI

@main
struct LaunchDeckApp: App {
    private enum WindowLayout {
        static let minimumVisibleIcons = 30
        static let minimumSize = AppGridPageView.minimumWindowSize(for: minimumVisibleIcons)
    }

    @Environment(\.scenePhase) private var scenePhase
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LauncherStore()

    var body: some Scene {
        WindowGroup("LaunchDeck", id: "main") {
            ContentView(store: store)
                .frame(minWidth: WindowLayout.minimumSize.width, minHeight: WindowLayout.minimumSize.height)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active {
                        store.flushPendingPersistence()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: WindowLayout.minimumSize.width, height: WindowLayout.minimumSize.height)
        .commands {
            CommandMenu("启动台") {
                Button("刷新应用列表") {
                    Task { await store.reload() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
