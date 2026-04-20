import Foundation
import os

struct AppCatalogService {
    private let fileManager = FileManager.default
    private let cacheStore = AppCatalogMetadataCacheStore()
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Catalog")

    func loadApplications() -> [AppItem] {
        let start = DispatchTime.now()
        let candidates = AppCatalogScanner(
            fileManager: fileManager,
            roots: candidateRoots()
        ).scan()
        let localeSignature = Self.localeSignature
        let cache = cacheStore.load(localeSignature: localeSignature)

        var apps: [AppItem] = []
        apps.reserveCapacity(candidates.count)

        for appURL in candidates {
            let cacheKey = appURL.resolvingSymlinksInPath().path
            let stamp = fileStamp(for: appURL)

            if let entry = cache.entries[cacheKey], entry.matches(fileStamp: stamp) {
                apps.append(AppItem(name: entry.name, url: appURL, bundleIdentifier: entry.bundleIdentifier))
            } else {
                apps.append(AppItem(name: fallbackName(for: appURL), url: appURL, bundleIdentifier: nil))
            }
        }

        let sorted = apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let elapsedMs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        logger.info("catalog.load.fast count=\(sorted.count, privacy: .public) elapsed_ms=\(Double(elapsedMs) / 1_000_000, privacy: .public)")
        return sorted
    }

    func enrichApplications(_ apps: [AppItem]) -> [AppItem] {
        guard !apps.isEmpty else { return apps }

        let start = DispatchTime.now()
        let localeSignature = Self.localeSignature
        var cache = cacheStore.load(localeSignature: localeSignature)
        var cacheMisses = 0
        var enriched: [AppItem] = []
        enriched.reserveCapacity(apps.count)

        for app in apps {
            let cacheKey = app.url.resolvingSymlinksInPath().path
            let stamp = fileStamp(for: app.url)

            if let entry = cache.entries[cacheKey], entry.matches(fileStamp: stamp) {
                enriched.append(AppItem(name: entry.name, url: app.url, bundleIdentifier: entry.bundleIdentifier))
                continue
            }

            cacheMisses += 1
            let resolved = resolveMetadata(for: app.url, fallbackName: app.name)
            enriched.append(resolved)
            cache.entries[cacheKey] = .init(
                name: resolved.name,
                bundleIdentifier: resolved.bundleIdentifier,
                fileStamp: stamp
            )
        }

        cache.updatedAt = Date()
        cacheStore.save(cache)

        let elapsedMs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        logger.info(
            "catalog.enrich count=\(enriched.count, privacy: .public) misses=\(cacheMisses, privacy: .public) elapsed_ms=\(Double(elapsedMs) / 1_000_000, privacy: .public)"
        )
        return enriched
    }

    private func candidateRoots() -> [URL] {
        let homeApps = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications", isDirectory: true)

        let defaults = [
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeApps
        ]

        return defaults.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func resolveMetadata(for url: URL, fallbackName: String) -> AppItem {
        var candidates: [(name: String, source: Int)] = []
        var bundleIdentifier: String?

        if let bundle = Bundle(url: url) {
            bundleIdentifier = bundle.bundleIdentifier

            if let localizedDisplayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String {
                candidates.append((sanitizeName(localizedDisplayName), 92))
            }
            if let localizedBundleName = bundle.localizedInfoDictionary?["CFBundleName"] as? String {
                candidates.append((sanitizeName(localizedBundleName), 88))
            }
            if let displayName = bundle.infoDictionary?["CFBundleDisplayName"] as? String {
                candidates.append((sanitizeName(displayName), 82))
            }
            if let bundleName = bundle.infoDictionary?["CFBundleName"] as? String {
                candidates.append((sanitizeName(bundleName), 78))
            }
        }

        if let localizedName = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName {
            candidates.append((sanitizeName(localizedName), 72))
        }

        if candidates.isEmpty || bestLocalizedQualityScore(in: candidates) < 3 {
            if let loctableName = loctableDisplayName(for: url) {
                candidates.append((sanitizeName(loctableName), 98))
            }
        }

        candidates.append((sanitizeName(fallbackName), 10))
        let filtered = candidates.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let selected = selectBestName(from: filtered) ?? fallbackName
        return AppItem(name: selected, url: url, bundleIdentifier: bundleIdentifier)
    }

    private func loctableDisplayName(for url: URL) -> String? {
        let loctableURL = url
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("InfoPlist.loctable", isDirectory: false)

        guard fileManager.fileExists(atPath: loctableURL.path) else { return nil }
        guard let data = try? Data(contentsOf: loctableURL) else { return nil }
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let table = object as? [String: Any] else {
            return nil
        }

        let normalizedTable: [String: [String: Any]] = table.reduce(into: [:]) { partial, entry in
            if let dict = entry.value as? [String: Any] {
                partial[entry.key.lowercased()] = dict
            }
        }

        for key in Self.preferredLocalizationKeys {
            guard let localeValues = normalizedTable[key] else { continue }

            if let displayName = localeValues["CFBundleDisplayName"] as? String,
               !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return displayName
            }

            if let bundleName = localeValues["CFBundleName"] as? String,
               !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return bundleName
            }
        }

