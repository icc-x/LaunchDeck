import SwiftUI

struct LaunchpadBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: theme.backdropBase,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: theme.backdropGlow,
                center: .topTrailing,
                startRadius: 24,
                endRadius: 420
            )

            LinearGradient(
                colors: theme.backdropTint,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
