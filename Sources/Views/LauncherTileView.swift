import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct LauncherTileView: View {
    let entry: LauncherEntry
    let tileWidth: CGFloat
    let iconProvider: AppIconProvider
    let isSearchMode: Bool
    let isEditing: Bool
    let namespace: Namespace.ID
    let onLaunch: (AppItem) -> Void
    let onOpenFolder: (FolderItem) -> Void
    let onBeginDragging: (LauncherEntry) -> Void
    let onEnterEditMode: () -> Void
    let onDrop: (LauncherEntry, CGPoint, CGSize) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var isDropTargeted = false
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
        .scaleEffect(isHovering ? 1.03 : 1)
        .shadow(color: isHovering ? theme.tileShadowHover : theme.tileShadowNormal, radius: isHovering ? 6 : 3, y: isHovering ? 3 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: metrics.folderCornerRadius, style: .continuous)
                .stroke(isDropTargeted ? theme.dropStroke : .clear, lineWidth: 1.2)
                .padding(.bottom, metrics.dropOutlineBottomInset)
        }
        .animation(LaunchMotion.hover, value: isHovering)
        .animation(LaunchMotion.quickFade, value: isDropTargeted)
        .help(entry.displayName)
        .onTapGesture {
            guard !isEditing else { return }
            handleTap()
        }
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
        .onDrag {
            if !isSearchMode {
                onBeginDragging(entry)
            }
            return NSItemProvider(object: entry.id as NSString)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.42).onEnded { _ in
                guard !isSearchMode else { return }
                onEnterEditMode()
            }
        )
        .onDrop(
            of: [UTType.text],
            delegate: TileDropDelegate(
                targetEntry: entry,
                tileSize: tileSize,
                isDropTargeted: $isDropTargeted,
                onDrop: onDrop
            )
        )
        .conditionalModifier(isEditing) { view in
            view.modifier(WiggleModifier(isActive: true, seed: entry.id))
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
                    Image(nsImage: iconProvider.icon(for: app))
                        .resizable()
                        .frame(width: metrics.miniIconSize, height: metrics.miniIconSize)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.miniIconCornerRadius, style: .continuous))
                }
            }
        }
        .frame(width: metrics.folderSurfaceSize, height: metrics.folderSurfaceSize)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: metrics.folderCornerRadius, style: .continuous))
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

    private func refreshIconSubscription(force: Bool) {
        let key = observedIconKey
        guard force || key != subscribedIconKey else { return }

        iconSubscription?.cancel()
        subscribedIconKey = key
        guard !observedIconIDs.isEmpty else {
            iconSubscription = nil
            return
        }

        iconSubscription = iconProvider.iconLoadedPublisher(for: observedIconIDs).sink { _ in
            iconReloadToken &+= 1
        }

        // Pull once after (re)subscribe so already-cached icons can render immediately.
        iconReloadToken &+= 1
    }
}

private struct TileDropDelegate: DropDelegate {
    let targetEntry: LauncherEntry
    let tileSize: CGSize
    @Binding var isDropTargeted: Bool
    let onDrop: (LauncherEntry, CGPoint, CGSize) -> Void

    func dropEntered(info: DropInfo) {
        isDropTargeted = true
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false
        onDrop(targetEntry, info.location, tileSize)
        return true
    }
}
