import CoreGraphics
import Foundation
import os

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var allApps: [AppItem] = []
    @Published private(set) var rootEntries: [LauncherEntry] = []
    @Published private(set) var pages: [[LauncherEntry]] = []
    @Published var query = "" {
        didSet { scheduleFilter() }
    }
    @Published var currentPage = 0
    @Published private(set) var pageTransitionDirection = 1
    @Published private(set) var isEditing = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = "正在读取应用列表..."
    @Published var lastError: String?
    @Published private(set) var activeFolder: FolderItem?
    @Published private(set) var draggingEntryID: String?
    @Published private(set) var draggingFolderAppID: String?

    private let appLauncher: AppLaunchClient
    private let catalogClient: LauncherCatalogClient
    private let layoutPersistence: LauncherLayoutPersistence
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Store")

    private var pageSize = 35
    private var filteredEntries: [LauncherEntry] = []
    private var searchIndex = LauncherSearchIndex()
    private var draggingFolderID: String?
    private var edgeHoverDirection: Int?
    private var edgeHoverStartedAt = Date.distantPast
    private var lastEdgeFlipAt = Date.distantPast
    private var dragAutoClearToken = UUID()
    private var persistenceTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var metadataEnrichmentTask: Task<Void, Never>?
    private var layoutMutationVersion: UInt64 = 0
    private var lastPersistedFingerprint: UInt64?
    private var isPersistenceSuspended = false
    private var hasLoadedCatalog = false

    init(
        layoutPersistence: LauncherLayoutPersistence = LauncherLayoutPersistence(),
        catalogClient: LauncherCatalogClient = .live,
        appLauncher: AppLaunchClient = .live,
        autoReload: Bool = true
    ) {
        self.layoutPersistence = layoutPersistence
        self.catalogClient = catalogClient
        self.appLauncher = appLauncher

        if autoReload {
            Task { await reload() }
        }
    }

    func reload() async {
        let reloadStart = DispatchTime.now()
        await flushPendingPersistence()
        cancelReloadTasks()
        isPersistenceSuspended = false
        isLoading = true
        lastError = nil
        statusMessage = "正在扫描本机应用..."
        lastPersistedFingerprint = nil

        let persistedLayout = await loadPersistedLayout()
        let loaded = await Task.detached(priority: .userInitiated) { [catalogClient] in
            catalogClient.loadApplications()
        }.value

        allApps = loaded
        rootEntries = LauncherLayoutMerger.merge(apps: loaded, persisted: persistedLayout)
        hasLoadedCatalog = true
        layoutMutationVersion &+= 1
        searchIndex.markDirty()
        activeFolder = nil
        clearDragging()

        if !isPersistenceSuspended {
            await persistCurrentLayoutIfNeeded()
        }

        statusMessage = defaultStatusMessage()
        isLoading = false
        applyFilter(resetPage: true)
        startMetadataEnrichmentIfNeeded(initialApps: loaded)

        let elapsedMs = DispatchTime.now().uptimeNanoseconds - reloadStart.uptimeNanoseconds
        logger.info("store.reload.fast count=\(loaded.count, privacy: .public) elapsed_ms=\(Double(elapsedMs) / 1_000_000, privacy: .public)")
    }

    func flushPendingPersistence() async {
        guard !isPersistenceSuspended, hasLoadedCatalog else { return }
        persistenceTask?.cancel()
        persistenceTask = nil
        await persistCurrentLayoutIfNeeded()
    }

    func launch(_ app: AppItem) {
        statusMessage = "正在打开 \(app.name)..."
        appLauncher.launch(app) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = error
                    self.statusMessage = "打开失败：\(app.name)"
                } else {
                    self.statusMessage = "已打开 \(app.name)"
                }
            }
        }
    }

    func previousPage() {
        guard !pages.isEmpty else { return }
        goToPage(max(currentPage - 1, 0))
    }

    func nextPage() {
        guard !pages.isEmpty else { return }
        goToPage(min(currentPage + 1, pages.count - 1))
    }

    func goToPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        pageTransitionDirection = index >= currentPage ? 1 : -1
        currentPage = index
    }

    func updatePageSize(_ newPageSize: Int) {
        let resolved = max(1, newPageSize)
        guard resolved != pageSize else { return }

        let oldPageSize = pageSize
        let anchorIndex = max(0, currentPage * oldPageSize)
        pageSize = resolved
        applyFilter()

        guard !pages.isEmpty else {
            currentPage = 0
            return
        }

        let anchoredPage = min(anchorIndex / resolved, pages.count - 1)
        pageTransitionDirection = anchoredPage >= currentPage ? 1 : -1
        currentPage = anchoredPage
    }

    func enterEditMode() {
        guard queryKeyword.isEmpty else { return }
        if !isEditing {
            isEditing = true
            statusMessage = "编辑模式：拖拽可重排或分组"
        }
    }

    func exitEditMode() {
        guard isEditing else { return }
        isEditing = false
        clearDragging()
        statusMessage = activeFolder.map { "已打开文件夹：\($0.name)" } ?? defaultStatusMessage()
    }

    func openFolder(_ folder: FolderItem) {
        guard queryKeyword.isEmpty else { return }
        activeFolder = folder
        statusMessage = "已打开文件夹：\(folder.name)"
    }

    func closeFolder() {
        activeFolder = nil
        if queryKeyword.isEmpty {
            statusMessage = defaultStatusMessage()
        }
    }

    func beginDragging(_ entry: LauncherEntry) {
        guard queryKeyword.isEmpty else { return }
        enterEditMode()
        activeFolder = nil
        draggingFolderAppID = nil
        draggingFolderID = nil
        draggingEntryID = entry.id
        clearPageEdgeHover()
        scheduleDragAutoClear()
    }

    func beginFolderDragging(app: AppItem, folderID: String) {
        guard queryKeyword.isEmpty else { return }
        enterEditMode()
        draggingEntryID = nil
        draggingFolderID = folderID
        draggingFolderAppID = app.id
        clearPageEdgeHover()
        scheduleDragAutoClear()
    }

    func clearDragging() {
        draggingEntryID = nil
        draggingFolderAppID = nil
        draggingFolderID = nil
        clearPageEdgeHover()
        dragAutoClearToken = UUID()
    }

    func handleDrop(on targetEntry: LauncherEntry, location: CGPoint, tileSize: CGSize) {
        guard queryKeyword.isEmpty else {
            clearDragging()
            return
        }

        guard let draggedID = draggingEntryID, draggedID != targetEntry.id else {
            clearDragging()
            return
        }

        let groupZone = groupingRect(in: tileSize)
        let draggedName = layoutEditor().rootEntry(id: draggedID)?.displayName ?? ""
        let isGrouping = groupZone.contains(location)
        var groupedFolder: FolderItem?

        let didChange = mutateLayout { editor in
            if isGrouping, editor.canGroup(draggedID: draggedID, targetID: targetEntry.id) {
                groupedFolder = editor.group(draggedID: draggedID, targetID: targetEntry.id)
                return groupedFolder != nil
            }

            return editor.reorderRootEntry(draggedID: draggedID, targetID: targetEntry.id)
        }

        if didChange {
            if let groupedFolder {
                activeFolder = groupedFolder
                if targetEntry.folderValue != nil {
                    statusMessage = "已将 \(draggedName) 放入 \(groupedFolder.name)"
                } else {
                    statusMessage = "已创建文件夹：\(groupedFolder.name)"
                }
            } else {
                statusMessage = "已重排图标顺序"
            }
            scheduleLayoutPersist()
        }

        clearDragging()
        applyFilter()
    }

    func handleDropToPageEnd() {
        guard queryKeyword.isEmpty else {
            clearDragging()
            return
        }
        dropDraggedEntryAtCurrentPageBoundary(direction: 1)
    }

    func folderApps(in folder: FolderItem) -> [AppItem] {
        layoutEditor().folderApps(in: folder)
    }

    func renameFolder(id folderID: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let shouldKeepOpened = activeFolder?.id == folderID
        var renamedFolder: FolderItem?

        let didChange = mutateLayout { editor in
            renamedFolder = editor.renameFolder(id: folderID, to: trimmed)
            return renamedFolder != nil
        }

        guard didChange else { return }

        scheduleLayoutPersist()
        applyFilter()
        if shouldKeepOpened, let renamedFolder {
            activeFolder = renamedFolder
        }
        statusMessage = "已将文件夹重命名为 \(renamedFolder?.name ?? trimmed)"
    }

    func handleFolderDrop(on targetApp: AppItem, folderID: String) {
        guard queryKeyword.isEmpty else {
            clearDragging()
            return
        }
        guard draggingFolderID == folderID, let draggedID = draggingFolderAppID, draggedID != targetApp.id else {
            clearDragging()
            return
        }

        var updatedFolder: FolderItem?
        let didChange = mutateLayout { editor in
            updatedFolder = editor.reorderFolderApp(
                folderID: folderID,
                draggedAppID: draggedID,
                targetAppID: targetApp.id
            )
            return updatedFolder != nil
        }

        if didChange {
            scheduleLayoutPersist()
            applyFilter()
            if let updatedFolder {
                activeFolder = updatedFolder
                statusMessage = "已在 \(updatedFolder.name) 内重排"
            }
        }
        clearDragging()
    }

    func handleFolderDropToEnd(folderID: String) {
        handleFolderDropToPageBoundary(folderID: folderID, currentPage: nil, direction: 1, pageSize: pageSize)
    }

    func handleFolderDropToPageBoundary(folderID: String, currentPage: Int?, direction: Int, pageSize: Int) {
        guard queryKeyword.isEmpty else {
            clearDragging()
            return
        }
        guard draggingFolderID == folderID, let draggedID = draggingFolderAppID else {
            clearDragging()
            return
        }

        var updatedFolder: FolderItem?
        let didChange = mutateLayout { editor in
            updatedFolder = editor.moveFolderAppToBoundary(
                folderID: folderID,
                draggedAppID: draggedID,
                currentPage: currentPage,
                direction: direction,
                pageSize: pageSize
            )
            return updatedFolder != nil
        }

        if didChange {
            scheduleLayoutPersist()
            applyFilter()
            if let updatedFolder {
                activeFolder = updatedFolder
                statusMessage = "已在 \(updatedFolder.name) 内跨页移动"
            }
        }
        clearDragging()
    }

    func extractDraggingFolderAppToRoot() {
        guard queryKeyword.isEmpty else {
            clearDragging()
            return
        }
        guard let folderID = draggingFolderID, let draggedAppID = draggingFolderAppID else {
            clearDragging()
            return
        }

        var extractedApp: AppItem?
        let didChange = mutateLayout { editor in
            extractedApp = editor.extractFolderAppToRoot(folderID: folderID, appID: draggedAppID)
            return extractedApp != nil
        }

        if didChange {
            activeFolder = nil
            statusMessage = "已将 \(extractedApp?.name ?? "应用") 移出文件夹"
            scheduleLayoutPersist()
            applyFilter()
        }
        clearDragging()
    }

    func handleDragHoverAtPageEdge(direction: Int) {
        guard queryKeyword.isEmpty, activeFolder == nil else { return }
        guard draggingEntryID != nil else { return }
        guard !pages.isEmpty else { return }

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
            goToPage(currentPage - 1)
            lastEdgeFlipAt = now
        } else if direction > 0, currentPage < pages.count - 1 {
            goToPage(currentPage + 1)
            lastEdgeFlipAt = now
        }
    }

    func clearPageEdgeHover() {
        edgeHoverDirection = nil
        edgeHoverStartedAt = Date.distantPast
        lastEdgeFlipAt = Date.distantPast
    }

    func dropDraggedEntryAtCurrentPageBoundary(direction: Int) {
        guard queryKeyword.isEmpty else {
            clearDragging()
            return
        }
        guard let draggedID = draggingEntryID else {
            clearDragging()
            return
        }
        guard pages.indices.contains(currentPage) else {
            clearDragging()
            return
        }

        let pageStart = currentPage * pageSize
        let pageCount = pages[currentPage].count
        let pageEndExclusive = pageStart + pageCount
        let targetIndex = direction < 0 ? pageStart : pageEndExclusive

        let didChange = mutateLayout { editor in
            editor.moveRootEntry(id: draggedID, to: targetIndex)
        }

        if didChange {
            scheduleLayoutPersist()
            statusMessage = direction < 0 ? "已跨页移动到当前页开头" : "已跨页移动到当前页末尾"
        }
        clearDragging()
        applyFilter()
    }

    private func cancelReloadTasks() {
        persistenceTask?.cancel()
        persistenceTask = nil
        filterTask?.cancel()
        filterTask = nil
        metadataEnrichmentTask?.cancel()
        metadataEnrichmentTask = nil
    }

    private func loadPersistedLayout() async -> LauncherLayoutSnapshot? {
        do {
            return try await Task.detached(priority: .utility) { [layoutPersistence] in
                try layoutPersistence.load()
            }.value
        } catch let error as LauncherLayoutPersistenceError {
            switch error {
            case let .incompatibleSchema(version, backupPath):
                isPersistenceSuspended = true
                lastError = "布局版本不兼容（schema v\(version)），已备份到：\(backupPath)。请升级应用后再恢复。"
            }
            return nil
        } catch {
            lastError = "布局文件损坏，已自动重置。"
            return nil
        }
    }

    private func startMetadataEnrichmentIfNeeded(initialApps: [AppItem]) {
        guard !initialApps.isEmpty else { return }

        metadataEnrichmentTask = Task { [initialApps, catalogClient] in
            defer { self.metadataEnrichmentTask = nil }
            let enriched = await Task.detached(priority: .utility) {
                catalogClient.enrichApplications(initialApps)
            }.value

            guard !Task.isCancelled else { return }
            guard self.allApps.map(\.id) == initialApps.map(\.id) else { return }
            guard self.allApps != enriched else { return }

            self.applyMetadataUpdate(enriched)
        }
    }

    private func applyMetadataUpdate(_ apps: [AppItem]) {
        let appByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        allApps = apps
        rootEntries = rootEntries.map { entry in
            switch entry {
            case let .app(app):
                return .app(appByID[app.id] ?? app)
            case let .folder(folder):
                var updatedFolder = folder
                updatedFolder.apps = folder.apps.map { appByID[$0.id] ?? $0 }
                return .folder(updatedFolder)
            }
        }

        searchIndex.markDirty()
        applyFilter()
    }

    private func scheduleFilter(resetPage: Bool = false, immediate: Bool = false) {
        filterTask?.cancel()
        let querySnapshot = query
        let delayNanoseconds: UInt64 = immediate || querySnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? 0
            : 160_000_000

        filterTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard querySnapshot == self.query else { return }
            self.applyFilter(resetPage: resetPage)
            self.filterTask = nil
        }
    }

    private func applyFilter(resetPage: Bool = false) {
        let filterStart = DispatchTime.now()
        let keyword = queryKeyword

        if keyword.isEmpty {
            filteredEntries = rootEntries
        } else {
            filteredEntries = searchIndex.filter(entries: rootEntries, keyword: keyword)

            if isEditing {
                isEditing = false
            }
            if activeFolder != nil {
                activeFolder = nil
            }
        }

        pages = LauncherPaging.chunked(filteredEntries, pageSize: pageSize)
        syncActiveFolder()

        guard !pages.isEmpty else {
            currentPage = 0
            return
        }

        if resetPage {
            currentPage = 0
        } else {
            currentPage = min(currentPage, pages.count - 1)
        }

        if !keyword.isEmpty {
            let elapsedMs = DispatchTime.now().uptimeNanoseconds - filterStart.uptimeNanoseconds
            logger.info("store.filter keyword_len=\(keyword.count, privacy: .public) result=\(self.filteredEntries.count, privacy: .public) elapsed_ms=\(Double(elapsedMs) / 1_000_000, privacy: .public)")
        }
    }

    private var queryKeyword: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncActiveFolder() {
        guard let activeFolder else { return }
        self.activeFolder = layoutEditor().currentFolder(id: activeFolder.id)
    }

    private func groupingRect(in size: CGSize) -> CGRect {
        let width = min(84, size.width * 0.76)
        let height = min(90, size.height * 0.68)
        return CGRect(
            x: (size.width - width) * 0.5,
            y: 4,
            width: width,
            height: height
        )
    }

    private func defaultStatusMessage() -> String {
        rootEntries.isEmpty ? "未发现可展示的应用。" : "共 \(allApps.count) 个应用，可拖拽分组或重排"
    }

    private func layoutEditor() -> LauncherLayoutEditor {
        LauncherLayoutEditor(entries: rootEntries)
    }

    @discardableResult
    private func mutateLayout(_ mutation: (inout LauncherLayoutEditor) -> Bool) -> Bool {
        var editor = layoutEditor()
        let didChange = mutation(&editor)
        guard didChange else { return false }

        rootEntries = editor.entries
        layoutMutationVersion &+= 1
        searchIndex.markDirty()
        return true
    }

    private func scheduleLayoutPersist(delayNanoseconds: UInt64 = 260_000_000) {
        guard !isPersistenceSuspended else { return }
        persistenceTask?.cancel()

        let expectedVersion = layoutMutationVersion
        let snapshot = LauncherLayoutSnapshot(rootEntries: rootEntries)
        let fingerprint = LauncherLayoutEditor.layoutFingerprint(of: rootEntries)

        persistenceTask = Task { [weak self, snapshot, fingerprint, expectedVersion] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.persistScheduledLayout(
                snapshot: snapshot,
                fingerprint: fingerprint,
                expectedVersion: expectedVersion
            )
        }
    }

    private func persistScheduledLayout(
        snapshot: LauncherLayoutSnapshot,
        fingerprint: UInt64,
        expectedVersion: UInt64
    ) async {
        guard expectedVersion == layoutMutationVersion else { return }
        await persist(snapshot: snapshot, fingerprint: fingerprint)
        if expectedVersion == layoutMutationVersion {
            persistenceTask = nil
        }
    }

    private func persistCurrentLayoutIfNeeded() async {
        let snapshot = LauncherLayoutSnapshot(rootEntries: rootEntries)
        let fingerprint = LauncherLayoutEditor.layoutFingerprint(of: rootEntries)
        await persist(snapshot: snapshot, fingerprint: fingerprint)
    }

    private func persist(snapshot: LauncherLayoutSnapshot, fingerprint: UInt64) async {
        guard !isPersistenceSuspended else { return }
        guard fingerprint != lastPersistedFingerprint else { return }

        do {
            try await layoutPersistence.saveAsync(snapshot)
            lastPersistedFingerprint = fingerprint
            lastError = nil
        } catch {
            lastError = "保存布局失败：\(error.localizedDescription)"
        }
    }

    private func scheduleDragAutoClear() {
        let token = UUID()
        dragAutoClearToken = token

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard self.dragAutoClearToken == token else { return }
            self.clearDragging()
        }
    }
}
