import Foundation
import os

struct LauncherSessionSnapshot: Codable, Equatable, Sendable {
    var query: String
    var currentPage: Int
    var activeFolderID: String?
    var updatedAt: Date
}

struct LauncherSessionPersistence: @unchecked Sendable {
    private actor SessionWriter {
        func write(data: Data, to url: URL, fileManager: FileManager) throws {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        }

        func delete(at url: URL, fileManager: FileManager) throws {
            guard fileManager.fileExists(atPath: url.path) else { return }
            try fileManager.removeItem(at: url)
        }
    }

    private static let writer = SessionWriter()

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let fileName = "session-v1.json"
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "SessionPersistence")

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? LauncherLayoutPersistence.defaultBaseDirectory(fileManager: fileManager)
    }

    var fileURL: URL {
        baseDirectory.appendingPathComponent(fileName, isDirectory: false)
    }

    var storagePath: String {
        fileURL.path
    }

    func load() -> LauncherSessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try? decoder.decode(LauncherSessionSnapshot.self, from: data)
        if snapshot != nil {
            logger.info("session.load path=\(fileURL.path, privacy: .public)")
        }
        return snapshot
    }

    func saveAsync(_ snapshot: LauncherSessionSnapshot) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        try await Self.writer.write(data: data, to: fileURL, fileManager: fileManager)
        logger.info("session.save path=\(fileURL.path, privacy: .public)")
    }

    func deleteAsync() async throws {
        try await Self.writer.delete(at: fileURL, fileManager: fileManager)
        logger.info("session.delete path=\(fileURL.path, privacy: .public)")
    }
}
