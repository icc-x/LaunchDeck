import Foundation
import CoreGraphics
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

    private let launcher = AppLauncher()
    private let layoutPersistence: LauncherLayoutPersistence
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Store")
    private var pageSize = 35
    private var filteredEntries: [LauncherEntry] = []
    private var searchIndex: [SearchIndexItem] = []
    private var isSearchIndexDirty = true
    private var draggingFolderID: String?
    private var edgeHoverDirection: Int?
    private var edgeHoverStartedAt = Date.distantPast
    private var lastEdgeFlipAt = Date.distantPast
    private var dragAutoClearToken = UUID()
    private var persistenceTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var metadataEnrichmentTask: Task<Void, Never>?
    private var persistenceWriteTask: Task<Void, Never>?
    private var persistenceSaveSequence: UInt64 = 0
    private var layoutMutationVersion: UInt64 = 0
    private var lastPersistedFingerprint: UInt64?
    private var isPersistenceSuspended = false

    private struct SearchIndexItem: Sendable {
        let app: AppItem
        let normalizedName: String
    }

    init(layoutPersistence: LauncherLayoutPersistence = LauncherLayoutPersistence(), autoReload: Bool = true) {
        self.layoutPersistence = layoutPersistence
        if autoReload {
            Task { await reload() }
        }
    }

    func reload() async {
        let reloadStart = DispatchTime.now()
        persistenceTask?.cancel()
        persistenceTask = nil
        persistenceWriteTask?.cancel()
        persistenceWriteTask = nil
        persistenceSaveSequence &+= 1
        filterTask?.cancel()
        filterTask = nil
        metadataEnrichmentTask?.cancel()
        metadataEnrichmentTask = nil
        isPersistenceSuspended = false
        isLoading = true
        lastError = nil
        statusMessage = "正在扫描本机应用..."

        let persistedLayout: LauncherLayoutSnapshot?
        do {
            persistedLayout = try layoutPersistence.load()
        } catch let error as LauncherLayoutPersistenceError {
            persistedLayout = nil
            switch error {
            case let .incompatibleSchema(version, backupPath):
                isPersistenceSuspended = true
                lastError = "布局版本不兼容（schema v\(version)），已备份到：\(backupPath)。请升级应用后再恢复。"
            }
        } catch {
            persistedLayout = nil
            lastError = "布局文件损坏，已自动重置。"
        }

        let loaded = await Task.detached(priority: .userInitiated) {
            AppCatalogService().loadApplications()
        }.value

        allApps = loaded
        rootEntries = LauncherLayoutMerger.merge(apps: loaded, persisted: persistedLayout)
        layoutMutationVersion &+= 1
        markSearchIndexDirty()
        activeFolder = nil
        clearDragging()
        if !isPersistenceSuspended {
            let fingerprint = layoutFingerprint(of: rootEntries)
            persistLayoutNow(fingerprint: fingerprint)
        }
        statusMessage = loaded.isEmpty ? "未发现可展示的应用。" : "共 \(loaded.count) 个应用，可拖拽分组或重排"
        isLoading = false
        applyFilter(resetPage: true)
        startMetadataEnrichmentIfNeeded(initialApps: loaded)

        let elapsedMs = DispatchTime.now().uptimeNanoseconds - reloadStart.uptimeNanoseconds
        logger.info("store.reload.fast count=\(loaded.count, privacy: .public) elapsed_ms=\(Double(elapsedMs) / 1_000_000, privacy: .public)")
    }

    private func startMetadataEnrichmentIfNeeded(initialApps: [AppItem]) {
        guard !initialApps.isEmpty else { return }

        metadataEnrichmentTask = Task { [initialApps] in
            defer { self.metadataEnrichmentTask = nil }
            let enriched = await Task.detached(priority: .utility) {
                AppCatalogService().enrichApplications(initialApps)
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

        markSearchIndexDirty()
        applyFilter()
    }

    func flushPendingPersistence() {
        guard !isPersistenceSuspended else { return }
        persistenceTask?.cancel()
        persistenceTask = nil
        persistLayoutNow()
    }

    func launch(_ app: AppItem) {
        statusMessage = "正在打开 \(app.name)..."
        launcher.launch(app) { [weak self] error in
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
        if let folder = activeFolder {
            statusMessage = "已打开文件夹：\(folder.name)"
        } else {
            statusMessage = rootEntries.isEmpty ? "未发现可展示的应用。" : "共 \(allApps.count) 个应用，可拖拽分组或重排"
        }
    }

    func openFolder(_ folder: FolderItem) {
        guard queryKeyword.isEmpty else { return }
        activeFolder = folder
        statusMessage = "已打开文件夹：\(folder.name)"
    }

    func closeFolder() {
        activeFolder = nil
        if queryKeyword.isEmpty {
            statusMessage = rootEntries.isEmpty ? "未发现可展示的应用。" : "共 \(allApps.count) 个应用，可拖拽分组或重排"
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

        let previousFingerprint = layoutFingerprint(of: rootEntries)
        let groupZone = groupingRect(in: tileSize)
        if groupZone.contains(location), canGroup(draggedID: draggedID, targetID: targetEntry.id) {
            group(draggedID: draggedID, targetID: targetEntry.id)
        } else {
            reorder(draggedID: draggedID, targetID: targetEntry.id)
        }

        persistIfEntriesChanged(from: previousFingerprint)
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
        currentFolder(for: folder.id)?.apps ?? folder.apps
    }

    func renameFolder(id folderID: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let shouldKeepOpened = activeFolder?.id == folderID
        let previousFingerprint = layoutFingerprint(of: rootEntries)

        mutateFolder(id: folderID) { folder in
            folder.name = trimmed
        }
        persistIfEntriesChanged(from: previousFingerprint)
        applyFilter()
        if shouldKeepOpened, let folder = currentFolder(for: folderID) {
            activeFolder = folder
            statusMessage = "已将文件夹重命名为 \(folder.name)"
        } else {
            statusMessage = "已将文件夹重命名为 \(trimmed)"
        }
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

        let previousFingerprint = layoutFingerprint(of: rootEntries)
        mutateFolder(id: folderID) { folder in
            guard let from = folder.apps.firstIndex(where: { $0.id == draggedID }),
                  let to = folder.apps.firstIndex(where: { $0.id == targetApp.id }),
                  from != to else {
                return
            }

            let app = folder.apps.remove(at: from)
            let adjusted = from < to ? to - 1 : to
            folder.apps.insert(app, at: adjusted)
        }
        persistIfEntriesChanged(from: previousFingerprint)
        applyFilter()
        if let folder = currentFolder(for: folderID) {
            activeFolder = folder
            statusMessage = "已在 \(folder.name) 内重排"
        }
        clearDragging()
    }

    func handleFolderDropToEnd(folderID: String) {
        handleFolderDropToPageBoundary(folderID: folderID, currentPage: Int.max, direction: 1, pageSize: pageSize)
    }

    func handleFolderDropToPageBoundary(folderID: String, currentPage: Int, direction: Int, pageSize: Int) {
        guard queryKeyword.isEmpty else {
            clearDragging()
            return
        }
        guard draggingFolderID == folderID, let draggedID = draggingFolderAppID else {
            clearDragging()
            return
        }

        let previousFingerprint = layoutFingerprint(of: rootEntries)
        mutateFolder(id: folderID) { folder in
            guard let from = folder.apps.firstIndex(where: { $0.id == draggedID }) else { return }
            let app = folder.apps.remove(at: from)

            let resolvedPageSize = max(1, pageSize)
            let total = folder.apps.count
            if currentPage == Int.max {
                folder.apps.append(app)
                return
            }

            let pageStart = max(0, min(currentPage * resolvedPageSize, total))
            let pageEndExclusive = max(pageStart, min((currentPage + 1) * resolvedPageSize, total))
            let targetIndex = direction < 0 ? pageStart : pageEndExclusive
            let clamped = max(0, min(targetIndex, folder.apps.count))
            folder.apps.insert(app, at: clamped)
        }
        persistIfEntriesChanged(from: previousFingerprint)
        applyFilter()
        if let folder = currentFolder(for: folderID) {
            activeFolder = folder
            statusMessage = "已在 \(folder.name) 内跨页移动"
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

        let previousFingerprint = layoutFingerprint(of: rootEntries)
        guard let folderIndex = rootEntries.firstIndex(where: {
            guard case let .folder(folder) = $0 else { return false }
            return folder.id == folderID
        }), case var .folder(folder) = rootEntries[folderIndex] else {
            clearDragging()
            return
        }

        guard let appIndex = folder.apps.firstIndex(where: { $0.id == draggedAppID }) else {
            clearDragging()
            return
        }

        let extractedApp = folder.apps.remove(at: appIndex)

        if folder.apps.isEmpty {
            rootEntries.remove(at: folderIndex)
            rootEntries.insert(.app(extractedApp), at: folderIndex)
        } else if folder.apps.count == 1 {
            let remain = folder.apps[0]
            rootEntries[folderIndex] = .app(remain)
            rootEntries.insert(.app(extractedApp), at: min(folderIndex + 1, rootEntries.count))
        } else {
            rootEntries[folderIndex] = .folder(folder)
            rootEntries.insert(.app(extractedApp), at: min(folderIndex + 1, rootEntries.count))
        }

        activeFolder = nil
        statusMessage = "已将 \(extractedApp.name) 移出文件夹"
        persistIfEntriesChanged(from: previousFingerprint)
        clearDragging()
        applyFilter()
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

        let previousFingerprint = layoutFingerprint(of: rootEntries)
        let pageStart = currentPage * pageSize
        let pageCount = pages[currentPage].count
        let pageEndExclusive = pageStart + pageCount
        let targetIndex = direction < 0 ? pageStart : pageEndExclusive

        moveRootEntry(id: draggedID, to: targetIndex)
        persistIfEntriesChanged(from: previousFingerprint)
        statusMessage = direction < 0 ? "已跨页移动到当前页开头" : "已跨页移动到当前页末尾"
        clearDragging()
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
        let nextFilteredEntries: [LauncherEntry]

        if keyword.isEmpty {
            nextFilteredEntries = rootEntries
        } else {
            rebuildSearchIndexIfNeeded()
            let normalizedKeyword = normalizedSearchString(keyword)
            nextFilteredEntries = searchIndex
                .filter { $0.normalizedName.contains(normalizedKeyword) }
                .map { .app($0.app) }

            if isEditing {
                isEditing = false
            }
            if activeFolder != nil {
                activeFolder = nil
            }
        }

        // Always rebuild pages from the latest pageSize so resize can rebalance icons across pages.
        filteredEntries = nextFilteredEntries
        pages = chunked(filteredEntries, chunkSize: pageSize)

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

    private func markSearchIndexDirty() {
        isSearchIndexDirty = true
    }

    private func rebuildSearchIndexIfNeeded() {
        guard isSearchIndexDirty else { return }
        let apps = rootEntries.flatMap(\.flattenedApps)
        searchIndex = apps.map { app in
            SearchIndexItem(app: app, normalizedName: normalizedSearchString(app.name))
        }
        isSearchIndexDirty = false
    }

    private func normalizedSearchString(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private func chunked(_ items: [LauncherEntry], chunkSize: Int) -> [[LauncherEntry]] {
        guard !items.isEmpty else { return [] }
        guard chunkSize > 0 else { return [items] }

        var chunks: [[LauncherEntry]] = []
        chunks.reserveCapacity((items.count + chunkSize - 1) / chunkSize)

        var index = 0
        while index < items.count {
            let end = min(index + chunkSize, items.count)
            chunks.append(Array(items[index..<end]))
            index = end
        }

        return chunks
    }

    private var queryKeyword: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncActiveFolder() {
        guard let activeFolder else { return }
        self.activeFolder = currentFolder(for: activeFolder.id)
    }

    private func currentFolder(for folderID: String) -> FolderItem? {
        rootEntries
            .compactMap(\.folderValue)
            .first(where: { $0.id == folderID })
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

    private func canGroup(draggedID: String, targetID: String) -> Bool {
        guard let dragged = rootEntry(id: draggedID), let target = rootEntry(id: targetID) else {
            return false
        }

        switch (dragged, target) {
        case (.app, .app), (.app, .folder):
            return true
        default:
            return false
        }
    }

    private func reorder(draggedID: String, targetID: String) {
        guard let from = rootIndex(id: draggedID), let to = rootIndex(id: targetID), from != to else {
            return
        }

        moveRootEntry(from: from, to: to)
        statusMessage = "已重排图标顺序"
    }

    private func group(draggedID: String, targetID: String) {
        guard let dragged = rootEntry(id: draggedID), let target = rootEntry(id: targetID) else {
            return
        }

        switch (dragged, target) {
        case let (.app(draggedApp), .app(targetApp)):
            createFolder(draggedApp: draggedApp, targetApp: targetApp, draggedID: draggedID, targetID: targetID)
        case let (.app(draggedApp), .folder(folder)):
            append(app: draggedApp, into: folder, draggedID: draggedID)
        default:
            break
        }
    }

    private func createFolder(draggedApp: AppItem, targetApp: AppItem, draggedID: String, targetID: String) {
        guard let draggedIndex = rootIndex(id: draggedID), let targetIndex = rootIndex(id: targetID) else {
            return
        }

        let insertIndex = min(draggedIndex, targetIndex)
        for index in [draggedIndex, targetIndex].sorted(by: >) {
            rootEntries.remove(at: index)
        }

        let folder = FolderItem(
            id: UUID().uuidString,
            name: defaultFolderName(first: targetApp, second: draggedApp),
            apps: [targetApp, draggedApp]
        )
        rootEntries.insert(.folder(folder), at: insertIndex)
        activeFolder = folder
        statusMessage = "已创建文件夹：\(folder.name)"
    }

    private func append(app: AppItem, into folder: FolderItem, draggedID: String) {
        guard let draggedIndex = rootIndex(id: draggedID), let folderIndex = rootIndex(id: folder.entryID) else {
            return
        }

        rootEntries.remove(at: draggedIndex)
        let adjustedFolderIndex = draggedIndex < folderIndex ? folderIndex - 1 : folderIndex
        guard case var .folder(updatedFolder) = rootEntries[adjustedFolderIndex] else { return }
        guard !updatedFolder.apps.contains(where: { $0.id == app.id }) else { return }
        updatedFolder.apps.append(app)
        rootEntries[adjustedFolderIndex] = .folder(updatedFolder)
        statusMessage = "已将 \(app.name) 放入 \(updatedFolder.name)"
    }

    private func moveRootEntry(id: String, to targetIndex: Int) {
        guard let from = rootIndex(id: id) else { return }
        moveRootEntry(from: from, to: targetIndex)
    }

    private func moveRootEntry(from: Int, to targetIndex: Int) {
        guard rootEntries.indices.contains(from) else { return }

        let entry = rootEntries.remove(at: from)
        let clamped = max(0, min(targetIndex, rootEntries.count))
        let adjusted = from < clamped ? clamped - 1 : clamped
        rootEntries.insert(entry, at: max(0, min(adjusted, rootEntries.count)))
    }

    private func mutateFolder(id folderID: String, mutate: (inout FolderItem) -> Void) {
        guard let index = rootEntries.firstIndex(where: {
            guard case let .folder(folder) = $0 else { return false }
            return folder.id == folderID
        }) else {
            return
        }

        guard case var .folder(folder) = rootEntries[index] else { return }
        mutate(&folder)
        rootEntries[index] = .folder(folder)
    }

    private func defaultFolderName(first: AppItem, second: AppItem) -> String {
        let firstPrefix = first.name.split(separator: " ").first.map(String.init) ?? first.name
        let secondPrefix = second.name.split(separator: " ").first.map(String.init) ?? second.name
        if firstPrefix == secondPrefix {
            return firstPrefix
        }
        return "\(firstPrefix) 与 \(secondPrefix)"
    }

    private func rootIndex(id: String) -> Int? {
        rootEntries.firstIndex(where: { $0.id == id })
    }

    private func rootEntry(id: String) -> LauncherEntry? {
        rootEntries.first(where: { $0.id == id })
    }

    private func persistIfEntriesChanged(from previousFingerprint: UInt64) {
        let currentFingerprint = layoutFingerprint(of: rootEntries)
        guard previousFingerprint != currentFingerprint else { return }
        layoutMutationVersion &+= 1
        markSearchIndexDirty()
        scheduleLayoutPersist()
    }

    private func scheduleLayoutPersist(delayNanoseconds: UInt64 = 260_000_000) {
        guard !isPersistenceSuspended else { return }
        persistenceTask?.cancel()
        let expectedVersion = layoutMutationVersion
        persistenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            guard expectedVersion == self.layoutMutationVersion else { return }
            let snapshot = LauncherLayoutSnapshot(rootEntries: self.rootEntries)
            let fingerprint = self.layoutFingerprint(of: self.rootEntries)
            self.persistLayoutNow(snapshot: snapshot, fingerprint: fingerprint)
            self.persistenceTask = nil
        }
    }

    private func persistLayoutNow(
        snapshot: LauncherLayoutSnapshot? = nil,
        fingerprint: UInt64? = nil
    ) {
        guard !isPersistenceSuspended else { return }
        let target = snapshot ?? LauncherLayoutSnapshot(rootEntries: rootEntries)
        let targetFingerprint = fingerprint ?? layoutFingerprint(of: rootEntries)
        guard targetFingerprint != lastPersistedFingerprint else { return }

        persistenceSaveSequence &+= 1
        let saveSequence = persistenceSaveSequence
        persistenceWriteTask?.cancel()
        persistenceWriteTask = Task { @MainActor in
            do {
                try await layoutPersistence.saveAsync(target)
                guard !Task.isCancelled else { return }
                guard saveSequence == self.persistenceSaveSequence else { return }
                self.lastPersistedFingerprint = targetFingerprint
                self.lastError = nil
            } catch {
                guard !Task.isCancelled else { return }
                guard saveSequence == self.persistenceSaveSequence else { return }
                self.lastError = "保存布局失败：\(error.localizedDescription)"
            }

            if saveSequence == self.persistenceSaveSequence {
                self.persistenceWriteTask = nil
            }
        }
    }

    private func layoutFingerprint(of entries: [LauncherEntry]) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(entries.count)

        for entry in entries {
            switch entry {
            case let .app(app):
                hasher.combine(0)
                hasher.combine(app.id)
            case let .folder(folder):
                hasher.combine(1)
                hasher.combine(folder.id)
                hasher.combine(folder.name)
                hasher.combine(folder.apps.count)
                for app in folder.apps {
                    hasher.combine(app.id)
                }
            }
        }

        return UInt64(bitPattern: Int64(hasher.finalize()))
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
