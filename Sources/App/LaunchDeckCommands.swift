import SwiftUI

struct LaunchDeckCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let onReload: () -> Void
    let onExportDiagnostics: () -> Void

    var body: some Commands {
        CommandMenu(LaunchDeckStrings.commandMenuTitle) {
            Button(LaunchDeckStrings.refreshApps, action: onReload)
                .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button(LaunchDeckStrings.exportDiagnosticsCommand, action: onExportDiagnostics)
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .appSettings) {
            Button(LaunchDeckStrings.settingsTitle) {
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}
