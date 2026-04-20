import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The modal panel rendered when the user opens a folder. Composition:
///
/// - `FolderAppButton` — one tile per app (extracted to `Folder/FolderAppButton.swift`).
/// - `FolderAppPlaceholderView` — rendered at the currently-hovered insertion slot.
/// - `FolderGridDropDelegate` / `FolderEdgeDropDelegate` — own the drop-zone contracts.
/// - `FolderDragPreviewPlanner` — pure geometry translating cursor positions to the
///   insertion index used by `LauncherStore`.
///
/// This view is responsible only for:
///   1. Presenting the panel chrome (name field, page indicators, close/rename buttons).
///   2. Wiring SwiftUI `@State` — current page, hover scroller, icon subscriptions —
///      to the callbacks that `LauncherFolderOverlayContainer` hands in.
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
    @State private var edgeScroller = EdgePageScroller()
    @State private var lastWheelFlipAt = Date.distantPast
    @State private var pagedAppsCache: [ArraySlice<AppItem>] = []
    @State private var folderBadgeReloadToken = 0
    @State private var folderBadgeSubscription: AnyCancellable?
    @State private var subscribedFolderBadgeKey = ""
    @State private var previewInsertionIndex: Int?

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
            header

            ZStack {
                gridBody
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
                pageIndicators
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

    // MARK: Subviews

    private var header: some View {
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

            Button { isNameFocused = true } label: {
                Label(LaunchDeckStrings.rename, systemImage: "pencil")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(theme.controlSubtleForeground)
            }
            .buttonStyle(.plain)
            .help(LaunchDeckStrings.rename)

            Button { onClose() } label: {
                Label(LaunchDeckStrings.close, systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(theme.controlSubtleForeground)
            }
            .buttonStyle(.plain)
            .help(LaunchDeckStrings.close)
        }
    }

    private var gridBody: some View {
        GeometryReader { proxy in
            let metrics = FolderGridLayout.metrics(for: proxy.size)
            let visibleAppsArray = Array(visibleApps)
            let displaySlots = FolderDragPreviewPlanner.makeDisplaySlots(
                visibleApps: visibleAppsArray,
                draggingAppID: draggingFolderAppID,
                previewInsertionIndex: previewInsertionIndex
            )
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
                .padding(.vertical, FolderGridLayout.verticalPadding)
                .launchAnimation(LaunchMotion.reorder, value: visibleAppIDs)
            }
            .onDrop(
                of: [UTType.text],
                delegate: FolderGridDropDelegate(
                    onHover: { location in
                        updatePreview(
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
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            ForEach(0..<pagedAppsCache.count, id: \.self) { index in
                Button {
                    withLaunchAnimation(LaunchMotion.page) {
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

    // MARK: Paging

    private func handleEdgeHover(direction: Int) {
        guard edgeScroller.hover(direction: direction) else { return }

        if direction < 0, currentPage > 0 {
            withLaunchAnimation(LaunchMotion.page) {
                currentPage -= 1
            }
        } else if direction > 0, currentPage < pagedAppsCache.count - 1 {
            withLaunchAnimation(LaunchMotion.page) {
                currentPage += 1
            }
        }
    }

    private func clearEdgeHoverState() {
        edgeScroller.reset()
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
        guard now.timeIntervalSince(lastWheelFlipAt) >= LauncherTuning.WheelPaging.minimumInterval else { return false }

        guard let targetPage = WheelPageResolver.targetPage(
            currentPage: currentPage,
            pageCount: pagedAppsCache.count,
            event: event
        ) else {
            return false
        }

        withLaunchAnimation(LaunchMotion.page) {
            currentPage = targetPage
        }
        lastWheelFlipAt = now
        return true
    }

    // MARK: Rename / Paging plumbing

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

    // MARK: Drop routing

    private func updatePreview(
        visibleApps: [AppItem],
        displaySlots: [FolderGridSlot],
        metrics: FolderGridMetrics,
        location: CGPoint
    ) {
        guard draggingFolderAppID != nil else {
            previewInsertionIndex = nil
            return
        }

        switch FolderDragPreviewPlanner.hoverDestination(
            draggingAppID: draggingFolderAppID,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location
        ) {
        case .none, .placeholder:
            return
        case .end:
            previewInsertionIndex = visibleApps.filter { $0.id != draggingFolderAppID }.count
        case .app:
            if let insertionIndex = FolderDragPreviewPlanner.insertionIndex(
                draggingAppID: draggingFolderAppID,
                visibleApps: visibleApps,
                displaySlots: displaySlots,
                metrics: metrics,
                location: location,
                previewInsertionIndex: previewInsertionIndex
            ) {
                previewInsertionIndex = insertionIndex
            }
        }
    }

    private func performDrop(
        visibleApps: [AppItem],
        displaySlots: [FolderGridSlot],
        metrics: FolderGridMetrics,
        location: CGPoint
    ) {
        defer { previewInsertionIndex = nil }

        if let insertionIndex = FolderDragPreviewPlanner.insertionIndex(
            draggingAppID: draggingFolderAppID,
            visibleApps: visibleApps,
            displaySlots: displaySlots,
            metrics: metrics,
            location: location,
            previewInsertionIndex: previewInsertionIndex
        ) {
            onDropToInsertionIndex(globalInsertionIndex(for: insertionIndex))
            return
        }

        let fallbackInsertionIndex = previewInsertionIndex
            ?? visibleApps.filter { $0.id != draggingFolderAppID }.count
        onDropToInsertionIndex(globalInsertionIndex(for: fallbackInsertionIndex))
    }

    private func globalInsertionIndex(for localInsertionIndex: Int) -> Int {
        let pageStart = currentPage * max(1, folderPageSize)
        let remainingCount = max(0, apps.count - (draggingFolderAppID == nil ? 0 : 1))
        return max(0, min(pageStart + localInsertionIndex, remainingCount))
    }
}
