import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct FolderOverlayView: View {
    let folder: FolderItem
    let apps: [AppItem]
    let isDraggingFolderApp: Bool
    let draggingFolderAppID: String?
    let folderPageSize: Int
    let wheelPagingEnabled: Bool
    let iconProvider: AppIconProvider
    let folderPreviewIconProvider: AppIconProvider
    let namespace: Namespace.ID
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onLaunch: (AppItem) -> Void
    let onBeginDragging: (AppItem) -> Void
    let onDropToInsertionIndex: (Int) -> Void
    let onDropToFolderPageBoundary: (Int, Int, Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var editingName = ""
    @FocusState private var isNameFocused: Bool
    @State private var currentPage = 0
    @State private var edgeHoverDirection: Int?
    @State private var edgeHoverStartedAt = Date.distantPast
    @State private var lastEdgeFlipAt = Date.distantPast
    @State private var lastWheelFlipAt = Date.distantPast
    @State private var pagedAppsCache: [ArraySlice<AppItem>] = []
    @State private var folderBadgeReloadToken = 0
    @State private var folderBadgeSubscription: AnyCancellable?
    @State private var subscribedFolderBadgeKey = ""
    @State private var previewInsertionIndex: Int?

    private enum GridLayout {
        static let tileWidth: CGFloat = 104
        static let tileHeight: CGFloat = 118
        static let columnSpacing: CGFloat = 11 * 0.5
        static let rowSpacing: CGFloat = 12 * 0.5
        static let verticalPadding: CGFloat = 8
    }

    private struct GridMetrics {
        let columnCount: Int
        let columns: [GridItem]
        let tileWidth: CGFloat
        let tileHeight: CGFloat
        let columnSpacing: CGFloat
        let rowSpacing: CGFloat
    }

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    private var visibleApps: ArraySlice<AppItem> {
        guard pagedAppsCache.indices.contains(currentPage) else { return ArraySlice<AppItem>() }
        return pagedAppsCache[currentPage]
    }

    private var showFolderEdgeDropZones: Bool {
        isDraggingFolderApp && pagedAppsCache.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                folderBadge

                VStack(alignment: .leading, spacing: 2) {
                    TextField(LaunchDeckStrings.folderNamePlaceholder, text: $editingName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .onSubmit { commitRename() }
                        .onChange(of: folder.name) { _, newValue in
                            editingName = newValue
                        }
                        .frame(maxWidth: 280, alignment: .leading)
                        .accessibilityLabel(LaunchDeckStrings.folderNamePlaceholder)

                    Text(LaunchDeckStrings.appCountInFolder(apps.count))
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    isNameFocused = true
                } label: {
                    Label(LaunchDeckStrings.rename, systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(theme.controlSubtleForeground)
                }
                .buttonStyle(.plain)
                .help(LaunchDeckStrings.rename)

                Button {
                    onClose()
                } label: {
                    Label(LaunchDeckStrings.close, systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(theme.controlSubtleForeground)
                }
                .buttonStyle(.plain)
                .help(LaunchDeckStrings.close)
            }

            ZStack {
                GeometryReader { proxy in
                    let metrics = gridMetrics(for: proxy.size)
                    let visibleAppsArray = Array(visibleApps)
                    let displaySlots = makeDisplaySlots(from: visibleAppsArray)
                    let visibleAppIDs = displaySlots.map(\.id)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: metrics.columns, spacing: metrics.rowSpacing) {
                            ForEach(displaySlots) { slot in
                                switch slot {
                                case let .app(app):
                                    FolderAppButton(
                                        app: app,
                                        isBeingDragged: app.id == draggingFolderAppID && previewInsertionIndex == nil,
                                        iconProvider: iconProvider,
                                        action: { onLaunch(app) },
                                        onBeginDragging: { onBeginDragging(app) }
                                    )
                                case .placeholder:
                                    FolderAppPlaceholderView()
                                }
                            }
                        }
                        .padding(.vertical, GridLayout.verticalPadding)
                        .animation(LaunchMotion.reorder, value: visibleAppIDs)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: FolderGridDropDelegate(
                            onHover: { location in
                                updatePreview(
                                    draggingAppID: draggingFolderAppID,
                                    visibleApps: visibleAppsArray,
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
                                    draggingAppID: draggingFolderAppID,
                                    visibleApps: visibleAppsArray,
                                    displaySlots: displaySlots,
                                    metrics: metrics,
                                    location: location
                                )
                            }
                        )
                    )
                    .overlay {
                        if wheelPagingEnabled, pagedAppsCache.count > 1 {
                            ScrollWheelCaptureView { event in
                                handleFolderWheelPaging(event)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }

                if showFolderEdgeDropZones {
                    HStack {
                        folderEdgeDropZone(direction: -1)
                        Spacer(minLength: 0)
                        folderEdgeDropZone(direction: 1)
                    }
                    .padding(.horizontal, 2)
                }
            }

            if pagedAppsCache.count > 1 {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ForEach(0..<pagedAppsCache.count, id: \.self) { index in
                        Button {
                            withAnimation(LaunchMotion.page) {
                                currentPage = index
                            }
                        } label: {
                            Circle()
                                .fill(index == currentPage ? theme.pageIndicatorActive : theme.pageIndicatorInactive)
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 860, maxHeight: 560)
        .background(theme.panelFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.28 : 0.18), radius: 14, y: 10)
        .onAppear {
            editingName = folder.name
            rebuildPagedApps()
            clampFolderPage()
            refreshFolderBadgeSubscription(force: true)
        }
        .onChange(of: apps) { _, _ in
            rebuildPagedApps()
            clampFolderPage()
            clearEdgeHoverState()
            refreshFolderBadgeSubscription(force: false)
        }
        .onChange(of: isNameFocused) { _, focused in
            if !focused {
                commitRename()
            }
        }
        .onDisappear {
            folderBadgeSubscription?.cancel()
            folderBadgeSubscription = nil
            subscribedFolderBadgeKey = ""
        }
        .onChange(of: draggingFolderAppID) { _, newValue in
            if newValue == nil {
                previewInsertionIndex = nil
            }
        }
        .onChange(of: Array(visibleApps).map(\.id)) { _, _ in
            guard let draggingFolderAppID else {
                previewInsertionIndex = nil
                return
            }
            if let previewInsertionIndex {
                let maxInsertionIndex = max(0, Array(visibleApps).filter { $0.id != draggingFolderAppID }.count)
                self.previewInsertionIndex = min(previewInsertionIndex, maxInsertionIndex)
            }
        }
    }

    private var folderBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.controlFill)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 3), count: 2), spacing: 3) {
                ForEach(Array(apps.prefix(4).enumerated()), id: \.offset) { _, app in
                    Image(nsImage: folderPreviewIconProvider.icon(for: app))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
        .frame(width: 52, height: 52)
        .id(folderBadgeReloadToken)
        .matchedGeometryEffect(id: "folder-card-\(folder.id)", in: namespace)
    }

    private func folderEdgeDropZone(direction: Int) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 68)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                delegate: FolderEdgeDropDelegate(
                    onHover: {
                        handleEdgeHover(direction: direction)
                    },
                    onExit: {
                        clearEdgeHoverState()
                    },
                    onDropAtBoundary: {
                        onDropToFolderPageBoundary(currentPage, direction, folderPageSize)
                        clearEdgeHoverState()
                    }
                )
            )
    }

    private func handleEdgeHover(direction: Int) {
        let now = Date()

        if edgeHoverDirection != direction {
            edgeHoverDirection = direction
            edgeHoverStartedAt = now
            lastEdgeFlipAt = now
            return
        }

        let hoverElapsed = now.timeIntervalSince(edgeHoverStartedAt)
        guard hoverElapsed >= 0.20 else { return }

        let dynamicInterval = max(0.08, 0.34 - hoverElapsed * 0.22)
        guard now.timeIntervalSince(lastEdgeFlipAt) >= dynamicInterval else { return }

        if direction < 0, currentPage > 0 {
            withAnimation(LaunchMotion.page) {
                currentPage -= 1
            }
            lastEdgeFlipAt = now
        } else if direction > 0, currentPage < pagedAppsCache.count - 1 {
            withAnimation(LaunchMotion.page) {
                currentPage += 1
            }
            lastEdgeFlipAt = now
        }
    }

    private func clearEdgeHoverState() {
        edgeHoverDirection = nil
        edgeHoverStartedAt = Date.distantPast
        lastEdgeFlipAt = Date.distantPast
    }

    private func clampFolderPage() {
        guard !pagedAppsCache.isEmpty else {
            currentPage = 0
            return
        }
        currentPage = min(currentPage, pagedAppsCache.count - 1)
    }

    private func handleFolderWheelPaging(_ event: NSEvent) -> Bool {
        guard pagedAppsCache.count > 1 else { return false }

        let now = Date()
        guard now.timeIntervalSince(lastWheelFlipAt) >= 0.16 else { return false }

        guard let targetPage = WheelPageResolver.targetPage(
            currentPage: currentPage,
            pageCount: pagedAppsCache.count,
            event: event
        ) else {
            return false
        }

        withAnimation(LaunchMotion.page) {
            currentPage = targetPage
        }
        lastWheelFlipAt = now
        return true
    }

    private func commitRename() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingName = folder.name
            return
        }
        onRename(trimmed)
    }

    private func rebuildPagedApps() {
        pagedAppsCache = LauncherPaging.chunked(apps, pageSize: folderPageSize)
    }

    private func gridMetrics(for size: CGSize) -> GridMetrics {
        let availableWidth = max(GridLayout.tileWidth, size.width)
        let rawCount = Int((availableWidth + GridLayout.columnSpacing) / (GridLayout.tileWidth + GridLayout.columnSpacing))
        let columnCount = max(1, rawCount)
        let columns = Array(
            repeating: GridItem(.fixed(GridLayout.tileWidth), spacing: GridLayout.columnSpacing),
            count: columnCount
        )

        return GridMetrics(
            columnCount: columnCount,
            columns: columns,
            tileWidth: GridLayout.tileWidth,
            tileHeight: GridLayout.tileHeight,
            columnSpacing: GridLayout.columnSpacing,
            rowSpacing: GridLayout.rowSpacing
        )
    }

    private var folderBadgeIconIDs: [String] {
        Array(apps.prefix(4).map(\.id))
    }

    private var folderBadgeIconKey: String {
        folderBadgeIconIDs.joined(separator: "|")
    }

    private func refreshFolderBadgeSubscription(force: Bool) {
        let key = folderBadgeIconKey
        guard force || key != subscribedFolderBadgeKey else { return }

        folderBadgeSubscription?.cancel()
        subscribedFolderBadgeKey = key
        guard !folderBadgeIconIDs.isEmpty else {
            folderBadgeSubscription = nil
            return
        }

        folderBadgeSubscription = folderPreviewIconProvider.iconLoadedPublisher(for: folderBadgeIconIDs).sink { _ in
            folderBadgeReloadToken &+= 1
        }

        folderBadgeReloadToken &+= 1
    }

    private func makeDisplaySlots(from visibleApps: [AppItem]) -> [FolderGridSlot] {
        guard let draggingFolderAppID, let previewInsertionIndex else {
            return visibleApps.map(FolderGridSlot.app)
        }

        let remainingApps = visibleApps.filter { $0.id != draggingFolderAppID }
        let clampedInsertionIndex = max(0, min(previewInsertionIndex, remainingApps.count))
        var slots = remainingApps.map(FolderGridSlot.app)
        slots.insert(.placeholder(id: draggingFolderAppID), at: clampedInsertionIndex)
        return slots
    }

    private func updatePreview(
        draggingAppID: String?,
        visibleApps: [AppItem],
        displaySlots: [FolderGridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) {
        guard draggingAppID != nil else {
            previewInsertionIndex = nil
            return
        }

        switch hoverDestination(
            draggingAppID: draggingAppID,
            visibleApps: visibleApps,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location
        ) {
        case .none, .placeholder:
            return
        case .end:
            previewInsertionIndex = visibleApps.filter { $0.id != draggingAppID }.count
        case .app:
            if let insertionIndex = insertionIndex(
                draggingAppID: draggingAppID,
                visibleApps: visibleApps,
                displaySlots: displaySlots,
                metrics: metrics,
                location: location
            ) {
                previewInsertionIndex = insertionIndex
            }
        }
    }

    private func performDrop(
        draggingAppID: String?,
        visibleApps: [AppItem],
        displaySlots: [FolderGridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) {
        defer { previewInsertionIndex = nil }

        if let insertionIndex = insertionIndex(
            draggingAppID: draggingAppID,
            visibleApps: visibleApps,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location
        ) {
            onDropToInsertionIndex(globalInsertionIndex(for: insertionIndex))
            return
        }

        let fallbackInsertionIndex = previewInsertionIndex
            ?? visibleApps.filter { $0.id != draggingAppID }.count
        onDropToInsertionIndex(globalInsertionIndex(for: fallbackInsertionIndex))
    }

    private func hoverDestination(
        draggingAppID: String?,
        visibleApps: [AppItem],
        displaySlots: [FolderGridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) -> FolderHoverDestination {
        guard let draggingAppID else { return .none }

        let translatedX = location.x
        let translatedY = location.y - GridLayout.verticalPadding
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
            return .app(app, CGPoint(x: localX, y: localY), CGSize(width: metrics.tileWidth, height: metrics.tileHeight))
        }
    }

    private func insertionIndex(
        draggingAppID: String?,
        visibleApps: [AppItem],
        displaySlots: [FolderGridSlot],
        metrics: GridMetrics,
        location: CGPoint
    ) -> Int? {
        guard let draggingAppID else { return nil }

        switch hoverDestination(
            draggingAppID: draggingAppID,
            visibleApps: visibleApps,
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

            let insertionIndex = localLocation.x >= tileSize.width * 0.5
                ? targetIndex + 1
                : targetIndex
            return max(0, min(insertionIndex, remainingApps.count))
        }
    }

    private func globalInsertionIndex(for localInsertionIndex: Int) -> Int {
        let pageStart = currentPage * max(1, folderPageSize)
        let remainingCount = max(0, apps.count - (draggingFolderAppID == nil ? 0 : 1))
        return max(0, min(pageStart + localInsertionIndex, remainingCount))
    }

}

private enum FolderHoverDestination {
    case none
    case app(AppItem, CGPoint, CGSize)
    case placeholder
    case end
}

private enum FolderGridSlot: Identifiable {
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

private struct FolderAppPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.placeholderFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.placeholderStroke, lineWidth: 1)
                )
                .frame(width: 70, height: 70)

            VStack(spacing: 4) {
                Capsule()
                    .fill(theme.placeholderSecondaryFill)
                    .frame(width: 52, height: 9)
                Capsule()
                    .fill(theme.placeholderSecondaryFill.opacity(0.78))
                    .frame(width: 36, height: 7)
            }
        }
            .padding(.top, 4)
            .frame(width: 104, height: 118)
            .scaleEffect(0.98)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}

