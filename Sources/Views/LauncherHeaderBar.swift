import SwiftUI

struct LauncherHeaderBar: View {
    @Binding var query: String
    let isEditing: Bool
    let controlForeground: Color
    let refreshHint: String
    let onFinishEditing: () -> Void
    let onReload: () -> Void
    let searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            SearchField(text: $query)
                .focused(searchFocused)
                .frame(maxWidth: 540)

            Spacer(minLength: 0)

            if isEditing {
                Button(LaunchDeckStrings.done, action: onFinishEditing)
                    .buttonStyle(.borderedProminent)
                    .tint(.primary.opacity(0.14))
                    .foregroundStyle(controlForeground)
            }

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(controlForeground)
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
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
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help(refreshHint)
            .accessibilityHint(LaunchDeckStrings.reloadAccessibilityHint)
        }
        .frame(maxWidth: .infinity)
    }
}
