import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: LauncherPreferences
    let layoutStoragePath: String
    let sessionStoragePath: String
    let onExportDiagnostics: () -> Void
    let onClearSession: () -> Void
    let onResetPreferences: () -> Void

    var body: some View {
        Form {
            Section(LaunchDeckStrings.settingsInteractionSection) {
                Toggle(LaunchDeckStrings.settingsFocusSearchOnLaunch, isOn: $preferences.focusSearchOnLaunch)
                Toggle(LaunchDeckStrings.settingsEnableWheelPaging, isOn: $preferences.enableWheelPaging)
                Stepper(
                    value: $preferences.prefetchPageDepth,
                    in: 0...3
                ) {
                    LabeledContent(LaunchDeckStrings.settingsPrefetchDepth, value: "\(preferences.prefetchPageDepth)")
                }
                Stepper(
                    value: $preferences.folderPageSize,
                    in: 9...30
                ) {
                    LabeledContent(LaunchDeckStrings.settingsFolderPageSize, value: "\(preferences.folderPageSize)")
                }
            }

            Section(LaunchDeckStrings.settingsAppearanceSection) {
                Toggle(LaunchDeckStrings.settingsShowStatusDetails, isOn: $preferences.showStatusDetails)
            }

            Section(LaunchDeckStrings.settingsSessionSection) {
                Toggle(LaunchDeckStrings.settingsRestoreLastSession, isOn: $preferences.restoreLastSession)
                LabeledContent(LaunchDeckStrings.settingsLayoutPath, value: layoutStoragePath)
                    .lineLimit(2)
                    .textSelection(.enabled)
                LabeledContent(LaunchDeckStrings.settingsSessionPath, value: sessionStoragePath)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Button(LaunchDeckStrings.settingsClearSession, action: onClearSession)
            }

            Section(LaunchDeckStrings.settingsDiagnosticsSection) {
                Text(LaunchDeckStrings.settingsDiagnosticsDescription)
                    .foregroundStyle(.secondary)
                Button(LaunchDeckStrings.settingsExportDiagnostics, action: onExportDiagnostics)
            }

            Section {
                Button(LaunchDeckStrings.settingsResetDefaults, action: onResetPreferences)
                    .disabled(preferences.isDefaultConfiguration)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }
}
