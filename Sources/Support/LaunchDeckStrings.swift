import Foundation

enum LaunchDeckStrings {
    static let tableName = "Localizable"

    static var windowTitle: String { localizedString(forKey: "window.title", defaultValue: "LaunchDeck") }
    static var commandMenuTitle: String { localizedString(forKey: "command.menu.title", defaultValue: "启动台") }
    static var defaultFolderName: String { localizedString(forKey: "folder.default_name", defaultValue: "文件夹") }
    static var fallbackAppName: String { localizedString(forKey: "app.default_name", defaultValue: "应用") }
    static var searchPlaceholder: String { localizedString(forKey: "search.placeholder", defaultValue: "搜索应用") }
    static var refreshApps: String { localizedString(forKey: "action.refresh_apps", defaultValue: "刷新应用列表") }
    static var refresh: String { localizedString(forKey: "action.refresh", defaultValue: "刷新") }
    static var done: String { localizedString(forKey: "action.done", defaultValue: "完成") }
    static var rename: String { localizedString(forKey: "action.rename", defaultValue: "重命名") }
    static var close: String { localizedString(forKey: "action.close", defaultValue: "关闭") }
    static var resetDefaults: String { localizedString(forKey: "action.reset_defaults", defaultValue: "恢复默认设置") }
    static var diagnosticsExported: String { localizedString(forKey: "status.diagnostics_exported", defaultValue: "诊断报告已导出") }
    static var diagnosticsExportCancelled: String { localizedString(forKey: "status.diagnostics_export_cancelled", defaultValue: "已取消诊断导出") }
    static var sessionCleared: String { localizedString(forKey: "status.session_cleared", defaultValue: "已清除会话恢复数据") }
    static var sessionRestored: String { localizedString(forKey: "status.session_restored", defaultValue: "已恢复上次会话") }
    static var preferencesReset: String { localizedString(forKey: "status.preferences_reset", defaultValue: "已恢复默认设置") }
    static var loadingApps: String { localizedString(forKey: "loading.apps", defaultValue: "正在加载应用") }
    static var emptyTitle: String { localizedString(forKey: "empty.title", defaultValue: "没有匹配的应用") }
    static var emptyDescription: String { localizedString(forKey: "empty.description", defaultValue: "尝试修改关键字，或点击右上角刷新。") }
    static var dragFolderExtractHint: String { localizedString(forKey: "folder.extract_hint", defaultValue: "拖到文件夹外部可移出") }
    static var folderNamePlaceholder: String { localizedString(forKey: "folder.name.placeholder", defaultValue: "文件夹名称") }
    static var settingsTitle: String { localizedString(forKey: "settings.title", defaultValue: "设置") }
    static var settingsInteractionSection: String { localizedString(forKey: "settings.section.interaction", defaultValue: "交互") }
    static var settingsSessionSection: String { localizedString(forKey: "settings.section.session", defaultValue: "恢复与存储") }
    static var settingsDiagnosticsSection: String { localizedString(forKey: "settings.section.diagnostics", defaultValue: "诊断") }
    static var settingsAppearanceSection: String { localizedString(forKey: "settings.section.appearance", defaultValue: "显示") }
    static var settingsWindowSection: String { localizedString(forKey: "settings.section.window", defaultValue: "窗口") }
    static var settingsAppearanceMode: String { localizedString(forKey: "settings.appearance_mode", defaultValue: "外观风格") }
    static var settingsFocusSearchOnLaunch: String { localizedString(forKey: "settings.focus_search_on_launch", defaultValue: "启动时聚焦搜索框") }
    static var settingsEnableWheelPaging: String { localizedString(forKey: "settings.enable_wheel_paging", defaultValue: "启用滚轮翻页") }
    static var settingsRestoreLastSession: String { localizedString(forKey: "settings.restore_last_session", defaultValue: "恢复上次会话") }
    static var settingsShowStatusDetails: String { localizedString(forKey: "settings.show_status_details", defaultValue: "显示状态详情") }
    static var settingsPrefetchDepth: String { localizedString(forKey: "settings.prefetch_depth", defaultValue: "预取页深度") }
    static var settingsFolderPageSize: String { localizedString(forKey: "settings.folder_page_size", defaultValue: "文件夹每页应用数") }
    static var settingsExportDiagnostics: String { localizedString(forKey: "settings.export_diagnostics", defaultValue: "导出诊断报告…") }
    static var settingsClearSession: String { localizedString(forKey: "settings.clear_session", defaultValue: "清除恢复会话") }
    static var settingsResetDefaults: String { localizedString(forKey: "settings.reset_defaults", defaultValue: "恢复默认设置") }
    static var settingsLayoutPath: String { localizedString(forKey: "settings.layout_path", defaultValue: "布局文件") }
    static var settingsSessionPath: String { localizedString(forKey: "settings.session_path", defaultValue: "会话文件") }
    static var settingsWindowDescription: String { localizedString(forKey: "settings.window.description", defaultValue: "以下设置会影响新建主窗口和下次启动时的默认布局。") }
    static var settingsMinimumVisibleIcons: String { localizedString(forKey: "settings.minimum_visible_icons", defaultValue: "启动窗口最少可见图标数") }
    static var settingsDefaultWindowVisibleArea: String { localizedString(forKey: "settings.default_window_visible_area", defaultValue: "启动窗口面积占比") }
    static var settingsStartupWindowTopInset: String { localizedString(forKey: "settings.startup_window_top_inset", defaultValue: "启动窗口顶部间距") }
    static var settingsDiagnosticsDescription: String { localizedString(forKey: "settings.diagnostics.description", defaultValue: "导出当前布局、偏好、会话与运行摘要，便于排障。") }
    static var diagnosticsFileName: String { localizedString(forKey: "diagnostics.file_name", defaultValue: "LaunchDeck-Diagnostics.json") }
    static var diagnosticsExportAction: String { localizedString(forKey: "diagnostics.export.action", defaultValue: "导出诊断报告") }
    static var diagnosticsExportPrompt: String { localizedString(forKey: "diagnostics.export.prompt", defaultValue: "选择诊断报告的保存位置。") }
    static var exportDiagnosticsCommand: String { localizedString(forKey: "command.export_diagnostics", defaultValue: "导出诊断报告…") }
    static var reloadAccessibilityHint: String { localizedString(forKey: "accessibility.reload_hint", defaultValue: "重新扫描本机应用并刷新布局") }
    static var settingsAccessibilityHint: String { localizedString(forKey: "accessibility.settings_hint", defaultValue: "打开偏好设置窗口") }
    static var appearanceFollowSystem: String { localizedString(forKey: "appearance.follow_system", defaultValue: "跟随系统") }
    static var appearanceLight: String { localizedString(forKey: "appearance.light", defaultValue: "浅色") }
    static var appearanceDark: String { localizedString(forKey: "appearance.dark", defaultValue: "深色") }

