import XCTest
@testable import LaunchDeck

@MainActor
final class AppIconProviderTests: XCTestCase {
    func testIconLoadedPublisherEmitsAfterLoadingBundleIcon() async throws {
        let fileManager = FileManager.default
        let directory = makeTemporaryDirectory(fileManager: fileManager)
        defer { try? fileManager.removeItem(at: directory) }

        let appURL = try makeTestAppBundle(at: directory, fileManager: fileManager)
        let app = AppItem(name: "Icon Test", url: appURL, bundleIdentifier: "test.icon")
        let provider = AppIconProvider()
        let expectation = expectation(description: "icon loaded")

        let cancellable = provider.iconLoadedPublisher(for: [app.id]).sink { _ in
            expectation.fulfill()
        }

        _ = provider.icon(for: app)
        await fulfillment(of: [expectation], timeout: 2.0)
        _ = cancellable
        XCTAssertNotNil(provider.icon(for: app).tiffRepresentation)
    }

    private func makeTestAppBundle(at directory: URL, fileManager: FileManager) throws -> URL {
        let appURL = directory.appendingPathComponent("IconTest.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: sampleIconURL(), to: resourcesURL.appendingPathComponent("AppIcon.icns"))

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>IconTest</string>
            <key>CFBundleIconFile</key>
            <string>AppIcon</string>
            <key>CFBundleIdentifier</key>
            <string>test.icon</string>
            <key>CFBundleName</key>
            <string>IconTest</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """
        try Data(plist.utf8).write(
            to: contentsURL.appendingPathComponent("Info.plist"),
            options: [.atomic]
        )

        return appURL
    }

    private func sampleIconURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("AppIcon.icns", isDirectory: false)
    }

    private func makeTemporaryDirectory(fileManager: FileManager) -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("LaunchDeckIconTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: url)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
