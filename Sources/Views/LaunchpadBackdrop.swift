import AppKit
import SwiftUI

struct LaunchpadBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            NativeMaterialBackdrop(
                opacity: 0.97,
                material: colorScheme == .dark ? .hudWindow : .underWindowBackground
            )

            // Keep a subtle neutral tint so cards stay readable on bright wallpapers.
            LinearGradient(
                colors: theme.backdropTint,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct NativeMaterialBackdrop: NSViewRepresentable {
    let opacity: CGFloat
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.alphaValue = opacity
    }
}