    static func appCount(_ count: Int) -> String {
        String(format: localizedString(forKey: "status.apps_count", defaultValue: "共 %ld 个应用，可拖拽分组或重排"), count)
    }

    static func defaultFolderNamePair(first: String, second: String) -> String {
        String(format: localizedString(forKey: "folder.default_pair", defaultValue: "%1$@ 与 %2$@"), first, second)
    }

    static func appCountInFolder(_ count: Int) -> String {
        String(format: localizedString(forKey: "folder.app_count", defaultValue: "%ld 个应用"), count)
    }

    static func pagePosition(current: Int, total: Int) -> String {
        String(format: localizedString(forKey: "footer.page_position", defaultValue: "第 %ld / %ld 页"), current, total)
    }

    static func resultsCount(_ count: Int) -> String {
        String(format: localizedString(forKey: "footer.results_count", defaultValue: "搜索结果 %ld 项"), count)
    }

    static func scanningStatus() -> String {
        localizedString(forKey: "status.scanning", defaultValue: "正在扫描本机应用...")
    }

    static func noAppsStatus() -> String {
        localizedString(forKey: "status.no_apps", defaultValue: "未发现可展示的应用。")
    }

    static func editingStatus() -> String {
        localizedString(forKey: "status.editing", defaultValue: "编辑模式：拖拽可重排或分组")
    }

    static func folderOpened(_ name: String) -> String {
        String(format: localizedString(forKey: "status.folder_opened", defaultValue: "已打开文件夹：%@"), name)
    }

    static func folderRenamed(_ name: String) -> String {
        String(format: localizedString(forKey: "status.folder_renamed", defaultValue: "已将文件夹重命名为 %@"), name)
    }

    static func folderReordered(_ name: String) -> String {
        String(format: localizedString(forKey: "status.folder_reordered", defaultValue: "已在 %@ 内重排"), name)
    }

    static func folderCrossPageMoved(_ name: String) -> String {
        String(format: localizedString(forKey: "status.folder_cross_page", defaultValue: "已在 %@ 内跨页移动"), name)
    }

    static func folderExtracted(_ appName: String) -> String {
        String(format: localizedString(forKey: "status.folder_extracted", defaultValue: "已将 %@ 移出文件夹"), appName)
    }

    static func groupedIntoFolder(_ appName: String, folderName: String) -> String {
        String(format: localizedString(forKey: "status.grouped_into_folder", defaultValue: "已将 %@ 放入 %@"), appName, folderName)
    }

    static func createdFolder(_ name: String) -> String {
        String(format: localizedString(forKey: "status.created_folder", defaultValue: "已创建文件夹：%@"), name)
    }

