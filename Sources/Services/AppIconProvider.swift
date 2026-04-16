import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppIconProvider {
    private struct IconJob {
        let id: String
        let path: String
    }

    private enum LoadReason {
        case demand
        case prefetch
    }

    private struct PreparedIcon {
        let image: NSImage
        let cost: Int
    }

    private struct RasterizedIconPayload: Sendable {
        let pngData: Data
        let cost: Int
    }

    private enum CachePolicy {
        static let countLimit = 160
        static let totalCostLimit = 24 * 1024 * 1024
        static let bytesPerPixel = 4
        static let fallbackBackingScaleFactor: CGFloat = 2
    }

    private let cache = NSCache<NSString, NSImage>()
    private var iconLoadedSubjects: [String: PassthroughSubject<Void, Never>] = [:]
    private let iconSize: NSSize
    private let backingScaleFactor: CGFloat
    private var pendingJobs: [IconJob] = []
    private var nextPendingJobIndex = 0
    private var pendingReasons: [String: LoadReason] = [:]
    private var cachedIDs = Set<String>()
    private var workingSetIDs = Set<String>()
    private var loadingTask: Task<Void, Never>?

    private lazy var placeholderIcon: NSImage = {
        makePlaceholderIcon()
    }()

    init(iconSize: NSSize = NSSize(width: 72, height: 72)) {
        self.iconSize = iconSize
        backingScaleFactor = max(Self.maximumBackingScaleFactor(), CachePolicy.fallbackBackingScaleFactor)
        cache.countLimit = CachePolicy.countLimit
        cache.totalCostLimit = CachePolicy.totalCostLimit
    }

    deinit {
        loadingTask?.cancel()
    }

    func icon(for app: AppItem) -> NSImage {
        let key = app.id as NSString
        if let image = cache.object(forKey: key) {
            return image
        }

        enqueue(app, reason: .demand)
        return placeholderIcon
    }

    func prefetch(_ apps: [AppItem]) {
        workingSetIDs = Set(apps.map(\.id))
        trimCache(keeping: workingSetIDs)

        for app in apps {
            enqueue(app, reason: .prefetch)
        }
    }

    func clearCache() {
        loadingTask?.cancel()
        loadingTask = nil
        cache.removeAllObjects()
        pendingJobs.removeAll(keepingCapacity: false)
        nextPendingJobIndex = 0
        pendingReasons.removeAll(keepingCapacity: false)
        cachedIDs.removeAll(keepingCapacity: false)
        workingSetIDs.removeAll(keepingCapacity: false)
    }

    func iconLoadedPublisher(for appIDs: [String]) -> AnyPublisher<Void, Never> {
        let uniqueIDs = Array(Set(appIDs)).sorted()
        guard !uniqueIDs.isEmpty else {
            return Empty(completeImmediately: true).eraseToAnyPublisher()
        }

        let publishers = uniqueIDs.compactMap { appID -> AnyPublisher<Void, Never>? in
            if cache.object(forKey: appID as NSString) != nil {
                return nil
            }

            return subject(for: appID)
                .map { _ in () }
                .eraseToAnyPublisher()
        }

        guard !publishers.isEmpty else {
            return Empty(completeImmediately: true).eraseToAnyPublisher()
        }

        return Publishers.MergeMany(publishers).eraseToAnyPublisher()
    }

    private func enqueue(_ app: AppItem, reason: LoadReason) {
        let key = app.id as NSString
        guard cache.object(forKey: key) == nil else { return }

        if let existingReason = pendingReasons[app.id] {
            if existingReason == .prefetch, reason == .demand {
                pendingReasons[app.id] = .demand
            }
            return
        }

        pendingReasons[app.id] = reason
        pendingJobs.append(.init(id: app.id, path: app.url.path))
        startLoaderIfNeeded()
    }

    private func startLoaderIfNeeded() {
        guard loadingTask == nil else { return }
        loadingTask = Task { [weak self] in
            await self?.runLoaderLoop()
        }
    }

    private func runLoaderLoop() async {
        while !Task.isCancelled {
            guard let job = dequeueJob() else {
                loadingTask = nil
                return
            }

            let key = job.id as NSString
            if cache.object(forKey: key) != nil {
                continue
            }

            if job.reason == .prefetch, !workingSetIDs.contains(job.id) {
                continue
            }

            let iconSize = self.iconSize
            let backingScaleFactor = self.backingScaleFactor
            let preparedIcon: PreparedIcon
            if let payload = await Self.rasterizedIconPayload(
                forBundleAtPath: job.path,
                iconSize: iconSize,
                backingScaleFactor: backingScaleFactor
            ) {
                preparedIcon = makePreparedIcon(from: payload, iconSize: iconSize)
            } else {
                preparedIcon = makeWorkspacePreparedIcon(forFileAtPath: job.path)
            }
            cache.setObject(preparedIcon.image, forKey: key, cost: preparedIcon.cost)
            cachedIDs.insert(job.id)
            if let subject = iconLoadedSubjects.removeValue(forKey: job.id) {
                subject.send(())
                subject.send(completion: .finished)
            }
            await Task.yield()
        }

        loadingTask = nil
    }

    private func dequeueJob() -> (id: String, path: String, reason: LoadReason)? {
        guard nextPendingJobIndex < pendingJobs.count else {
            pendingJobs.removeAll(keepingCapacity: true)
            nextPendingJobIndex = 0
            return nil
        }

        let job = pendingJobs[nextPendingJobIndex]
        nextPendingJobIndex += 1
        let reason = pendingReasons.removeValue(forKey: job.id) ?? .prefetch

        if nextPendingJobIndex >= 64, nextPendingJobIndex * 2 >= pendingJobs.count {
            pendingJobs.removeFirst(nextPendingJobIndex)
            nextPendingJobIndex = 0
        }

        return (job.id, job.path, reason)
    }

    private func subject(for appID: String) -> PassthroughSubject<Void, Never> {
        if let existing = iconLoadedSubjects[appID] {
            return existing
        }
        let created = PassthroughSubject<Void, Never>()
        iconLoadedSubjects[appID] = created
        return created
    }

    private func makePreparedIcon(from payload: RasterizedIconPayload, iconSize: NSSize) -> PreparedIcon {
        if let image = NSImage(data: payload.pngData) {
            image.size = iconSize
            return PreparedIcon(image: image, cost: payload.cost)
        }

        return PreparedIcon(image: placeholderIcon, cost: payload.cost)
    }

    private func makeWorkspacePreparedIcon(forFileAtPath path: String) -> PreparedIcon {
        Self.makeWorkspacePreparedIcon(
            forFileAtPath: path,
            iconSize: iconSize,
            backingScaleFactor: backingScaleFactor
        )
    }

    nonisolated private static func rasterizedIconPayload(
        forBundleAtPath path: String,
        iconSize: NSSize,
        backingScaleFactor: CGFloat
    ) async -> RasterizedIconPayload? {
        await Task.detached(priority: .utility) {
            autoreleasepool {
                guard let iconURL = resolveIconFileURL(forBundleAtPath: path) else {
                    return nil
                }
                return rasterizeIconPayload(
                    from: iconURL,
                    iconSize: iconSize,
                    backingScaleFactor: backingScaleFactor
                )
            }
        }.value
    }

    nonisolated private static func makeWorkspacePreparedIcon(
        forFileAtPath path: String,
        iconSize: NSSize,
        backingScaleFactor: CGFloat
    ) -> PreparedIcon {
        let sourceImage = NSWorkspace.shared.icon(forFile: path)
        let pixelWidth = max(1, Int((iconSize.width * backingScaleFactor).rounded(.up)))
        let pixelHeight = max(1, Int((iconSize.height * backingScaleFactor).rounded(.up)))
        let cost = pixelWidth * pixelHeight * CachePolicy.bytesPerPixel

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            sourceImage.size = iconSize
            return PreparedIcon(image: sourceImage, cost: cost)
        }

        representation.size = iconSize

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: representation) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            sourceImage.draw(
                in: NSRect(origin: .zero, size: iconSize),
                from: NSRect(origin: .zero, size: sourceImage.size),
                operation: .copy,
                fraction: 1
            )
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let rasterizedImage = NSImage(size: iconSize)
        rasterizedImage.addRepresentation(representation)
        return PreparedIcon(image: rasterizedImage, cost: cost)
    }

    nonisolated private static func resolveIconFileURL(forBundleAtPath path: String) -> URL? {
        let bundleURL = URL(fileURLWithPath: path, isDirectory: true)
        let infoPlistURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)

        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }

        let resourcesURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)

        var candidateNames: [String] = []
        if let iconFile = dictionary["CFBundleIconFile"] as? String {
            candidateNames.append(iconFile)
        }
        if let iconName = dictionary["CFBundleIconName"] as? String {
            candidateNames.append(iconName)
        }
        candidateNames.append("AppIcon")

        for candidate in candidateNames {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let baseURL = resourcesURL.appendingPathComponent(trimmed, isDirectory: false)
            if FileManager.default.fileExists(atPath: baseURL.path) {
                return baseURL
            }

            if baseURL.pathExtension.isEmpty {
                let icnsURL = baseURL.appendingPathExtension("icns")
                if FileManager.default.fileExists(atPath: icnsURL.path) {
                    return icnsURL
                }
            }
        }

        return nil
    }

    nonisolated private static func rasterizeIconPayload(
        from iconURL: URL,
        iconSize: NSSize,
        backingScaleFactor: CGFloat
    ) -> RasterizedIconPayload? {
        let pixelWidth = max(1, Int((iconSize.width * backingScaleFactor).rounded(.up)))
        let pixelHeight = max(1, Int((iconSize.height * backingScaleFactor).rounded(.up)))
        let maxPixelSize = max(pixelWidth, pixelHeight)
        let cost = pixelWidth * pixelHeight * CachePolicy.bytesPerPixel

        guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let destinationData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            destinationData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return RasterizedIconPayload(
            pngData: destinationData as Data,
            cost: cost
        )
    }

    private func makePlaceholderIcon() -> NSImage {
        let outerInset = min(iconSize.width, iconSize.height) * 0.08
        let innerInset = min(iconSize.width, iconSize.height) * 0.24
        let cornerRadius = min(iconSize.width, iconSize.height) * 0.18
        let image = NSImage(size: iconSize, flipped: false) { [iconSize] rect in
            NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: outerInset, dy: outerInset),
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).fill()

            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            NSBezierPath(
                roundedRect: rect.insetBy(dx: innerInset, dy: innerInset),
                xRadius: max(2, cornerRadius * 0.56),
                yRadius: max(2, cornerRadius * 0.56)
            ).fill()

            NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
            let highlightRect = NSRect(
                x: outerInset + max(1, iconSize.width * 0.08),
                y: rect.maxY - outerInset - max(2, iconSize.height * 0.22),
                width: max(2, rect.width - (outerInset * 2 + iconSize.width * 0.16)),
                height: max(1.5, iconSize.height * 0.08)
            )
            let highlight = NSBezierPath(
                roundedRect: highlightRect,
                xRadius: highlightRect.height * 0.5,
                yRadius: highlightRect.height * 0.5
            )
            highlight.lineWidth = 1
            highlight.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    nonisolated private static func maximumBackingScaleFactor() -> CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? CachePolicy.fallbackBackingScaleFactor
    }

    private func trimCache(keeping idsToKeep: Set<String>) {
        let staleIDs = cachedIDs.subtracting(idsToKeep)
        guard !staleIDs.isEmpty else { return }

        for id in staleIDs {
            cache.removeObject(forKey: id as NSString)
            cachedIDs.remove(id)
        }
    }
}
