import SwiftUI

struct SearchField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.controlSubtleForeground)

            TextField("搜索应用", text: $text)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.controlForeground)
                .disableAutocorrection(true)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.controlSubtleForeground)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(theme.searchFieldStroke, lineWidth: 1)
        )
    }
}
