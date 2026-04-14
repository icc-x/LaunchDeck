import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LauncherGridContainerView: View {
    let entries: ArraySlice<LauncherEntry>
    let isSearchMode: Bool
    let currentPage: Int
    let pageCount: Int
    let transitionDirection: Int
    let draggingEntryID: String?
    let isFolderOpen: Bool
    let iconProvider: AppIconProvider
    let folderPreviewIconProvider: AppIconProvider
    let namespace: Namespace.ID
    let onLaunch: (AppItem) -> Void
    let onOpenFolder: (FolderItem) -> Void
    let onBeginDragging: (LauncherEntry) -> Void
    let onDropOnEntry: (LauncherEntry, CGPoint, CGSize) -> Void
    let onDropToPageEnd: () -> Void
    let onPageCapacityChange: (Int) -> Void
    let onPageEdgeHover: (Int) -> Void
    let onPageEdgeExit: () -> Void
    let onDropAtPageBoundary: (Int) -> Void
    let onWheelPageChange: (NSEvent) -> Bool

    var body: some View {
        ZStack {
            AppGridPageView(
                entries: entries,
                isSearchMode: isSearchMode,
                iconProvider: iconProvider,
                folderPreviewIconProvider: folderPreviewIconProvider,
                namespace: namespace,
                onLaunch: onLaunch,
                onOpenFolder: onOpenFolder,
                onBeginDragging: onBeginDragging,
                onDropOnEntry: onDropOnEntry,
                onDropToPageEnd: onDropToPageEnd,
                onPageCapacityChange: onPageCapacityChange
            )
            .id("page-\(currentPage)")
            .transition(pageTransition)
            .animation(LaunchMotion.page, value: currentPage)
            .overlay {
                if canUseWheelPaging {
                    ScrollWheelCaptureView { event in
                        onWheelPageChange(event)
                    }
                    .allowsHitTesting(false)
                }
            }

            if showPageEdgeDropZones {
                HStack {
                    edgeDropZone(direction: -1)
                    Spacer(minLength: 0)
                    edgeDropZone(direction: 1)
                }
                .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var canUseWheelPaging: Bool {
        !isSearchMode && !isFolderOpen && pageCount > 1
    }

    private var showPageEdgeDropZones: Bool {
        draggingEntryID != nil && !isSearchMode && !isFolderOpen && pageCount > 1
    }

    private var pageTransition: AnyTransition {
        if transitionDirection >= 0 {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.985)),
                removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 1.01))
            )
        }
        return .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.985)),
            removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 1.01))
        )
    }

    private func edgeDropZone(direction: Int) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 72)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                delegate: GridEdgePageDropDelegate(
                    onHover: {
                        onPageEdgeHover(direction)
                    },
                    onExit: onPageEdgeExit,
                    onDropAtBoundary: {
                        onDropAtPageBoundary(direction)
                    }
                )
            )
    }
}

private struct GridEdgePageDropDelegate: DropDelegate {
    let onHover: () -> Void
    let onExit: () -> Void
    let onDropAtBoundary: () -> Void

    func dropEntered(info: DropInfo) {
        onHover()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHover()
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        onExit()
        onDropAtBoundary()
        return true
    }
}
