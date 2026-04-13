import Foundation
import XCTest
@testable import LaunchDeck

final class LaunchDeckStringsTests: XCTestCase {
    func testLocalizedStringMatchesLowercasedScriptLocalizationFolder() throws {
        let bundle = try makeBundle(
            localizations: [
                "en": [
                    "settings.title": "Settings",
                    "footer.page_position": "Page %ld of %ld",
                ],
                "zh-hans": [
                    "settings.title": "设置",
                    "footer.page_position": "第 %ld / %ld 页",
                ],
            ],
            developmentLocalization: "zh-Hans"
        )

        XCTAssertEqual(
            LaunchDeckStrings.localizedString(
                forKey: "settings.title",
                defaultValue: "<missing>",
                bundle: bundle,
                preferredLanguages: ["zh-Hans-CN", "en-CN"]
            ),
            "设置"
        )

        XCTAssertEqual(
            String(
                format: LaunchDeckStrings.localizedString(
                    forKey: "footer.page_position",
                    defaultValue: "<missing>",
                    bundle: bundle,
                    preferredLanguages: ["zh-Hans-CN", "en-CN"]
                ),
                2,
                5
            ),
            "第 2 / 5 页"
        )
    }

    func testLocalizedStringFallsBackToEnglishWhenPreferredLocalizationIsUnavailable() throws {
        let bundle = try makeBundle(
            localizations: [
                "en": [
                    "settings.title": "Settings",
                ],
            ],
            developmentLocalization: "en"
        )

        XCTAssertEqual(
            LaunchDeckStrings.localizedString(
                forKey: "settings.title",
                defaultValue: "<missing>",
                bundle: bundle,
                preferredLanguages: ["fr-FR"]
            ),
            "Settings"
        )
    }

    private func makeBundle(
        localizations: [String: [String: String]],
        developmentLocalization: String
    ) throws -> Bundle {
        let fileManager = FileManager.default
        let bundleURL = fileManager.temporaryDirectory
            .appendingPathComponent("LaunchDeckStringsTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathExtension("bundle")

        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.icc.launchdeck.tests.localization",
            "CFBundleDevelopmentRegion": developmentLocalization,
            "CFBundlePackageType": "BNDL",
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: bundleURL.appendingPathComponent("Info.plist"), options: .atomic)

        for (localization, strings) in localizations {
            let lprojURL = bundleURL.appendingPathComponent("\(localization).lproj", isDirectory: true)
            try fileManager.createDirectory(at: lprojURL, withIntermediateDirectories: true)

            let content = strings
                .sorted(by: { $0.key < $1.key })
                .map { "\"\($0.key)\" = \"\($0.value)\";" }
                .joined(separator: "\n")

            try content.write(
                to: lprojURL.appendingPathComponent("Localizable.strings"),
                atomically: true,
                encoding: .utf8
            )
        }

        guard let bundle = Bundle(url: bundleURL) else {
            XCTFail("无法创建测试 bundle")
            throw NSError(domain: "LaunchDeckStringsTests", code: 1)
        }

        return bundle
    }
}