private struct FolderAppButton: View {
    let app: AppItem
    let isBeingDragged: Bool
    let iconProvider: AppIconProvider
    let action: () -> Void
    let onBeginDragging: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var iconReloadToken = 0
    @State private var iconSubscription: AnyCancellable?

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        let _ = iconReloadToken
        VStack(spacing: 8) {
            Image(nsImage: iconProvider.icon(for: app))
                .resizable()
                .interpolation(.high)
                .frame(width: 70, height: 70)

            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 96)
        }
        .contentShape(Rectangle())
        .opacity(isBeingDragged ? 0.06 : 1)
        .scaleEffect(isBeingDragged ? 0.92 : (isHovering ? 1.02 : 1))
        .blur(radius: isBeingDragged ? 1.1 : 0)
        .animation(LaunchMotion.hover, value: isHovering)
        .animation(LaunchMotion.reorder, value: isBeingDragged)
        .onHover { isHovering = $0 }
        .onAppear {
            if iconSubscription == nil {
                iconSubscription = iconProvider.iconLoadedPublisher(for: [app.id]).sink { _ in
                    iconReloadToken &+= 1
                }
                iconReloadToken &+= 1
            }
        }
        .onDisappear {
            iconSubscription?.cancel()
            iconSubscription = nil
        }
        .help(app.name)
        .accessibilityLabel(app.name)
        .onTapGesture {
            action()
        }
        .onDrag {
            onBeginDragging()
            return NSItemProvider(object: "folder:\(app.id)" as NSString)
        } preview: {
            dragPreview
        }
    }

    private var dragPreview: some View {
        VStack(spacing: 8) {
            Image(nsImage: iconProvider.icon(for: app))
                .resizable()
                .interpolation(.high)
                .frame(width: 70, height: 70)

            Text(app.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 96)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.dragPreviewFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.dragPreviewStroke, lineWidth: 1)
                )
        )
        .scaleEffect(1.05)
        .shadow(color: theme.dragPreviewShadow, radius: 18, y: 10)
        .compositingGroup()
    }
}

private struct FolderGridDropDelegate: DropDelegate {
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

private struct FolderEdgeDropDelegate: DropDelegate {
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
