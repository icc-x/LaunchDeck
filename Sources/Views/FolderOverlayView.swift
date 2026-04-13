import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct FolderOverlayView: View {
    let folder: FolderItem
    let apps: [AppItem]
    let isEditing: Bool
    let isDraggingFolderApp: Bool
    let iconProvider: AppIconProvider
    let namespace: Namespace.ID
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onLaunch: (AppItem) -> Void
    let onBeginDragging: (AppItem) -> Void
    let onEnterEditMode: () -> Void
    let onDropOnApp: (AppItem) -> Void
    let onDropToFolderPageBoundary: (Int, Int, Int) -> Void
    let onDropToFolderEnd: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var editingName = ""
    @FocusState private var isNameFocused: Bool
    @State private var currentPage = 0
    @State private var edgeHoverDirection: Int?
    @State private var edgeHoverStartedAt = Date.distantPast
    @State private var lastEdgeFlipAt = Date.distantPast
    @State private var lastWheelFlipAt = Date.distantPast
    @State private var pagedAppsCache: [[AppItem]] = []
    @State private var folderBadgeReloadToken = 0
    @State private var folderBadgeSubscription: AnyCancellable?
    @State private var subscribedFolderBadgeKey = ""

    private let folderPageSize = 18
    private let folderSpacingScale: CGFloat = 0.5

    private var theme: LaunchTheme {
        LaunchTheme(colorScheme: colorScheme)
    }

    private var visibleApps: [AppItem] {
        guard pagedAppsCache.indices.contains(currentPage) else { return [] }
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
                    TextField("文件夹名称", text: $editingName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .onSubmit { commitRename() }
                        .onChange(of: folder.name) { _, newValue in
                            editingName = newValue
                        }
                        .frame(maxWidth: 280, alignment: .leading)

                    Text("\(apps.count) 个应用")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    isNameFocused = true
                } label: {
                    Label("重命名", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(theme.controlSubtleForeground)
                }
                .buttonStyle(.plain)
                .help("重命名文件夹")

                Button {
                    onClose()
                } label: {
                    Label("关闭", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(theme.controlSubtleForeground)
                }
                .buttonStyle(.plain)
                .help("关闭文件夹")
            }

            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104, maximum: 104), spacing: 11 * folderSpacingScale)],
                        spacing: 12 * folderSpacingScale
                    ) {
                        ForEach(visibleApps) { app in
                            FolderAppButton(
                                app: app,
                                isEditing: isEditing,
                                iconProvider: iconProvider,
                                action: { onLaunch(app) },
                                onBeginDragging: { onBeginDragging(app) },
                                onEnterEditMode: onEnterEditMode,
                                onDropOnApp: { onDropOnApp(app) }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                    .onDrop(of: [UTType.text], delegate: FolderPageDropDelegate {
                        if pagedAppsCache.isEmpty {
                            onDropToFolderEnd()
                        } else {
                            onDropToFolderPageBoundary(currentPage, 1, folderPageSize)
                        }
                    })
                }
                .overlay {
                    if pagedAppsCache.count > 1 {
                        ScrollWheelCaptureView { event in
                            handleFolderWheelPaging(event)
                        }
                        .allowsHitTesting(false)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
    }

    private var folderBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 3), count: 2), spacing: 3) {
                ForEach(Array(apps.prefix(4).enumerated()), id: \.offset) { _, app in
                    Image(nsImage: iconProvider.icon(for: app))
                        .resizable()
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

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let threshold: CGFloat = 3.0

        if abs(deltaY) >= abs(deltaX), abs(deltaY) > threshold {
            if deltaY < 0, currentPage < pagedAppsCache.count - 1 {
                withAnimation(LaunchMotion.page) {
                    currentPage += 1
                }
                lastWheelFlipAt = now
                return true
            }
            if deltaY > 0, currentPage > 0 {
                withAnimation(LaunchMotion.page) {
                    currentPage -= 1
                }
                lastWheelFlipAt = now
                return true
            }
            return false
        }

        if abs(deltaX) > threshold {
            if deltaX > 0, currentPage > 0 {
                withAnimation(LaunchMotion.page) {
                    currentPage -= 1
                }
                lastWheelFlipAt = now
                return true
            }
            if deltaX < 0, currentPage < pagedAppsCache.count - 1 {
                withAnimation(LaunchMotion.page) {
                    currentPage += 1
                }
                lastWheelFlipAt = now
                return true
            }
        }

        return false
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
        pagedAppsCache = chunked(apps, chunkSize: folderPageSize)
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

        folderBadgeSubscription = iconProvider.iconLoadedPublisher(for: folderBadgeIconIDs).sink { _ in
            folderBadgeReloadToken &+= 1
        }

        folderBadgeReloadToken &+= 1
    }

    private func chunked(_ items: [AppItem], chunkSize: Int) -> [[AppItem]] {
        guard !items.isEmpty else { return [] }
        guard chunkSize > 0 else { return [items] }

        var chunks: [[AppItem]] = []
        var index = 0

        while index < items.count {
            let end = min(index + chunkSize, items.count)
            chunks.append(Array(items[index..<end]))
            index = end
        }

        return chunks
    }
}

private struct FolderAppButton: View {
    let app: AppItem
    let isEditing: Bool
    let iconProvider: AppIconProvider
    let action: () -> Void
    let onBeginDragging: () -> Void
    let onEnterEditMode: () -> Void
    let onDropOnApp: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false
    @State private var isDropTargeted = false
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
                .frame(width: 70, height: 70)

            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 96)
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(LaunchMotion.hover, value: isHovering)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDropTargeted ? theme.dropStroke : .clear, lineWidth: 1)
                .padding(.top, 4)
        )
        .animation(LaunchMotion.quickFade, value: isDropTargeted)
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
        .onTapGesture(perform: action)
        .onDrag {
            onBeginDragging()
            return NSItemProvider(object: "folder:\(app.id)" as NSString)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.42).onEnded { _ in
                onEnterEditMode()
            }
        )
        .onDrop(of: [UTType.text], delegate: FolderAppDropDelegate(
            isDropTargeted: $isDropTargeted,
            onDropOnApp: onDropOnApp
        ))
        .conditionalModifier(isEditing) { view in
            view.modifier(WiggleModifier(isActive: true, seed: app.id))
        }
    }
}

private struct FolderPageDropDelegate: DropDelegate {
    let onDropToPageEnd: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        onDropToPageEnd()
        return true
    }
}

private struct FolderAppDropDelegate: DropDelegate {
    @Binding var isDropTargeted: Bool
    let onDropOnApp: () -> Void

    func dropEntered(info: DropInfo) {
        isDropTargeted = true
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false
        onDropOnApp()
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