        return nil
    }

    private func fallbackName(for url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        return sanitizeName(raw.replacingOccurrences(of: "-", with: " "))
    }

    private func sanitizeName(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectBestName(from candidates: [(name: String, source: Int)]) -> String? {
        candidates.max { lhs, rhs in
            let left = localizedQualityScore(lhs.name) * 1000 + lhs.source
            let right = localizedQualityScore(rhs.name) * 1000 + rhs.source
            return left < right
        }?.name
    }

    private func bestLocalizedQualityScore(in candidates: [(name: String, source: Int)]) -> Int {
        candidates.map { localizedQualityScore($0.name) }.max() ?? 0
    }

    private func localizedQualityScore(_ name: String) -> Int {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }

        if trimmed.unicodeScalars.contains(where: { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) || (0x3400...0x4DBF).contains(Int(scalar.value))
        }) {
            return 3
        }

        if trimmed.contains(" ") || trimmed.contains("-") {
            return 1
        }
        return 2
    }

    private func fileStamp(for url: URL) -> TimeInterval? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let date = values.contentModificationDate else {
            return nil
        }
        return date.timeIntervalSince1970
    }

    private static let localeSignature = Locale.preferredLanguages.joined(separator: "|")

    private static let preferredLocalizationKeys: [String] = {
        var keys: [String] = []

        for language in Locale.preferredLanguages {
            let normalized = language.replacingOccurrences(of: "-", with: "_")
            let parts = normalized.split(separator: "_").map(String.init)

            if !normalized.isEmpty {
                keys.append(normalized.lowercased())
            }

            if parts.count >= 3 {
                keys.append("\(parts[0])_\(parts[2])".lowercased())
                keys.append("\(parts[0])_\(parts[1])".lowercased())
            }

            if let first = parts.first {
                keys.append(first.lowercased())
            }
        }

        keys.append(contentsOf: ["zh_cn", "zh_hans", "zh", "en"])

        var deduped: [String] = []
        var seen = Set<String>()
        for key in keys where !key.isEmpty {
            if seen.insert(key).inserted {
                deduped.append(key)
            }
        }
        return deduped
    }()
}

private struct AppCatalogMetadataCache: Codable {
    static let schemaVersion = 1

    struct Entry: Codable {
        var name: String
        var bundleIdentifier: String?
        var fileStamp: TimeInterval?

        func matches(fileStamp: TimeInterval?) -> Bool {
            switch (self.fileStamp, fileStamp) {
            case (nil, nil):
                return true
            case let (lhs?, rhs?):
                return abs(lhs - rhs) < 0.001
            default:
                return false
            }
        }
    }

    var schemaVersion: Int
    var localeSignature: String
    var entries: [String: Entry]
    var updatedAt: Date

    static func empty(localeSignature: String) -> AppCatalogMetadataCache {
        .init(
            schemaVersion: AppCatalogMetadataCache.schemaVersion,
            localeSignature: localeSignature,
            entries: [:],
            updatedAt: Date()
        )
    }
}

private struct AppCatalogMetadataCacheStore {
    private static let logger = Logger(subsystem: "com.icc.launchdeck", category: "CatalogCache")

    private let fileManager = FileManager.default
    private let fileName = "app-catalog-cache-v1.json"

    func load(localeSignature: String) -> AppCatalogMetadataCache {
        let url = cacheURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            // ENOENT is expected on first launch; anything else is worth flagging.
            if !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError) {
                Self.logger.error("catalog cache read failed: \(error.localizedDescription, privacy: .public)")
            }
            return .empty(localeSignature: localeSignature)
        }

        do {
            let cache = try JSONDecoder().decode(AppCatalogMetadataCache.self, from: data)
            guard cache.schemaVersion == AppCatalogMetadataCache.schemaVersion else {
                Self.logger.notice(
                    "catalog cache schema mismatch (have=\(cache.schemaVersion), want=\(AppCatalogMetadataCache.schemaVersion)); discarding"
                )
                return .empty(localeSignature: localeSignature)
            }
            guard cache.localeSignature == localeSignature else {
                Self.logger.info(
                    "catalog cache locale signature changed (have=\(cache.localeSignature, privacy: .public), want=\(localeSignature, privacy: .public)); discarding"
                )
                return .empty(localeSignature: localeSignature)
            }
            return cache
        } catch {
            Self.logger.error("catalog cache decode failed: \(error.localizedDescription, privacy: .public)")
            return .empty(localeSignature: localeSignature)
        }
    }

    func save(_ cache: AppCatalogMetadataCache) {
        let data: Data
        do {
            data = try JSONEncoder().encode(cache)
        } catch {
            Self.logger.error("catalog cache encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let targetURL = cacheURL()
        let baseDirectory = targetURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            try data.write(to: targetURL, options: [.atomic])
        } catch {
            Self.logger.error(
                "catalog cache write failed at \(targetURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func cacheURL() -> URL {
        let baseDirectory: URL
        if let appSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            baseDirectory = appSupport.appendingPathComponent("LaunchDeck", isDirectory: true)
        } else {
            baseDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("LaunchDeck", isDirectory: true)
        }
        return baseDirectory.appendingPathComponent(fileName, isDirectory: false)
    }
}
