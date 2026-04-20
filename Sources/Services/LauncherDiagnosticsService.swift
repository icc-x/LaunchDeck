import AppKit
import Foundation
import os

struct LauncherDiagnosticsReport: Codable, Sendable {
    struct Runtime: Codable, Sendable {
        var bundleIdentifier: String
        var appVersion: String
        var buildNumber: String
        var operatingSystemVersion: String
        var localeIdentifier: String
        var preferredLanguages: [String]
    }

    struct LayoutSummary: Codable, Sendable {
        var totalApps: Int
        var rootEntries: Int
        var folderCount: Int
        var searchQuery: String
        var currentPage: Int
        var totalPages: Int
        var activeFolderID: String?
        var activeFolderName: String?
        var isLoading: Bool
        var lastError: String?
        var statusMessage: String
    }

    struct Storage: Codable, Sendable {
        var layoutPath: String
        var sessionPath: String
    }

    var generatedAt: Date
    var runtime: Runtime
    var preferences: LauncherPreferencesSnapshot
    var restoredSession: LauncherSessionSnapshot?
    var storage: Storage
    var layout: LayoutSummary
}

enum LauncherDiagnosticsError: Error {
    case cancelled
}

@MainActor
struct LauncherDiagnosticsService {
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Diagnostics")

    func makeReport(
        preferences: LauncherPreferencesSnapshot,
        restoredSession: LauncherSessionSnapshot?,
        layoutPath: String,
        sessionPath: String,
        allAppsCount: Int,
        rootEntries: [LauncherEntry],
        query: String,
        currentPage: Int,
        pagesCount: Int,
        activeFolder: FolderItem?,
        isLoading: Bool,
        lastError: String?,
        statusMessage: String
    ) -> LauncherDiagnosticsReport {
        let folderCount = rootEntries.compactMap(\.folderValue).count
        let bundle = Bundle.main

        return LauncherDiagnosticsReport(
            generatedAt: Date(),
            runtime: .init(
                bundleIdentifier: bundle.bundleIdentifier ?? "com.icc.launchdeck",
                appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                localeIdentifier: Locale.current.identifier,
                preferredLanguages: Locale.preferredLanguages
            ),
            preferences: preferences,
            restoredSession: restoredSession,
            storage: .init(
                layoutPath: layoutPath,
                sessionPath: sessionPath
            ),
            layout: .init(
                totalApps: allAppsCount,
                rootEntries: rootEntries.count,
                folderCount: folderCount,
                searchQuery: query,
                currentPage: currentPage,
                totalPages: pagesCount,
                activeFolderID: activeFolder?.id,
                activeFolderName: activeFolder?.name,
                isLoading: isLoading,
                lastError: lastError,
                statusMessage: statusMessage
            )
        )
    }

    func export(report: LauncherDiagnosticsReport) async throws -> URL {
        let saveURL = try selectExportURL()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: saveURL, options: [.atomic])
        logger.info("diagnostics.export path=\(saveURL.path, privacy: .public)")
        return saveURL
    }

    private func selectExportURL() throws -> URL {
        let panel = NSSavePanel()
        panel.title = LaunchDeckStrings.diagnosticsExportAction
        panel.message = LaunchDeckStrings.diagnosticsExportPrompt
        panel.nameFieldStringValue = LaunchDeckStrings.diagnosticsFileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw LauncherDiagnosticsError.cancelled
        }
        return url
    }
}
