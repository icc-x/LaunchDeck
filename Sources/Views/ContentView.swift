import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum Layout {
        static let edgePaddingScale: CGFloat = 0.38
        static let mainStackSpacing: CGFloat = 10
        static let mainHorizontalPadding: CGFloat = 32 * edgePaddingScale
        static let mainVerticalPadding: CGFloat = 24 * edgePaddingScale
        static let footerBottomInset: CGFloat = 4
    }

    @ObservedObject var store: LauncherStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var iconProvider = AppIconProvider()
    @FocusState private var searchFocused: Bool
    @Namespace private var folderNamespace
    @State private var lastWheelFlipAt = Date.distantPast
    @State private var lastPrefetchKey = ""

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                LaunchpadBackdrop()

                VStack(spacing: Layout.mainStackSpacing) {
                    header
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, Layout.mainHorizontalPadding)
                .padding(.vertical, Layout.mainVerticalPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .opacity(store.activeFolder == nil ? 1 : 0.94)
                .scaleEffect(store.activeFolder == nil ? 1 : 0.995)
                .animation(LaunchMotion.smooth, value: store.activeFolder != nil)

                VStack {
                    Spacer(minLength: 0)
                    footer
                        .padding(.bottom, Layout.footerBottomInset)
                }
                .padding(.horizontal, Layout.mainHorizontalPadding)
                .padding(.vertical, Layout.mainVerticalPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)

                if let folder = store.activeFolder {
                    folderLayer(folder)
                }

                if let lastError = store.lastError {
                    errorToast(lastError)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .onAppear {
            searchFocused = true
            prefetchVisibleIcons()
        }
        .onChange(of: store.currentPage) { _, _ in
            prefetchVisibleIcons()
        }
        .onChange(of: store.pages) { _, _ in
            prefetchVisibleIcons()
        }
        .onChange(of: store.activeFolder?.id) { _, _ in
            prefetchVisibleIcons()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            SearchField(text: $store.query)
                .focused($searchFocused)
                .frame(maxWidth: 540)

            Spacer(minLength: 0)

            if store.isEditing {
                Button("完成") {
                    store.exitEditMode()
                }
                .buttonStyle(.borderedProminent)
                .tint(colorScheme == .dark ? .white.opacity(0.22) : .black.opacity(0.14))
                .foregroundStyle(theme.controlForeground)
            }

            Button {
                Task { await store.reload() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(theme.controlForeground)
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("刷新应用列表")
        }
        .frame(maxWidth: .infinity)
    }

    private var content: some View {
        Group {
            if store.isLoading {
                Spacer()
                ProgressView("正在加载应用")
                    .controlSize(.large)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            } else if store.pages.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "没有匹配的应用",
                    systemImage: "magnifyingglass",
                    description: Text("尝试修改关键字，或点击右上角刷新。")
                )
                .foregroundStyle(theme.textPrimary)
                Spacer()
            } else if store.pages.indices.contains(store.currentPage) {
                ZStack {
                    AppGridPageView(
                        entries: store.pages[store.currentPage],
                        isSearchMode: isSearchMode,
                        isEditing: store.isEditing,
                        iconProvider: iconProvider,
                        namespace: folderNamespace,
                        onLaunch: { app in
                            store.launch(app)
                        },
                        onOpenFolder: { folder in
                            withAnimation(LaunchMotion.modal) {
                                store.openFolder(folder)
                            }
                        },
                        onBeginDragging: { entry in
                            store.beginDragging(entry)
                        },
                        onEnterEditMode: {
                            store.enterEditMode()
                        },
                        onDropOnEntry: { entry, location, size in
                            store.handleDrop(on: entry, location: location, tileSize: size)
                        },
                        onDropToPageEnd: {
                            store.handleDropToPageEnd()
                        },
                        onPageCapacityChange: { capacity in
                            store.updatePageSize(capacity)
                        }
                    )
                    .id("page-\(store.currentPage)")
                    .transition(pageTransition)
                    .animation(LaunchMotion.page, value: store.currentPage)
                    .overlay {
                        if canUseWheelPaging {
                            ScrollWheelCaptureView { event in
                                handleMainWheelPaging(event)
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
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text(store.statusMessage)
                .font(.callout)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)

            if store.pages.count > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<store.pages.count, id: \.self) { index in
                        Button {
                            store.goToPage(index)
                        } label: {
                            Circle()
                                .fill(index == store.currentPage ? theme.pageIndicatorActive : theme.pageIndicatorInactive)
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var isSearchMode: Bool {
        !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showPageEdgeDropZones: Bool {
        store.draggingEntryID != nil && !isSearchMode && store.activeFolder == nil && store.pages.count > 1
    }

    private var canUseWheelPaging: Bool {
        !isSearchMode && store.activeFolder == nil && store.pages.count > 1
    }

    private var pageTransition: AnyTransition {
        if store.pageTransitionDirection >= 0 {
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

    private func handleMainWheelPaging(_ event: NSEvent) -> Bool {
        guard canUseWheelPaging else { return false }

        let now = Date()
        guard now.timeIntervalSince(lastWheelFlipAt) >= 0.16 else { return false }

        guard let targetPage = WheelPageResolver.targetPage(
            currentPage: store.currentPage,
            pageCount: store.pages.count,
            event: event
        ) else {
            return false
        }

        store.goToPage(targetPage)
        lastWheelFlipAt = now
        return true
    }

    private func folderLayer(_ folder: FolderItem) -> some View {
        ZStack {
            theme.modalMask
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(LaunchMotion.modal) {
                        store.closeFolder()
                    }
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: FolderExtractDropDelegate(
                        canExtract: { store.draggingFolderAppID != nil },
                        onDropExtract: {
                            store.extractDraggingFolderAppToRoot()
                        }
                    )
                )

            if store.draggingFolderAppID != nil {
                Text("拖到文件夹外部可移出")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.controlForeground)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(theme.dragHintStroke, lineWidth: 1)
                    )
                    .padding(.top, 28)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            FolderOverlayView(
                folder: folder,
                apps: store.folderApps(in: folder),
                isEditing: store.isEditing,
                isDraggingFolderApp: store.draggingFolderAppID != nil,
                iconProvider: iconProvider,
                namespace: folderNamespace,
                onClose: {
                    withAnimation(LaunchMotion.modal) {
                        store.closeFolder()
                    }
                },
                onRename: { name in
                    store.renameFolder(id: folder.id, to: name)
                },
                onLaunch: { app in
                    store.launch(app)
                },
                onBeginDragging: { app in
                    store.beginFolderDragging(app: app, folderID: folder.id)
                },
                onEnterEditMode: {
                    store.enterEditMode()
                },
                onDropOnApp: { app in
                    store.handleFolderDrop(on: app, folderID: folder.id)
                },
                onDropToFolderPageBoundary: { page, direction, pageSize in
                    store.handleFolderDropToPageBoundary(
                        folderID: folder.id,
                        currentPage: page,
                        direction: direction,
                        pageSize: pageSize
                    )
                },
                onDropToFolderEnd: {
                    store.handleFolderDropToEnd(folderID: folder.id)
                }
            )
            .padding(.horizontal, 72)
            .padding(.vertical, 38)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.965).combined(with: .opacity),
                removal: .scale(scale: 1.015).combined(with: .opacity)
            ))
            .animation(LaunchMotion.modal, value: store.activeFolder?.id ?? "")
        }
        .animation(LaunchMotion.quickFade, value: store.draggingFolderAppID != nil)
    }

    private func prefetchVisibleIcons() {
        var apps: [AppItem] = []

        func appendEntries(_ entries: [LauncherEntry]) {
            for entry in entries {
                switch entry {
                case let .app(app):
                    apps.append(app)
                case let .folder(folder):
                    apps.append(contentsOf: folder.apps.prefix(4))
                }
            }
        }

        if store.pages.indices.contains(store.currentPage) {
            appendEntries(store.pages[store.currentPage])
        }

        let nextPage = store.currentPage + 1
        if store.pages.indices.contains(nextPage) {
            appendEntries(store.pages[nextPage])
        }

        if let folder = store.activeFolder {
            apps.append(contentsOf: store.folderApps(in: folder))
        }

        var deduped: [AppItem] = []
        deduped.reserveCapacity(apps.count)
        var seen = Set<String>()
        for app in apps where seen.insert(app.id).inserted {
            deduped.append(app)
        }

        let prefetchKey = deduped.map(\.id).joined(separator: "|")
        guard prefetchKey != lastPrefetchKey else { return }
        lastPrefetchKey = prefetchKey
        iconProvider.prefetch(deduped)
    }

    private func errorToast(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(theme.controlForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(theme.controlStroke, lineWidth: 1)
            )
    }

    private func edgeDropZone(direction: Int) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.001))
            .frame(width: 72)
            .contentShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                delegate: EdgePageDropDelegate(
                    direction: direction,
                    onHover: {
                        store.handleDragHoverAtPageEdge(direction: direction)
                    },
                    onExit: {
                        store.clearPageEdgeHover()
                    },
                    onDropAtBoundary: {
                        store.dropDraggedEntryAtCurrentPageBoundary(direction: direction)
                    }
                )
            )
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

private struct EdgePageDropDelegate: DropDelegate {
    let direction: Int
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
