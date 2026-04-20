import SwiftUI
import UniformTypeIdentifiers

struct LauncherFolderOverlayContainer: View {
    let folder: FolderItem
    let apps: [AppItem]
    let isDraggingFolderApp: Bool
    let draggingFolderAppID: String?
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
    let onDropToInsertionIndex: (Int) -> Void
    let onDropToFolderPageBoundary: (Int, Int, Int) -> Void
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
                    .background(theme.controlFillStrong, in: Capsule())
                    .overlay(Capsule().stroke(theme.dragHintStroke, lineWidth: 1))
                    .padding(.top, 28)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            FolderOverlayView(
                folder: folder,
                apps: apps,
                isDraggingFolderApp: isDraggingFolderApp,
                draggingFolderAppID: draggingFolderAppID,
                folderPageSize: folderPageSize,
                wheelPagingEnabled: wheelPagingEnabled,
                iconProvider: iconProvider,
                folderPreviewIconProvider: folderPreviewIconProvider,
                namespace: namespace,
                onClose: onClose,
                onRename: onRename,
                onLaunch: onLaunch,
                onBeginDragging: onBeginDragging,
                onDropToInsertionIndex: onDropToInsertionIndex,
                onDropToFolderPageBoundary: onDropToFolderPageBoundary
            )
            .padding(.horizontal, 72)
            .padding(.vertical, 38)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.965).combined(with: .opacity),
                removal: .scale(scale: 1.015).combined(with: .opacity)
            ))
            .launchAnimation(LaunchMotion.modal, value: folder.id)
        }
        .launchAnimation(LaunchMotion.quickFade, value: isDraggingFolderApp)
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
