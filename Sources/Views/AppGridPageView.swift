import SwiftUI
import UniformTypeIdentifiers

struct AppGridPageView: View {
    let entries: [LauncherEntry]
    let isSearchMode: Bool
    let isEditing: Bool
    let iconProvider: AppIconProvider
    let namespace: Namespace.ID
    let onLaunch: (AppItem) -> Void
    let onOpenFolder: (FolderItem) -> Void
    let onBeginDragging: (LauncherEntry) -> Void
    let onEnterEditMode: () -> Void
    let onDropOnEntry: (LauncherEntry, CGPoint, CGSize) -> Void
    let onDropToPageEnd: () -> Void
    let onPageCapacityChange: (Int) -> Void

    @State private var lastReportedCapacity = 0

    private enum Layout {
        static let edgePaddingScale: CGFloat = 0.3
        static let spacingScale: CGFloat = 0.5
        static let minTileWidth: CGFloat = 104
        static let maxTileWidth: CGFloat = 122
        static let minColumns = 5
        static let maxColumns = 12
        static let baseColumnSpacing: CGFloat = 11 * spacingScale
        static let columnSpacingRatio: CGFloat = 0.05
        static let rowSpacingRatio: CGFloat = 0.064
        static let horizontalPadding: CGFloat = 20 * edgePaddingScale
        static let verticalPadding: CGFloat = 12 * edgePaddingScale
        static let tileHeightRatio: CGFloat = 1.14

        static func columnSpacing(for tileWidth: CGFloat) -> CGFloat {
            max(4, tileWidth * columnSpacingRatio)
        }

        static func rowSpacing(for tileWidth: CGFloat) -> CGFloat {
            max(5, tileWidth * rowSpacingRatio)
        }
    }

    private struct GridMetrics {
        let columnCount: Int
        let rowCount: Int
        let columns: [GridItem]
        let tileWidth: CGFloat
        let rowSpacing: CGFloat

        var pageCapacity: Int {
            max(1, columnCount * rowCount)
        }
    }

    nonisolated static func minimumWindowSize(for minimumVisibleIcons: Int) -> CGSize {
        let iconTarget = max(1, minimumVisibleIcons)
        let requiredColumns = min(Layout.maxColumns, max(Layout.minColumns, 6))
        let requiredRows = max(1, Int(ceil(Double(iconTarget) / Double(requiredColumns))))

        let tileWidth = Layout.minTileWidth
        let tileHeight = tileWidth * Layout.tileHeightRatio
        let rowSpacing = Layout.rowSpacing(for: tileWidth)

        let availableWidthForColumns = CGFloat(requiredColumns) * (Layout.minTileWidth + Layout.baseColumnSpacing)
            - Layout.baseColumnSpacing
            + 1
        let availableHeightForRows = CGFloat(requiredRows) * (tileHeight + rowSpacing)
            - rowSpacing
            + 1

        let gridWidth = Layout.horizontalPadding * 2 + availableWidthForColumns
        let gridHeight = Layout.verticalPadding * 2 + availableHeightForRows

        let horizontalChrome: CGFloat = 64
        let verticalChrome: CGFloat = 176
        return CGSize(
            width: ceil(gridWidth + horizontalChrome),
            height: ceil(gridHeight + verticalChrome)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = gridMetrics(for: proxy.size)
            LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                ForEach(Array(entries.prefix(metrics.pageCapacity))) { entry in
                    LauncherTileView(
                        entry: entry,
                        tileWidth: metrics.tileWidth,
                        iconProvider: iconProvider,
                        isSearchMode: isSearchMode,
                        isEditing: isEditing,
                        namespace: namespace,
                        onLaunch: onLaunch,
                        onOpenFolder: onOpenFolder,
                        onBeginDragging: onBeginDragging,
                        onEnterEditMode: onEnterEditMode,
                        onDrop: onDropOnEntry
                    )
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .onDrop(of: [UTType.text], delegate: PageDropDelegate(onDropToEnd: onDropToPageEnd))
            .onAppear {
                reportPageCapacityIfNeeded(metrics.pageCapacity)
            }
            .onChange(of: metrics.pageCapacity) { _, newValue in
                reportPageCapacityIfNeeded(newValue)
            }
        }
    }

    private func gridMetrics(for size: CGSize) -> GridMetrics {
        let width = size.width
        let height = size.height
        let available = max(0, width - Layout.horizontalPadding * 2)
        let rawCount = Int((available + Layout.baseColumnSpacing) / (Layout.minTileWidth + Layout.baseColumnSpacing))
        let count = max(Layout.minColumns, min(Layout.maxColumns, rawCount))
        let tileWidth = max(
            Layout.minTileWidth,
            min(
                Layout.maxTileWidth,
                (available - CGFloat(count - 1) * Layout.baseColumnSpacing) / CGFloat(count)
            )
        )
        let columnSpacing = Layout.columnSpacing(for: tileWidth)
        let rowSpacing = Layout.rowSpacing(for: tileWidth)
        let tileHeight = tileWidth * Layout.tileHeightRatio
        let availableHeight = max(0, height - Layout.verticalPadding * 2)
        let rawRows = Int((availableHeight + rowSpacing) / (tileHeight + rowSpacing))
        let rows = max(1, rawRows)
        let columns = Array(
            repeating: GridItem(.fixed(tileWidth), spacing: columnSpacing),
            count: count
        )
        return GridMetrics(
            columnCount: count,
            rowCount: rows,
            columns: columns,
            tileWidth: tileWidth,
            rowSpacing: rowSpacing
        )
    }

    private func reportPageCapacityIfNeeded(_ capacity: Int) {
        guard capacity != lastReportedCapacity else { return }
        lastReportedCapacity = capacity
        onPageCapacityChange(capacity)
    }
}

private struct PageDropDelegate: DropDelegate {
    let onDropToEnd: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        onDropToEnd()
        return true
    }
}
