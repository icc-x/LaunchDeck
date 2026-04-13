import Foundation
import XCTest
@testable import LaunchDeck

final class AppCatalogScannerTests: XCTestCase {
    func testScanReturnsAllApplicationsWithoutHardCap() throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        for index in 0..<300 {
            let appURL = directory.appendingPathComponent(String(format: "App-%03d.app", index), isDirectory: true)
            try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        }

        let urls = AppCatalogScanner(fileManager: fileManager, roots: [directory]).scan()

        XCTAssertEqual(urls.count, 300)
    }

    private func makeTemporaryDirectory(fileManager: FileManager) -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("LaunchDeckScannerTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
