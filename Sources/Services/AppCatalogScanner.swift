import Foundation

struct AppCatalogScanner {
    private let fileManager: FileManager
    private let roots: [URL]

    init(fileManager: FileManager = .default, roots: [URL]) {
        self.fileManager = fileManager
        self.roots = roots
    }

    func scan() -> [URL] {
        var selectedByPath: [String: AppCatalogCandidate] = [:]

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isPackageKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "app" else {
                    continue
                }

                let resolvedPath = fileURL.resolvingSymlinksInPath().path
                let candidate = AppCatalogCandidate(url: fileURL, priority: pathPriority(fileURL.path))

                if let existing = selectedByPath[resolvedPath] {
                    if candidate.priority > existing.priority {
                        selectedByPath[resolvedPath] = candidate
                    }
                } else {
                    selectedByPath[resolvedPath] = candidate
                }
            }
        }

        return selectedByPath.values
            .sorted(by: AppCatalogCandidate.sort)
            .map(\.url)
    }

    private func pathPriority(_ path: String) -> Int {
        if path.hasPrefix("/System/Applications") { return 3 }
        if path.hasPrefix("/Applications") { return 2 }
        if path.hasPrefix(NSHomeDirectory()) { return 1 }
        return 0
    }
}

private struct AppCatalogCandidate {
    let url: URL
    let priority: Int

    static func sort(lhs: AppCatalogCandidate, rhs: AppCatalogCandidate) -> Bool {
        let lhsName = lhs.url.deletingPathExtension().lastPathComponent
        let rhsName = rhs.url.deletingPathExtension().lastPathComponent
        let nameComparison = lhsName.localizedCaseInsensitiveCompare(rhsName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }

        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
    }
}
