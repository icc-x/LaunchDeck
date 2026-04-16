import AppKit
import SwiftUI

struct ContentView: View {
    private enum Layout {
        static let edgePaddingScale: CGFloat = 0.38
        static let mainStackSpacing: CGFloat = 10
        static let mainHorizontalPadding: CGFloat = 32 * edgePaddingScale
        static let mainVerticalPadding: CGFloat = 24 * edgePaddingScale
        static let footerBottomInset: CGFloat = 4
    }

    @ObservedObject var store: LauncherStore
    @ObservedObject var preferences: LauncherPreferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var iconProvider = AppIconProvider()
    @State private var folderPreviewIconProvider = AppIconProvider(iconSize: NSSize(width: 28, height: 28))
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
                    LauncherHeaderBar(
                        query: $store.query,
                        controlForeground: theme.controlForeground,
                        refreshHint: LaunchDeckStrings.refreshApps,
                        onOpenSettings: {
                            openWindow(id: "settings")
                        },
                        onReload: {
                            Task { await store.reload() }
                        },
                        searchFocused: $searchFocused
                    )

                    bodyContent
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
                    LauncherFooterBar(
                        statusMessage: store.statusMessage,
                        pagesCount: store.pages.count,
                        currentPage: store.currentPage,
                        showDetails: preferences.showStatusDetails,
                        detailText: store.footerDetailText,
                        pageIndicatorActive: theme.pageIndicatorActive,
                        pageIndicatorInactive: theme.pageIndicatorInactive,
                        textSecondary: theme.textSecondary,
                        onGoToPage: { index in
                            store.goToPage(index)
                        }
                    )
                    .padding(.bottom, Layout.footerBottomInset)
                }
                .padding(.horizontal, Layout.mainHorizontalPadding)
                .padding(.vertical, Layout.mainVerticalPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)

                if let folder = store.activeFolder {
                    LauncherFolderOverlayContainer(
                        folder: folder,
                        apps: store.folderApps(in: folder),
                        isDraggingFolderApp: store.draggingFolderAppID != nil,
                        draggingFolderAppID: store.draggingFolderAppID,
                        folderPageSize: preferences.folderPageSize,
                        wheelPagingEnabled: preferences.enableWheelPaging,
                        iconProvider: iconProvider,
                        folderPreviewIconProvider: folderPreviewIconProvider,
                        namespace: folderNamespace,
                        theme: theme,
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
                        onDropToInsertionIndex: { insertionIndex in
                            withAnimation(LaunchMotion.reorder) {
                                store.handleFolderDrop(
                                    folderID: folder.id,
                                    toInsertionIndex: insertionIndex
                                )
                            }
                        },
                        onDropToFolderPageBoundary: { page, direction, pageSize in
                            withAnimation(LaunchMotion.reorder) {
                                store.handleFolderDropToPageBoundary(
                                    folderID: folder.id,
                                    currentPage: page,
                                    direction: direction,
                                    pageSize: pageSize
                                )
                            }
                        },
                        onDropExtract: {
                            withAnimation(LaunchMotion.reorder) {
                                store.extractDraggingFolderAppToRoot()
                            }
                        }
                    )
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
            if preferences.focusSearchOnLaunch {
                searchFocused = true
            }
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
        .onChange(of: preferences.prefetchPageDepth) { _, _ in
            prefetchVisibleIcons()
        }
        .onChange(of: preferences.focusSearchOnLaunch) { _, focused in
            if focused {
                searchFocused = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                prefetchVisibleIcons()
            } else if phase == .background {
                lastPrefetchKey = ""
                iconProvider.clearCache()
                folderPreviewIconProvider.clearCache()
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if store.isLoading {
            Spacer()
            ProgressView(LaunchDeckStrings.loadingApps)
                .controlSize(.large)
                .foregroundStyle(theme.textPrimary)
            Spacer()
        } else if store.pages.isEmpty {
            Spacer()
            ContentUnavailableView(
                LaunchDeckStrings.emptyTitle,
                systemImage: "magnifyingglass",
                description: Text(LaunchDeckStrings.emptyDescription)
            )
            .foregroundStyle(theme.textPrimary)
            Spacer()
        } else if store.pages.indices.contains(store.currentPage) {
            LauncherGridContainerView(
                allEntries: store.rootEntries,
                entries: store.pages[store.currentPage],
                isSearchMode: isSearchMode,
                currentPage: store.currentPage,
                pageCount: store.pages.count,
                transitionDirection: store.pageTransitionDirection,
                draggingEntryID: store.draggingEntryID,
                isFolderOpen: store.activeFolder != nil,
                iconProvider: iconProvider,
                folderPreviewIconProvider: folderPreviewIconProvider,
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
                onDropOnEntry: { entry, location, size in
                    withAnimation(LaunchMotion.reorder) {
                        store.handleDrop(on: entry, location: location, tileSize: size)
                    }
                },
                onDropToInsertionIndex: { insertionIndex in
                    withAnimation(LaunchMotion.reorder) {
                        store.handleDrop(toRootInsertionIndex: insertionIndex)
                    }
                },
                onPageCapacityChange: { capacity in
                    store.updatePageSize(capacity)
                },
                onPageEdgeHover: { direction in
                    store.handleDragHoverAtPageEdge(direction: direction)
                },
                onPageEdgeExit: {
                    store.clearPageEdgeHover()
                },
                onDropAtPageBoundary: { direction in
                    withAnimation(LaunchMotion.reorder) {
                        store.dropDraggedEntryAtCurrentPageBoundary(direction: direction)
                    }
                },
                onWheelPageChange: handleMainWheelPaging(_:)
            )
        }
    }

    private var isSearchMode: Bool {
        !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleMainWheelPaging(_ event: NSEvent) -> Bool {
        guard preferences.enableWheelPaging else { return false }
        guard store.activeFolder == nil, store.pages.count > 1 else { return false }

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

    private func prefetchVisibleIcons() {
        var apps: [AppItem] = []
        var folderPreviewApps: [AppItem] = []

        func appendEntries(_ entries: ArraySlice<LauncherEntry>) {
            for entry in entries {
                switch entry {
                case let .app(app):
                    apps.append(app)
                case let .folder(folder):
                    folderPreviewApps.append(contentsOf: folder.apps.prefix(4))
                }
            }
        }

        let depth = max(0, preferences.prefetchPageDepth)
        for offset in 0...depth {
            let pageIndex = store.currentPage + offset
            if store.pages.indices.contains(pageIndex) {
                appendEntries(store.pages[pageIndex])
            }
        }

        if let folder = store.activeFolder {
            let folderApps = store.folderApps(in: folder)
            let folderPrefetchCount = preferences.folderPageSize
            apps.append(contentsOf: folderApps.prefix(folderPrefetchCount))
            folderPreviewApps.append(contentsOf: folderApps.prefix(4))
        }

        var dedupedMain: [AppItem] = []
        dedupedMain.reserveCapacity(apps.count)
        var seen = Set<String>()
        for app in apps where seen.insert(app.id).inserted {
            dedupedMain.append(app)
        }

        var dedupedPreview: [AppItem] = []
        dedupedPreview.reserveCapacity(folderPreviewApps.count)
        seen.removeAll(keepingCapacity: true)
        for app in folderPreviewApps where seen.insert(app.id).inserted {
            dedupedPreview.append(app)
        }

        let prefetchKey = (dedupedMain.map(\.id) + ["#"] + dedupedPreview.map(\.id)).joined(separator: "|")
        guard prefetchKey != lastPrefetchKey else { return }
        lastPrefetchKey = prefetchKey
        iconProvider.prefetch(dedupedMain)
        folderPreviewIconProvider.prefetch(dedupedPreview)
    }

    private func errorToast(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(theme.controlForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.controlFillStrong, in: Capsule())
            .overlay(
                Capsule().stroke(theme.controlStroke, lineWidth: 1)
            )
    }
}
