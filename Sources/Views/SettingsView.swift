import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: LauncherPreferences
    let layoutStoragePath: String
    let sessionStoragePath: String
    let onExportDiagnostics: () -> Void
    let onClearSession: () -> Void
    let onResetPreferences: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

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

                Section(LaunchDeckStrings.settingsWindowSection) {
                    Text(LaunchDeckStrings.settingsWindowDescription)
                        .foregroundStyle(.secondary)

                    Stepper(
                        value: $preferences.defaultWindowVisibleAreaPercent,
                        in: 20...70,
                        step: 5
                    ) {
                        LabeledContent(
                            LaunchDeckStrings.settingsDefaultWindowVisibleArea,
                            value: "\(preferences.defaultWindowVisibleAreaPercent)%"
                        )
                    }

                    Stepper(
                        value: $preferences.minimumVisibleIcons,
                        in: 12...72,
                        step: 6
                    ) {
                        LabeledContent(
                            LaunchDeckStrings.settingsMinimumVisibleIcons,
                            value: "\(preferences.minimumVisibleIcons)"
                        )
                    }

                    Stepper(
                        value: $preferences.startupWindowTopInset,
                        in: 24...240,
                        step: 8
                    ) {
                        LabeledContent(
                            LaunchDeckStrings.settingsStartupWindowTopInset,
                            value: "\(preferences.startupWindowTopInset)"
                        )
                    }
                }

                Section(LaunchDeckStrings.settingsAppearanceSection) {
                    Picker(LaunchDeckStrings.settingsAppearanceMode, selection: $preferences.appearanceMode) {
                        ForEach(LauncherAppearanceMode.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

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
            .scrollContentBackground(.automatic)
            .formStyle(.grouped)
            .padding(20)
        }
        .background(SettingsWindowConfigurationView())
        .contentShape(Rectangle())
        .frame(minWidth: 520, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