    static func rootReordered() -> String {
        localizedString(forKey: "status.root_reordered", defaultValue: "已重排图标顺序")
    }

    static func rootMovedToPageBoundary(direction: Int) -> String {
        direction < 0
            ? localizedString(forKey: "status.root_page_start", defaultValue: "已跨页移动到当前页开头")
            : localizedString(forKey: "status.root_page_end", defaultValue: "已跨页移动到当前页末尾")
    }

    static func openingApp(_ appName: String) -> String {
        String(format: localizedString(forKey: "status.opening_app", defaultValue: "正在打开 %@..."), appName)
    }

    static func openedApp(_ appName: String) -> String {
        String(format: localizedString(forKey: "status.opened_app", defaultValue: "已打开 %@"), appName)
    }

    static func openAppFailed(_ appName: String) -> String {
        String(format: localizedString(forKey: "status.open_failed", defaultValue: "打开失败：%@"), appName)
    }

    static func persistenceIncompatible(version: Int, backupPath: String) -> String {
        String(
            format: localizedString(
                forKey: "error.persistence_incompatible",
                defaultValue: "布局版本不兼容（schema v%ld），已备份到：%@。请升级应用后再恢复。"
            ),
            version,
            backupPath
        )
    }

    static func persistenceCorrupted() -> String {
        localizedString(forKey: "error.persistence_corrupted", defaultValue: "布局文件损坏，已自动重置。")
    }

    static func persistenceSaveFailed(_ error: String) -> String {
        String(format: localizedString(forKey: "error.persistence_save_failed", defaultValue: "保存布局失败：%@"), error)
    }

    static func sessionSaveFailed(_ error: String) -> String {
        String(format: localizedString(forKey: "error.session_save_failed", defaultValue: "保存会话失败：%@"), error)
    }

    static func sessionClearFailed(_ error: String) -> String {
        String(format: localizedString(forKey: "error.session_clear_failed", defaultValue: "清除恢复会话失败：%@"), error)
    }

    static func diagnosticsExportFailed(_ error: String) -> String {
        String(format: localizedString(forKey: "error.diagnostics_export_failed", defaultValue: "导出诊断报告失败：%@"), error)
    }

    static func localizedString(
        forKey key: String,
        defaultValue: String,
        bundle: Bundle = .module,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        guard let localizationBundle = bundleForPreferredLocalization(bundle: bundle, preferredLanguages: preferredLanguages) else {
            return bundle.localizedString(forKey: key, value: defaultValue, table: tableName)
        }
        return localizationBundle.localizedString(forKey: key, value: defaultValue, table: tableName)
    }

    private static func bundleForPreferredLocalization(bundle: Bundle, preferredLanguages: [String]) -> Bundle? {
        guard let localization = resolvedLocalizationIdentifier(in: bundle, preferredLanguages: preferredLanguages) else {
            return nil
        }

        guard let path = bundle.path(forResource: localization, ofType: "lproj"),
              let localizationBundle = Bundle(path: path) else {
            return nil
        }
        return localizationBundle
    }

    private static func resolvedLocalizationIdentifier(in bundle: Bundle, preferredLanguages: [String]) -> String? {
        let availableLocalizations = bundle.localizations
        guard !availableLocalizations.isEmpty else { return nil }

        let availableByNormalizedIdentifier = Dictionary(uniqueKeysWithValues: availableLocalizations.map {
            (normalizeLocalizationIdentifier($0), $0)
        })

        for candidate in localizationCandidates(from: preferredLanguages) {
            if let match = availableByNormalizedIdentifier[normalizeLocalizationIdentifier(candidate)] {
                return match
            }
        }

        if let developmentLocalization = bundle.developmentLocalization,
           let match = availableByNormalizedIdentifier[normalizeLocalizationIdentifier(developmentLocalization)] {
            return match
        }

        if let english = availableByNormalizedIdentifier["en"] {
            return english
        }

        return availableLocalizations.first
    }

    private static func localizationCandidates(from preferredLanguages: [String]) -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func append(_ value: String) {
            let normalized = normalizeLocalizationIdentifier(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return }
            candidates.append(normalized)
        }

        for language in preferredLanguages {
            let normalized = normalizeLocalizationIdentifier(language)
            let components = normalized.split(separator: "-").map(String.init)

            append(normalized)

            if components.count >= 3 {
                append("\(components[0])-\(components[1])")
                append("\(components[0])-\(components[2])")
            } else if components.count >= 2 {
                append("\(components[0])-\(components[1])")
            }

            if let languageCode = components.first {
                append(languageCode)
            }
        }

        return candidates
    }

    private static func normalizeLocalizationIdentifier(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }
}
