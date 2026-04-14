import SwiftUI

struct LauncherHeaderBar: View {
    @Binding var query: String
    let controlForeground: Color
    let refreshHint: String
    let onOpenSettings: () -> Void
    let onReload: () -> Void
    let searchFocused: FocusState<Bool>.Binding
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            SearchField(text: $query)
                .focused(searchFocused)
                .frame(maxWidth: 540)

            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(controlForeground)
                    .padding(10)
                    .background(theme.controlFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(LaunchDeckStrings.settingsTitle)
            .accessibilityHint(LaunchDeckStrings.settingsAccessibilityHint)

            Button(action: onReload) {
                Label(LaunchDeckStrings.refresh, systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(controlForeground)
                    .padding(10)
                    .background(theme.controlFill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(refreshHint)
            .accessibilityHint(LaunchDeckStrings.reloadAccessibilityHint)
        }
        .frame(maxWidth: .infinity)
    }
}
