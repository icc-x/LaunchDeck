import CoreGraphics
import SwiftUI

/// A slot in the folder grid. Either a real app or a transient placeholder that marks
/// the spot where the currently-dragged app would land if the user released right now.
enum FolderGridSlot: Identifiable {
    case app(AppItem)
    case placeholder(id: String)

    var id: String {
        switch self {
        case let .app(app):
            return app.id
        case let .placeholder(id):
            return "folder-placeholder-\(id)"
        }
    }
}

/// The slot under the cursor while a drag is in progress.
enum FolderHoverDestination {
    /// The cursor is outside the grid area.
    case none
    /// The cursor is over an existing app tile at the given local point and tile size.
    case app(AppItem, CGPoint, CGSize)
    /// The cursor is over the placeholder for the dragged item itself.
    case placeholder
    /// The cursor is past the last tile on the page (drop to "append to this page").
    case end
}

/// Lays out the folder grid for a given viewport size.
struct FolderGridMetrics {
    let columnCount: Int
    let columns: [GridItem]
    let tileWidth: CGFloat
    let tileHeight: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
}

enum FolderGridLayout {
    static let tileWidth: CGFloat = 104
    static let tileHeight: CGFloat = 118
    static let columnSpacing: CGFloat = 11 * 0.5
    static let rowSpacing: CGFloat = 12 * 0.5
    static let verticalPadding: CGFloat = 8

    static func metrics(for size: CGSize) -> FolderGridMetrics {
        let availableWidth = max(tileWidth, size.width)
        let rawCount = Int((availableWidth + columnSpacing) / (tileWidth + columnSpacing))
        let columnCount = max(1, rawCount)
        let columns = Array(
            repeating: GridItem(.fixed(tileWidth), spacing: columnSpacing),
            count: columnCount
        )
        return FolderGridMetrics(
            columnCount: columnCount,
            columns: columns,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
    }
}
