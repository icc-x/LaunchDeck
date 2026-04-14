import SwiftUI
import UniformTypeIdentifiers

struct LauncherFolderOverlayContainer: View {
    let folder: FolderItem
    let apps: [AppItem]
    let isEditing: Bool
    let isDraggingFolderApp: Bool
    let folderPageSize: Int
    let wheelPagingEnabled: Bool
    let iconProvider: AppIconProvider
    let folderPreviewIconProvider: AppIconProvider
    let namespace: Namespace.ID
    let theme: LaunchTheme
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onLaunch: (AppItem) -> Void
    let onBeginDragging: (AppItem) -> Void
    let onEnterEditMode: () -> Void
    let onDropOnApp: (AppItem) -> Void
    let onDropToFolderPageBoundary: (Int, Int, Int) -> Void
    let onDropToFolderEnd: () -> Void
    let onDropExtract: () -> Void

    var body: some View {
        ZStack {
            theme.modalMask
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .onDrop(
                    of: [UTType.text],
                    delegate: FolderExtractDropDelegate(
                        canExtract: { isDraggingFolderApp },
                        onDropExtract: onDropExtract
                    )
                )

            if isDraggingFolderApp {
                Text(LaunchDeckStrings.dragFolderExtractHint)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.controlForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(theme.dragHintStroke, lineWidth: 1))
                    .padding(.top, 28)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            FolderOverlayView(
                folder: folder,
                apps: apps,
                isEditing: isEditing,
                isDraggingFolderApp: isDraggingFolderApp,
                folderPageSize: folderPageSize,
                wheelPagingEnabled: wheelPagingEnabled,
                iconProvider: iconProvider,
                folderPreviewIconProvider: folderPreviewIconProvider,
                namespace: namespace,
                onClose: onClose,
                onRename: onRename,
                onLaunch: onLaunch,
                onBeginDragging: onBeginDragging,
                onEnterEditMode: onEnterEditMode,
                onDropOnApp: onDropOnApp,
                onDropToFolderPageBoundary: onDropToFolderPageBoundary,
                onDropToFolderEnd: onDropToFolderEnd
            )
            .padding(.horizontal, 72)
            .padding(.vertical, 38)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.965).combined(with: .opacity),
                removal: .scale(scale: 1.015).combined(with: .opacity)
            ))
            .animation(LaunchMotion.modal, value: folder.id)
        }
        .animation(LaunchMotion.quickFade, value: isDraggingFolderApp)
    }
}

private struct FolderExtractDropDelegate: DropDelegate {
    let canExtract: () -> Bool
    let onDropExtract: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canExtract() else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canExtract() else { return false }
        onDropExtract()
        return true
    }
}
