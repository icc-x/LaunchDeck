import Combine
import SwiftUI

/// A single app tile rendered inside an open folder. Uses a native `Button` so VoiceOver
/// reports a button role, Enter/Space activate it, and the tap is treated as a first-class
/// activation instead of a gesture guess.
struct FolderAppButton: View {
    let app: AppItem
    let isBeingDragged: Bool
    let iconProvider: AppIconProvider
    let action: () -> Void
    let onBeginDragging: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var iconReloadToken = 0
    @State private var iconSubscription: AnyCancellable?

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        let _ = iconReloadToken
        Button(action: action) {
            VStack(spacing: 8) {
                Image(nsImage: iconProvider.icon(for: app))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 70, height: 70)

                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 96)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isBeingDragged ? 0.06 : 1)
        .scaleEffect(isBeingDragged ? 0.92 : (isHovering ? 1.02 : 1))
        .blur(radius: isBeingDragged ? 1.1 : 0)
        .launchAnimation(LaunchMotion.hover, value: isHovering)
        .launchAnimation(LaunchMotion.reorder, value: isBeingDragged)
        .onHover { isHovering = $0 }
        .onAppear {
            if iconSubscription == nil {
                iconSubscription = iconProvider.iconLoadedPublisher(for: [app.id]).sink { _ in
                    iconReloadToken &+= 1
                }
                iconReloadToken &+= 1
            }
        }
        .onDisappear {
            iconSubscription?.cancel()
            iconSubscription = nil
        }
        .help(app.name)
        .accessibilityLabel(app.name)
        .accessibilityHint(LaunchDeckStrings.accessibilityHintLaunchApp)
        .onDrag {
            onBeginDragging()
            return NSItemProvider(object: "folder:\(app.id)" as NSString)
        } preview: {
            dragPreview
        }
    }

    private var dragPreview: some View {
        VStack(spacing: 8) {
            Image(nsImage: iconProvider.icon(for: app))
                .resizable()
                .interpolation(.high)
                .frame(width: 70, height: 70)

            Text(app.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 96)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.dragPreviewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.dragPreviewStroke, lineWidth: 1)
                )
        )
        .scaleEffect(1.05)
        .shadow(color: theme.dragPreviewShadow, radius: 18, y: 10)
        .compositingGroup()
    }
}

struct FolderAppPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.placeholderFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.placeholderStroke, lineWidth: 1)
                )
                .frame(width: 70, height: 70)

            VStack(spacing: 4) {
                Capsule()
                    .fill(theme.placeholderSecondaryFill)
                    .frame(width: 52, height: 9)
                Capsule()
                    .fill(theme.placeholderSecondaryFill.opacity(0.78))
                    .frame(width: 36, height: 7)
            }
        }
            .padding(.top, 4)
            .frame(width: FolderGridLayout.tileWidth, height: FolderGridLayout.tileHeight)
            .scaleEffect(0.98)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}

#Preview("Folder app button") {
    FolderAppButton(
        app: LaunchDeckPreviewFixtures.safari,
        isBeingDragged: false,
        iconProvider: AppIconProvider(),
        action: {},
        onBeginDragging: {}
    )
    .padding(24)
    .background(LaunchpadBackdrop())
}

#Preview("Folder app placeholder") {
    FolderAppPlaceholderView()
        .padding(24)
        .background(LaunchpadBackdrop())
}
