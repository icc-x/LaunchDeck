import AppKit
import Combine

@MainActor
final class AppIconProvider {
    private struct IconJob {
        let id: String
        let path: String
    }

    private let cache = NSCache<NSString, NSImage>()
    private var iconLoadedSubjects: [String: CurrentValueSubject<Int, Never>] = [:]
    private let iconSize = NSSize(width: 72, height: 72)
    private var pendingJobs: [IconJob] = []
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
        let uniqueIDs = Array(Set(appIDs))
        guard !uniqueIDs.isEmpty else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        let publishers = uniqueIDs.map {
            subject(for: $0)
                .map { _ in () }
                .eraseToAnyPublisher()
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
            guard !pendingJobs.isEmpty else {
                loadingTask = nil
                return
            }

            let job = pendingJobs.removeFirst()
            pendingIDs.remove(job.id)

            let key = job.id as NSString
            if cache.object(forKey: key) != nil {
                continue
            }

            let image = NSWorkspace.shared.icon(forFile: job.path)
            image.size = iconSize
            cache.setObject(image, forKey: key)
            let subject = subject(for: job.id)
            subject.value += 1
            await Task.yield()
        }

        loadingTask = nil
    }

    private func subject(for appID: String) -> CurrentValueSubject<Int, Never> {
        if let existing = iconLoadedSubjects[appID] {
            return existing
        }
        let created = CurrentValueSubject<Int, Never>(0)
        iconLoadedSubjects[appID] = created
        return created
    }
}
