import AppKit
import Combine

@MainActor
final class AppIconProvider {
    private struct IconJob {
        let id: String
        let path: String
    }

    private let cache = NSCache<NSString, NSImage>()
    private var iconLoadedSubjects: [String: PassthroughSubject<Void, Never>] = [:]
    private let iconSize = NSSize(width: 72, height: 72)
    private var pendingJobs: [IconJob] = []
    private var nextPendingJobIndex = 0
    private var pendingIDs = Set<String>()
    private var loadingTask: Task<Void, Never>?

    private lazy var placeholderIcon: NSImage = {
        if let image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil) {
            image.size = iconSize
            return image
        }
        return NSImage(size: iconSize)
    }()

    init() {
        cache.countLimit = 720
    }

    deinit {
        loadingTask?.cancel()
    }

    func icon(for app: AppItem) -> NSImage {
        let key = app.id as NSString
        if let image = cache.object(forKey: key) {
            return image
        }

        enqueue(app)
        return placeholderIcon
    }

    func prefetch(_ apps: [AppItem]) {
        for app in apps {
            enqueue(app)
        }
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

    private func enqueue(_ app: AppItem) {
        let key = app.id as NSString
        guard cache.object(forKey: key) == nil else { return }
        guard pendingIDs.insert(app.id).inserted else { return }

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

            let image = NSWorkspace.shared.icon(forFile: job.path)
            image.size = iconSize
            cache.setObject(image, forKey: key)
            if let subject = iconLoadedSubjects.removeValue(forKey: job.id) {
                subject.send(())
                subject.send(completion: .finished)
            }
            await Task.yield()
        }

        loadingTask = nil
    }

    private func dequeueJob() -> IconJob? {
        guard nextPendingJobIndex < pendingJobs.count else {
            pendingJobs.removeAll(keepingCapacity: true)
            nextPendingJobIndex = 0
            return nil
        }

        let job = pendingJobs[nextPendingJobIndex]
        nextPendingJobIndex += 1
        pendingIDs.remove(job.id)

        if nextPendingJobIndex >= 64, nextPendingJobIndex * 2 >= pendingJobs.count {
            pendingJobs.removeFirst(nextPendingJobIndex)
            nextPendingJobIndex = 0
        }

        return job
    }

    private func subject(for appID: String) -> PassthroughSubject<Void, Never> {
        if let existing = iconLoadedSubjects[appID] {
            return existing
        }
        let created = PassthroughSubject<Void, Never>()
        iconLoadedSubjects[appID] = created
        return created
    }
}
