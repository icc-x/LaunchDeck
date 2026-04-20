import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct LauncherTileView: View {
    let entry: LauncherEntry
    let tileWidth: CGFloat
    let iconProvider: AppIconProvider
    let folderPreviewIconProvider: AppIconProvider
    let isSearchMode: Bool
    let isBeingDragged: Bool
    let namespace: Namespace.ID
    let onLaunch: (AppItem) -> Void
    let onOpenFolder: (FolderItem) -> Void
    let onBeginDragging: (LauncherEntry) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var iconReloadToken = 0
    @State private var iconSubscription: AnyCancellable?
    @State private var subscribedIconKey = ""

    private struct Metrics {
        let tileWidth: CGFloat

        private enum Ratio {
            static let minTileWidth: CGFloat = 104
            static let maxTileWidth: CGFloat = 122
            static let tileHeight: CGFloat = 1.14
            static let iconToLabelSpacing: CGFloat = 0.055
            static let labelMaxWidth: CGFloat = 0.94
            static let appIconFillMin: CGFloat = 0.82
            static let appIconFillMax: CGFloat = 0.88
            static let folderSurfaceFillMin: CGFloat = 0.88
            static let folderSurfaceFillMax: CGFloat = 0.93
            static let folderCornerRadius: CGFloat = 0.15
            static let miniIconFill: CGFloat = 0.34
            static let miniIconCornerRadius: CGFloat = 0.21
            static let miniGridSpacing: CGFloat = 0.12
            static let dropOutlineBottomInset: CGFloat = 0.24
        }

        private var widthProgress: CGFloat {
            let denominator = max(1, Ratio.maxTileWidth - Ratio.minTileWidth)
            let normalized = (tileWidth - Ratio.minTileWidth) / denominator
            return min(1, max(0, normalized))
        }

        private func interpolated(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
            minValue + (maxValue - minValue) * widthProgress
        }

        var tileHeight: CGFloat { tileWidth * Ratio.tileHeight }
        var iconToLabelSpacing: CGFloat { tileWidth * Ratio.iconToLabelSpacing }
        var labelMaxWidth: CGFloat { tileWidth * Ratio.labelMaxWidth }
        var appIconSize: CGFloat { tileWidth * interpolated(Ratio.appIconFillMin, Ratio.appIconFillMax) }
        var folderSurfaceSize: CGFloat { tileWidth * interpolated(Ratio.folderSurfaceFillMin, Ratio.folderSurfaceFillMax) }
        var folderCornerRadius: CGFloat { tileWidth * Ratio.folderCornerRadius }
        var miniIconSize: CGFloat { folderSurfaceSize * Ratio.miniIconFill }
        var miniIconCornerRadius: CGFloat { miniIconSize * Ratio.miniIconCornerRadius }
        var miniGridSpacing: CGFloat { miniIconSize * Ratio.miniGridSpacing }
        var dropOutlineBottomInset: CGFloat { tileWidth * Ratio.dropOutlineBottomInset }
    }

    private var metrics: Metrics {
        Metrics(tileWidth: tileWidth)
    }

    private var tileSize: CGSize {
        CGSize(width: metrics.tileWidth, height: metrics.tileHeight)
    }

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        let _ = iconReloadToken
        Button(action: handleTap) {
            VStack(spacing: metrics.iconToLabelSpacing) {
                iconSurface
                Text(entry.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: metrics.labelMaxWidth)
            }
            .frame(width: tileSize.width, height: tileSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isBeingDragged ? 0.06 : 1)
        .scaleEffect(isBeingDragged ? 0.92 : (isHovering ? 1.03 : 1))
        .blur(radius: isBeingDragged ? 1.2 : 0)
        .shadow(
            color: isBeingDragged ? .clear : (isHovering ? theme.tileShadowHover : theme.tileShadowNormal),
            radius: isBeingDragged ? 0 : (isHovering ? 6 : 3),
            y: isBeingDragged ? 0 : (isHovering ? 3 : 1)
        )
        .launchAnimation(LaunchMotion.hover, value: isHovering)
        .launchAnimation(LaunchMotion.reorder, value: isBeingDragged)
        .help(entry.displayName)
        .accessibilityLabel(entry.displayName)
        .accessibilityHint(accessibilityHint)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            refreshIconSubscription(force: true)
        }
        .onChange(of: observedIconKey) { _, _ in
            refreshIconSubscription(force: false)
        }
        .onDisappear {
            iconSubscription?.cancel()
            iconSubscription = nil
            subscribedIconKey = ""
        }
        // Always apply `.onDrag`, but veto the drag via an empty item provider when we're in
        // search mode. Returning different modifier stacks via an `if` would cause SwiftUI to
        // tear down and re-identify the view on every search-mode toggle.
        .onDrag {
            guard !isSearchMode else { return NSItemProvider() }
            onBeginDragging(entry)
            return NSItemProvider(object: entry.id as NSString)
        } preview: {
            dragPreview
        }
    }

    private var accessibilityHint: String {
        switch entry {
        case .app:
            return LaunchDeckStrings.accessibilityHintLaunchApp
        case .folder:
            return LaunchDeckStrings.accessibilityHintOpenFolder
        }
    }

    private var observedIconIDs: [String] {
        switch entry {
        case let .app(app):
            return [app.id]
        case let .folder(folder):
            return folder.apps.prefix(4).map(\.id)
        }
    }

    private var observedIconKey: String {
        observedIconIDs.joined(separator: "|")
    }

    @ViewBuilder
    private var iconSurface: some View {
        switch entry {
        case let .app(app):
            appIconSurface(app)
        case let .folder(folder):
            folderIconSurface(folder)
        }
    }

    private func appIconSurface(_ app: AppItem) -> some View {
        Image(nsImage: iconProvider.icon(for: app))
            .resizable()
            .interpolation(.high)
            .frame(width: metrics.appIconSize, height: metrics.appIconSize)
    }

    private func folderIconSurface(_ folder: FolderItem) -> some View {
        VStack(spacing: 5) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(metrics.miniIconSize), spacing: metrics.miniGridSpacing), count: 2),
                spacing: metrics.miniGridSpacing
            ) {
                ForEach(Array(folder.apps.prefix(4).enumerated()), id: \.offset) { _, app in
                    Image(nsImage: folderPreviewIconProvider.icon(for: app))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: metrics.miniIconSize, height: metrics.miniIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.miniIconCornerRadius, style: .continuous))
                }
            }
        }
        .frame(width: metrics.folderSurfaceSize, height: metrics.folderSurfaceSize)
        .background(theme.folderCardFill, in: RoundedRectangle(cornerRadius: metrics.folderCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.folderCornerRadius, style: .continuous)
                .stroke(theme.cardStroke.opacity(isHovering ? 1 : 0.72), lineWidth: 1)
        )
        .matchedGeometryEffect(id: "folder-card-\(folder.id)", in: namespace)
    }

    private func handleTap() {
        switch entry {
        case let .app(app):
            onLaunch(app)
        case let .folder(folder):
            onOpenFolder(folder)
        }
    }

    private var dragPreview: some View {
        VStack(spacing: metrics.iconToLabelSpacing) {
            iconSurface
            Text(entry.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: metrics.labelMaxWidth)
        }
        .padding(.horizontal, max(8, tileWidth * 0.07))
        .padding(.vertical, max(8, tileWidth * 0.06))
        .background(
            RoundedRectangle(cornerRadius: metrics.folderCornerRadius * 1.1, style: .continuous)
                .fill(theme.dragPreviewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.folderCornerRadius * 1.1, style: .continuous)
                        .stroke(theme.dragPreviewStroke, lineWidth: 1)
                )
        )
        .scaleEffect(1.05)
        .shadow(color: theme.dragPreviewShadow, radius: 18, y: 10)
        .compositingGroup()
    }

    private func refreshIconSubscription(force: Bool) {
        let key = observedIconKey
        guard force || key != subscribedIconKey else { return }

        iconSubscription?.cancel()
        subscribedIconKey = key
        guard !observedIconIDs.isEmpty else {
            iconSubscription = nil
            return
        }

        iconSubscription = activeIconProvider.iconLoadedPublisher(for: observedIconIDs).sink { _ in
            iconReloadToken &+= 1
        }

        // Pull once after (re)subscribe so already-cached icons can render immediately.
        iconReloadToken &+= 1
    }

    private var activeIconProvider: AppIconProvider {
        switch entry {
        case .app:
            return iconProvider
        case .folder:
            return folderPreviewIconProvider
        }
    }
}

private struct LauncherTilePreviewHost: View {
    let entry: LauncherEntry
    @Namespace private var namespace

    var body: some View {
        LauncherTileView(
            entry: entry,
            tileWidth: 112,
            iconProvider: AppIconProvider(),
            folderPreviewIconProvider: AppIconProvider(),
            isSearchMode: false,
            isBeingDragged: false,
            namespace: namespace,
            onLaunch: { _ in },
            onOpenFolder: { _ in },
            onBeginDragging: { _ in }
        )
    }
}

#Preview("Tile — app") {
    LauncherTilePreviewHost(entry: .app(LaunchDeckPreviewFixtures.safari))
        .padding(32)
        .background(LaunchpadBackdrop())
}

#Preview("Tile — folder") {
    LauncherTilePreviewHost(entry: .folder(LaunchDeckPreviewFixtures.utilitiesFolder))
        .padding(32)
        .background(LaunchpadBackdrop())
}
