import CoreGraphics
import Foundation
import os

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var rootEntries: [LauncherEntry] = []
    @Published private(set) var pages: [ArraySlice<LauncherEntry>] = []
    @Published var query = "" {
        didSet {
            guard !isManagingQueryManually else { return }
            scheduleFilter()
            scheduleSessionPersist()
        }
    }
    @Published var currentPage = 0 {
        didSet {
            guard currentPage != oldValue else { return }
            scheduleSessionPersist()
        }
    }
    @Published private(set) var pageTransitionDirection = 1
    @Published private(set) var isEditing = false
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage = LaunchDeckStrings.scanningStatus()
    @Published var lastError: String?
    @Published private(set) var activeFolder: FolderItem? {
        didSet {
            guard activeFolder?.id != oldValue?.id else { return }
            scheduleSessionPersist()
        }
    }
    @Published private(set) var draggingEntryID: String?
    @Published private(set) var draggingFolderAppID: String?

    private let appLauncher: AppLaunchClient
    private let catalogClient: LauncherCatalogClient
    private let layoutPersistence: LauncherLayoutPersistence
    private let sessionPersistence: LauncherSessionPersistence
    private let diagnosticsService: LauncherDiagnosticsService
    private let preferences: LauncherPreferences
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Store")

    private var allAppsCount = 0
    private var catalogAppIDs: [String] = []
    private var pageSize = 35
    private var filteredEntries: [LauncherEntry] = []
    private var filteredResultsCount = 0
    private var searchIndex = LauncherSearchIndex()
    private var draggingFolderID: String?
    private var edgeHoverDirection: Int?
    private var edgeHoverStartedAt = Date.distantPast
    private var lastEdgeFlipAt = Date.distantPast
    private var dragAutoClearToken = UUID()
    private var persistenceTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var metadataEnrichmentTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var layoutMutationVersion: UInt64 = 0
    private var lastPersistedFingerprint: UInt64?
    private var isPersistenceSuspended = false
    private var hasLoadedCatalog = false
    private var isManagingQueryManually = false
    private var restoredSession: LauncherSessionSnapshot?

    init(
        preferences: LauncherPreferences,
        layoutPersistence: LauncherLayoutPersistence = LauncherLayoutPersistence(),
        sessionPersistence: LauncherSessionPersistence = LauncherSessionPersistence(),
        diagnosticsService: LauncherDiagnosticsService = LauncherDiagnosticsService(),
        catalogClient: LauncherCatalogClient = .live,
        appLauncher: AppLaunchClient = .live,
        autoReload: Bool = true
    ) {
        self.preferences = preferences
        self.layoutPersistence = layoutPersistence
        self.sessionPersistence = sessionPersistence
        self.diagnosticsService = diagnosticsService
        self.catalogClient = catalogClient
        self.appLauncher = appLauncher
        restoredSession = preferences.restoreLastSession ? sessionPersistence.load() : nil

        if autoReload {
            Task { await reload() }
        }
    }

    var footerDetailText: String? {
        var components: [String] = []

        if pages.count > 1 {
            components.append(
                LaunchDeckStrings.pagePosition(
                    current: currentPage + 1,
                    total: pages.count
                )
            )
        }

        if !queryKeyword.isEmpty {
            components.append(LaunchDeckStrings.resultsCount(filteredResultsCount))
        }

        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    var layoutStoragePath: String {
        layoutPersistence.storagePath
    }

    var sessionStoragePath: String {
        sessionPersistence.storagePath
    }

    func reload() async {
        let reloadStart = DispatchTime.now()
        await flushPendingPersistence()
        cancelTransientTasks()
        isPersistenceSuspended = false
        isLoading = true
        lastError = nil
        statusMessage = LaunchDeckStrings.scanningStatus()
        lastPersistedFingerprint = nil

        let persistedLayout = await loadPersistedLayout()
        let loaded = await Task.detached(priority: .userInitiated) { [catalogClient] in
            catalogClient.loadApplications()
        }.value

        allAppsCount = loaded.count
        catalogAppIDs = loaded.map(\.id)
        rootEntries = LauncherLayoutMerger.merge(apps: loaded, persisted: persistedLayout)
        hasLoadedCatalog = true
        layoutMutationVersion &+= 1
        searchIndex.markDirty()
        activeFolder = nil
        clearDragging()
        statusMessage = defaultStatusMessage()
        isLoading = false
        applyFilter(resetPage: true)
        restoreSessionIfNeeded()

        if !isPersistenceSuspended {
            await persistCurrentLayoutIfNeeded()
        }
        scheduleSessionPersist()
        startMetadataEnrichmentIfNeeded(initialApps: loaded)

        let elapsedMs = DispatchTime.now().uptimeNanoseconds - reloadStart.uptimeNanoseconds
        logger.info(
            "store.reload.fast count=\(loaded.count, privacy: .public) elapsed_ms=\(Double(elapsedMs) / 1_000_000, privacy: .public)"
        )
    }

    func flushPendingPersistence() async {
        guard hasLoadedCatalog else { return }
        persistenceTask?.cancel()
        persistenceTask = nil
        sessionTask?.cancel()
        sessionTask = nil

        if !isPersistenceSuspended {
            await persistCurrentLayoutIfNeeded()
        }
        await persistCurrentSessionIfNeeded()
    }

    func exportDiagnostics() async {
        let report = diagnosticsService.makeReport(
            preferences: preferences.snapshot,
            restoredSession: restoredSession,
            layoutPath: layoutStoragePath,
            sessionPath: sessionStoragePath,
            allAppsCount: allAppsCount,
            rootEntries: rootEntries,
            query: query,
            currentPage: currentPage,
            pagesCount: pages.count,
            activeFolder: activeFolder,
            isEditing: isEditing,
            isLoading: isLoading,
            lastError: lastError,
            statusMessage: statusMessage
        )

        do {
            _ = try await diagnosticsService.export(report: report)
            publishActionStatus(LaunchDeckStrings.diagnosticsExported)
        } catch let error as LauncherDiagnosticsError {
            switch error {
            case .cancelled:
                publishActionStatus(LaunchDeckStrings.diagnosticsExportCancelled)
            }
        } catch {
            lastError = LaunchDeckStrings.diagnosticsExportFailed(error.localizedDescription)
        }
    }

    func clearRestoredSession() async {
        sessionTask?.cancel()
        sessionTask = nil
        restoredSession = nil
        do {
            try await sessionPersistence.deleteAsync()
            publishActionStatus(LaunchDeckStrings.sessionCleared)
            logger.info("store.session.cleared")
        } catch {
            logger.error("store.session.clear_failed error=\(error.localizedDescription, privacy: .public)")
            lastError = LaunchDeckStrings.sessionClearFailed(error.localizedDescription)
        }
    }

    func handleRestoreLastSessionPreferenceChange() async {
        if preferences.restoreLastSession {
            restoredSession = sessionPersistence.load()
            restoreSessionIfNeeded()
            scheduleSessionPersist()
        } else {
            await clearRestoredSession()
        }
    }

    func notePreferencesReset() {
        publishActionStatus(LaunchDeckStrings.preferencesReset)
    }

    func launch(_ app: AppItem) {
        publishStatus(LaunchDeckStrings.openingApp(app.name))
        appLauncher.launch(app) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = error
                    self.statusMessage = LaunchDeckStrings.openAppFailed(app.name)
                } else {
                    self.publishActionStatus(LaunchDeckStrings.openedApp(app.name))
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
            publishActionStatus(LaunchDeckStrings.editingStatus())
        }
    }

    func exitEditMode() {
        guard isEditing else { return }
        isEditing = false
        clearDragging()
        publishActionStatus(activeFolder.map { LaunchDeckStrings.folderOpened($0.name) } ?? defaultStatusMessage())
    }

    func openFolder(_ folder: FolderItem) {
        guard queryKeyword.isEmpty else { return }
        activeFolder = folder
        publishActionStatus(LaunchDeckStrings.folderOpened(folder.name))
    }

    func closeFolder() {
        activeFolder = nil
        if queryKeyword.isEmpty {
            publishActionStatus(defaultStatusMessage())
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
                    publishActionStatus(LaunchDeckStrings.groupedIntoFolder(draggedName, folderName: groupedFolder.name))
                } else {
                    publishActionStatus(LaunchDeckStrings.createdFolder(groupedFolder.name))
                }
            } else {
                publishActionStatus(LaunchDeckStrings.rootReordered())
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
        publishActionStatus(LaunchDeckStrings.folderRenamed(renamedFolder?.name ?? trimmed))
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
                publishActionStatus(LaunchDeckStrings.folderReordered(updatedFolder.name))
            }
        }
        clearDragging()
    }

    func handleFolderDropToEnd(folderID: String) {
        handleFolderDropToPageBoundary(folderID: folderID, currentPage: nil, direction: 1, pageSize: preferences.folderPageSize)
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
                publishActionStatus(LaunchDeckStrings.folderCrossPageMoved(updatedFolder.name))
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
            publishActionStatus(LaunchDeckStrings.folderExtracted(extractedApp?.name ?? LaunchDeckStrings.fallbackAppName))
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
            publishActionStatus(LaunchDeckStrings.rootMovedToPageBoundary(direction: direction))
        }
        clearDragging()
        applyFilter()
    }

    private func cancelTransientTasks() {
        persistenceTask?.cancel()
        persistenceTask = nil
        filterTask?.cancel()
        filterTask = nil
        metadataEnrichmentTask?.cancel()
        metadataEnrichmentTask = nil
        sessionTask?.cancel()
        sessionTask = nil
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
                lastError = LaunchDeckStrings.persistenceIncompatible(version: version, backupPath: backupPath)
            }
            return nil
        } catch {
            lastError = LaunchDeckStrings.persistenceCorrupted()
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
            guard self.catalogAppIDs == initialApps.map(\.id) else { return }
            guard initialApps != enriched else { return }

            self.applyMetadataUpdate(enriched)
        }
    }

    private func applyMetadataUpdate(_ apps: [AppItem]) {
        let appByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })

        allAppsCount = apps.count
        catalogAppIDs = apps.map(\.id)
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

    private func restoreSessionIfNeeded() {
        guard preferences.restoreLastSession, let restoredSession else { return }
        guard !isLoading else { return }
        let previousQuery = query
        let previousPage = currentPage
        let previousActiveFolderID = activeFolder?.id

        setQuery(restoredSession.query, resetPage: true, immediate: true)
        if !pages.isEmpty {
            currentPage = min(restoredSession.currentPage, pages.count - 1)
        }
        if queryKeyword.isEmpty, let folderID = restoredSession.activeFolderID {
            activeFolder = layoutEditor().currentFolder(id: folderID)
            if let activeFolder {
                publishActionStatus(LaunchDeckStrings.folderOpened(activeFolder.name))
            }
        }

        if activeFolder == nil,
           previousQuery != query || previousPage != currentPage || previousActiveFolderID != activeFolder?.id {
            publishActionStatus(LaunchDeckStrings.sessionRestored)
        }
        logger.info("store.session.restore page=\(self.currentPage, privacy: .public)")
    }

    private func setQuery(_ value: String, resetPage: Bool, immediate: Bool) {
        isManagingQueryManually = true
        query = value
        isManagingQueryManually = false

        if immediate {
            applyFilter(resetPage: resetPage)
            scheduleSessionPersist()
        } else {
            scheduleFilter(resetPage: resetPage)
        }
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
            filteredResultsCount = 0
            if !filteredEntries.isEmpty {
                filteredEntries.removeAll(keepingCapacity: true)
            }
            pages = LauncherPaging.chunked(rootEntries, pageSize: pageSize)
        } else {
            filteredEntries = searchIndex.filter(entries: rootEntries, keyword: keyword)
            filteredResultsCount = filteredEntries.count
            pages = LauncherPaging.chunked(filteredEntries, pageSize: pageSize)

            if isEditing {
                isEditing = false
            }
            if activeFolder != nil {
                activeFolder = nil
            }
        }
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
            logger.info(
                "store.filter keyword_len=\(keyword.count, privacy: .public) result=\(self.filteredResultsCount, privacy: .public) elapsed_ms=\(Double(elapsedMs) / 1_000_000, privacy: .public)"
            )
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
        rootEntries.isEmpty ? LaunchDeckStrings.noAppsStatus() : LaunchDeckStrings.appCount(allAppsCount)
    }

    private func publishStatus(_ message: String, clearingError: Bool = false) {
        statusMessage = message
        if clearingError {
            lastError = nil
        }
    }

    private func publishActionStatus(_ message: String) {
        publishStatus(message, clearingError: true)
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
        await persistLayout(snapshot: snapshot, fingerprint: fingerprint)
        if expectedVersion == layoutMutationVersion {
            persistenceTask = nil
        }
    }

    private func persistCurrentLayoutIfNeeded() async {
        let snapshot = LauncherLayoutSnapshot(rootEntries: rootEntries)
        let fingerprint = LauncherLayoutEditor.layoutFingerprint(of: rootEntries)
        await persistLayout(snapshot: snapshot, fingerprint: fingerprint)
    }

    private func persistLayout(snapshot: LauncherLayoutSnapshot, fingerprint: UInt64) async {
        guard !isPersistenceSuspended else { return }
        guard fingerprint != lastPersistedFingerprint else { return }

        do {
            try await layoutPersistence.saveAsync(snapshot)
            lastPersistedFingerprint = fingerprint
            lastError = nil
        } catch {
            logger.error("store.layout.save_failed error=\(error.localizedDescription, privacy: .public)")
            lastError = LaunchDeckStrings.persistenceSaveFailed(error.localizedDescription)
        }
    }

    private func scheduleSessionPersist(delayNanoseconds: UInt64 = 180_000_000) {
        guard preferences.restoreLastSession, hasLoadedCatalog else { return }
        sessionTask?.cancel()
        let snapshot = makeSessionSnapshot()

        sessionTask = Task { [weak self, snapshot] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.persistSession(snapshot)
        }
    }

    private func persistCurrentSessionIfNeeded() async {
        guard preferences.restoreLastSession, hasLoadedCatalog else { return }
        await persistSession(makeSessionSnapshot())
    }

    private func persistSession(_ snapshot: LauncherSessionSnapshot) async {
        do {
            try await sessionPersistence.saveAsync(snapshot)
            restoredSession = snapshot
            lastError = nil
        } catch {
            logger.error("store.session.save_failed error=\(error.localizedDescription, privacy: .public)")
            lastError = LaunchDeckStrings.sessionSaveFailed(error.localizedDescription)
        }
    }

    private func makeSessionSnapshot() -> LauncherSessionSnapshot {
        LauncherSessionSnapshot(
            query: query,
            currentPage: currentPage,
            activeFolderID: queryKeyword.isEmpty ? activeFolder?.id : nil,
            updatedAt: Date()
        )
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
