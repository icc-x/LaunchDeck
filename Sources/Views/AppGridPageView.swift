import SwiftUI
import UniformTypeIdentifiers

struct AppGridPageView: View {
    let allEntries: [LauncherEntry]
    let entries: ArraySlice<LauncherEntry>
    let isSearchMode: Bool
    let draggingEntryID: String?
    let iconProvider: AppIconProvider
    let folderPreviewIconProvider: AppIconProvider
    let namespace: Namespace.ID
    let onLaunch: (AppItem) -> Void
    let onOpenFolder: (FolderItem) -> Void
    let onBeginDragging: (LauncherEntry) -> Void
    let onDropOnEntry: (LauncherEntry, CGPoint, CGSize) -> Void
    let onDropToInsertionIndex: (Int) -> Void
    let onPageCapacityChange: (Int) -> Void

    @State private var lastReportedCapacity = 0
    @State private var previewInsertionIndex: Int?

    fileprivate enum Layout {
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

    fileprivate struct GridMetrics {
        let columnCount: Int
        let rowCount: Int
        let columns: [GridItem]
        let tileWidth: CGFloat
        let tileHeight: CGFloat
        let columnSpacing: CGFloat
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
            let visibleEntries = entries.prefix(metrics.pageCapacity)
            let displaySlots = makeDisplaySlots(from: visibleEntries)
            let visibleEntryIDs = displaySlots.map(\.id)
            LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                ForEach(displaySlots) { slot in
                    switch slot {
                    case let .entry(entry):
                        LauncherTileView(
                            entry: entry,
                            tileWidth: metrics.tileWidth,
                            iconProvider: iconProvider,
                            folderPreviewIconProvider: folderPreviewIconProvider,
                            isSearchMode: isSearchMode,
                            isBeingDragged: entry.id == draggingEntryID && previewInsertionIndex == nil,
                            namespace: namespace,
                            onLaunch: onLaunch,
                            onOpenFolder: onOpenFolder,
                            onBeginDragging: onBeginDragging
                        )
                    case .placeholder:
                        LauncherTilePlaceholderView(tileWidth: metrics.tileWidth)
                    }
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .launchAnimation(LaunchMotion.reorder, value: visibleEntryIDs)
            .onDrop(
                of: [UTType.text],
                delegate: PageDropDelegate(
                    onHover: { location in
                        updatePreview(
                            draggingEntryID: draggingEntryID,
                            visibleEntries: visibleEntries,
                            displaySlots: displaySlots,
                            metrics: metrics,
                            location: location
                        )
                    },
                    onExitPreview: {
                        previewInsertionIndex = nil
                    },
                    onPerformDrop: { location in
                        performDrop(
                            draggingEntryID: draggingEntryID,
                            visibleEntries: visibleEntries,
                            displaySlots: displaySlots,
                            metrics: metrics,
                            location: location
                        )
                    }
                )
            )
            .onAppear {
                reportPageCapacityIfNeeded(metrics.pageCapacity)
            }
            .onChange(of: metrics.pageCapacity) { _, newValue in
                reportPageCapacityIfNeeded(newValue)
            }
            .onChange(of: draggingEntryID) { _, newValue in
                if newValue == nil {
                    previewInsertionIndex = nil
                }
            }
            .onChange(of: visibleEntries.map(\.id)) { _, _ in
                guard let draggingEntryID else {
                    previewInsertionIndex = nil
                    return
                }
                if let previewInsertionIndex {
                    let maxInsertionIndex = max(0, visibleEntries.filter { $0.id != draggingEntryID }.count)
                    self.previewInsertionIndex = min(previewInsertionIndex, maxInsertionIndex)
                }
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
            tileHeight: tileHeight,
            columnSpacing: columnSpacing,
            rowSpacing: rowSpacing
        )
    }

    private func reportPageCapacityIfNeeded(_ capacity: Int) {
        guard capacity != lastReportedCapacity else { return }
        lastReportedCapacity = capacity
        onPageCapacityChange(capacity)
    }

    private func makeDisplaySlots(from visibleEntries: ArraySlice<LauncherEntry>) -> [GridSlot] {
        guard let draggingEntryID, let previewInsertionIndex else {
            return visibleEntries.map(GridSlot.entry)
        }

        let remainingEntries = visibleEntries.filter { $0.id != draggingEntryID }
        let clampedInsertionIndex = max(0, min(previewInsertionIndex, remainingEntries.count))
        var slots = remainingEntries.map(GridSlot.entry)
        slots.insert(.placeholder(id: draggingEntryID), at: clampedInsertionIndex)
        return slots
    }

    private func updatePreview(
        draggingEntryID: String?,
        visibleEntries: ArraySlice<LauncherEntry>,
        displaySlots: [GridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) {
        guard draggingEntryID != nil else {
            previewInsertionIndex = nil
            return
        }

        switch hoverDestination(
            draggingEntryID: draggingEntryID,
            visibleEntries: visibleEntries,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location
        ) {
        case .none, .placeholder:
            return
        case .end:
            previewInsertionIndex = visibleEntries.filter { $0.id != draggingEntryID }.count
        case let .entry(_, _, _, isGrouping):
            if isGrouping {
                previewInsertionIndex = nil
                return
            }

            if let insertionIndex = insertionIndex(
                draggingEntryID: draggingEntryID,
                visibleEntries: visibleEntries,
                displaySlots: displaySlots,
                metrics: metrics,
                location: location
            ) {
                previewInsertionIndex = insertionIndex
            }
        }
    }

    private func performDrop(
        draggingEntryID: String?,
        visibleEntries: ArraySlice<LauncherEntry>,
        displaySlots: [GridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) {
        defer { previewInsertionIndex = nil }
        guard let draggingEntryID else { return }

        switch hoverDestination(
            draggingEntryID: draggingEntryID,
            visibleEntries: visibleEntries,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location
        ) {
        case let .entry(entry, localLocation, tileSize, isGrouping):
            if isGrouping {
                onDropOnEntry(entry, localLocation, tileSize)
                return
            }

            if let insertionIndex = insertionIndex(
                draggingEntryID: draggingEntryID,
                visibleEntries: visibleEntries,
                displaySlots: displaySlots,
                metrics: metrics,
                location: location
            ) {
                onDropToInsertionIndex(
                    LauncherRootGridDropResolver.globalInsertionIndex(
                        allEntries: allEntries,
                        visibleEntries: visibleEntries,
                        draggingEntryID: draggingEntryID,
                        localInsertionIndex: insertionIndex
                    )
                )
                return
            }
        case .placeholder:
            if let previewInsertionIndex {
                onDropToInsertionIndex(
                    LauncherRootGridDropResolver.globalInsertionIndex(
                        allEntries: allEntries,
                        visibleEntries: visibleEntries,
                        draggingEntryID: draggingEntryID,
                        localInsertionIndex: previewInsertionIndex
                    )
                )
                return
            }
        case .end, .none:
            break
        }

        let fallbackInsertionIndex = previewInsertionIndex
            ?? visibleEntries.filter { $0.id != draggingEntryID }.count
        onDropToInsertionIndex(
            LauncherRootGridDropResolver.globalInsertionIndex(
                allEntries: allEntries,
                visibleEntries: visibleEntries,
                draggingEntryID: draggingEntryID,
                localInsertionIndex: fallbackInsertionIndex
            )
        )
    }

    private func hoverDestination(
        draggingEntryID: String?,
        visibleEntries: ArraySlice<LauncherEntry>,
        displaySlots: [GridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) -> GridHoverDestination {
        guard let draggingEntryID else { return .none }

        let translatedX = location.x - Layout.horizontalPadding
        let translatedY = location.y - Layout.verticalPadding
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
        case let .entry(entry):
            guard entry.id != draggingEntryID else { return .placeholder }
            let localLocation = CGPoint(x: localX, y: localY)
            let tileSize = CGSize(width: metrics.tileWidth, height: metrics.tileHeight)
            let canGroup = LauncherTuning.Grouping.rect(in: tileSize).contains(localLocation)
                && LauncherRootGridDropResolver.canGroup(
                    allEntries: allEntries,
                    draggingEntryID: draggingEntryID,
                    targetEntry: entry
                )
            return .entry(entry, localLocation, tileSize, canGroup)
        }
    }

    private func insertionIndex(
        draggingEntryID: String?,
        visibleEntries: ArraySlice<LauncherEntry>,
        displaySlots: [GridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) -> Int? {
        guard let draggingEntryID else { return nil }

        switch hoverDestination(
            draggingEntryID: draggingEntryID,
            visibleEntries: visibleEntries,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location
        ) {
        case .none:
            return nil
        case .end:
            return visibleEntries.filter { $0.id != draggingEntryID }.count
        case .placeholder:
            return previewInsertionIndex
        case let .entry(entry, localLocation, tileSize, isGrouping):
            guard !isGrouping else { return nil }
            let remainingEntries = visibleEntries.filter { $0.id != draggingEntryID }
            guard let targetIndex = remainingEntries.firstIndex(where: { $0.id == entry.id }) else {
                return nil
            }
            let insertionIndex = localLocation.x >= tileSize.width * 0.5
                ? targetIndex + 1
                : targetIndex
            return max(0, min(insertionIndex, remainingEntries.count))
        }
    }

}

private enum GridHoverDestination {
    case none
    case entry(LauncherEntry, CGPoint, CGSize, Bool)
    case placeholder
    case end
}

private enum GridSlot: Identifiable {
    case entry(LauncherEntry)
    case placeholder(id: String)

    var id: String {
        switch self {
        case let .entry(entry):
            return entry.id
        case let .placeholder(id):
            return "placeholder-\(id)"
        }
    }
}

private struct LauncherTilePlaceholderView: View {
    let tileWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    private var tileHeight: CGFloat {
        tileWidth * 1.14
    }

    private var cornerRadius: CGFloat {
        tileWidth * 0.15
    }

    var body: some View {
        VStack(spacing: tileWidth * 0.06) {
            RoundedRectangle(cornerRadius: cornerRadius * 0.98, style: .continuous)
                .fill(theme.placeholderFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius * 0.98, style: .continuous)
                        .stroke(theme.placeholderStroke, lineWidth: 1)
                )
                .frame(width: tileWidth * 0.84, height: tileWidth * 0.84)

            VStack(spacing: 5) {
                Capsule()
                    .fill(theme.placeholderSecondaryFill)
                    .frame(width: tileWidth * 0.56, height: 10)
                Capsule()
                    .fill(theme.placeholderSecondaryFill.opacity(0.78))
                    .frame(width: tileWidth * 0.42, height: 8)
            }
        }
        .padding(.bottom, tileWidth * 0.02)
            .frame(width: tileWidth, height: tileHeight)
            .scaleEffect(0.98)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}

private struct PageDropDelegate: DropDelegate {
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
