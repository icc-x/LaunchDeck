import SwiftUI

/// Tracks the cursor inside the folder grid while a drag is in progress. Routes hover
/// updates to the caller so the insertion placeholder can follow the cursor, and
/// commits the drop when released.
struct FolderGridDropDelegate: DropDelegate {
    let onHover: (CGPoint) -> Void
    let onExitPreview: () -> Void
    let onPerformDrop: (CGPoint) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHover(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onExitPreview()
    }

    func performDrop(info: DropInfo) -> Bool {
        onPerformDrop(info.location)
        return true
    }
}

/// Active area at the leading/trailing edge of a multi-page folder that lets users flip
/// pages (on hover) and drop-at-boundary when releasing.
struct FolderEdgeDropDelegate: DropDelegate {
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
