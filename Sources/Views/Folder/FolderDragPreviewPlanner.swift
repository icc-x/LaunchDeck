import CoreGraphics
import Foundation

/// Pure drag/drop geometry math for the folder grid. Factored out of the main view so it
/// can be unit-tested and kept free of SwiftUI state.
enum FolderDragPreviewPlanner {
    /// Determine the drop target under `location` for the given `displaySlots`.
    static func hoverDestination(
        draggingAppID: String?,
        displaySlots: [FolderGridSlot],
        metrics: FolderGridMetrics,
        location: CGPoint
    ) -> FolderHoverDestination {
        guard let draggingAppID else { return .none }

        let translatedX = location.x
        let translatedY = location.y - FolderGridLayout.verticalPadding
        guard translatedX >= 0, translatedY >= 0 else { return .none }

        let strideX = metrics.tileWidth + metrics.columnSpacing
        let strideY = metrics.tileHeight + metrics.rowSpacing
        guard strideX > 0, strideY > 0 else { return .none }

        let column = Int(translatedX / strideX)
        let row = Int(translatedY / strideY)
        guard column >= 0, column < metrics.columnCount, row >= 0 else { return .none }

        let localX = translatedX - CGFloat(column) * strideX
        let localY = translatedY - CGFloat(row) * strideY
        guard localX >= 0, localX <= metrics.tileWidth, localY >= 0, localY <= metrics.tileHeight else {
            return .none
        }

        let index = row * metrics.columnCount + column
        guard index < displaySlots.count else { return .end }

        switch displaySlots[index] {
        case .placeholder:
            return .placeholder
        case let .app(app):
            guard app.id != draggingAppID else { return .placeholder }
            return .app(
                app,
                CGPoint(x: localX, y: localY),
                CGSize(width: metrics.tileWidth, height: metrics.tileHeight)
            )
        }
    }

    /// Compute the post-removal insertion index for the currently hovered slot. Returns
    /// `nil` when the cursor is not above an actionable slot; the caller should fall back
    /// to the last known preview index.
    static func insertionIndex(
        draggingAppID: String?,
        visibleApps: [AppItem],
        displaySlots: [FolderGridSlot],
        metrics: FolderGridMetrics,
        location: CGPoint,
        previewInsertionIndex: Int?
    ) -> Int? {
        guard let draggingAppID else { return nil }

        switch hoverDestination(
            draggingAppID: draggingAppID,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location
        ) {
        case .none:
            return nil
        case .end:
            return visibleApps.filter { $0.id != draggingAppID }.count
        case .placeholder:
            return previewInsertionIndex
        case let .app(app, localLocation, tileSize):
            let remainingApps = visibleApps.filter { $0.id != draggingAppID }
            guard let targetIndex = remainingApps.firstIndex(where: { $0.id == app.id }) else {
                return nil
            }
            let rawIndex = localLocation.x >= tileSize.width * 0.5
                ? targetIndex + 1
                : targetIndex
            return max(0, min(rawIndex, remainingApps.count))
        }
    }

    /// Splice the dragged app's placeholder into `visibleApps` at `previewInsertionIndex`
    /// to produce the slot list that the `ForEach` should render.
    static func makeDisplaySlots(
        visibleApps: [AppItem],
        draggingAppID: String?,
        previewInsertionIndex: Int?
    ) -> [FolderGridSlot] {
        guard let draggingAppID, let previewInsertionIndex else {
            return visibleApps.map(FolderGridSlot.app)
        }

        let remainingApps = visibleApps.filter { $0.id != draggingAppID }
        let clamped = max(0, min(previewInsertionIndex, remainingApps.count))
        var slots = remainingApps.map(FolderGridSlot.app)
        slots.insert(.placeholder(id: draggingAppID), at: clamped)
        return slots
    }
}
