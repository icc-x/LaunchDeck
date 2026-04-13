import Foundation

enum LaunchDeckStrings {
    static let tableName = "Localizable"

    static var windowTitle: String { localized("window.title", defaultValue: "LaunchDeck") }
    static var commandMenuTitle: String { localized("command.menu.title", defaultValue: "启动台") }
    static var defaultFolderName: String { localized("folder.default_name", defaultValue: "文件夹") }
    static var fallbackAppName: String { localized("app.default_name", defaultValue: "应用") }
    static var searchPlaceholder: String { localized("search.placeholder", defaultValue: "搜索应用") }
    static var refreshApps: String { localized("action.refresh_apps", defaultValue: "刷新应用列表") }
    static var refresh: String { localized("action.refresh", defaultValue: "刷新") }
    static var done: String { localized("action.done", defaultValue: "完成") }
    static var rename: String { localized("action.rename", defaultValue: "重命名") }
    static var close: String { localized("action.close", defaultValue: "关闭") }
    static var resetDefaults: String { localized("action.reset_defaults", defaultValue: "恢复默认设置") }
    static var diagnosticsExported: String { localized("status.diagnostics_exported", defaultValue: "诊断报告已导出") }
    static var diagnosticsExportCancelled: String { localized("status.diagnostics_export_cancelled", defaultValue: "已取消诊断导出") }
    static var sessionCleared: String { localized("status.session_cleared", defaultValue: "已清除会话恢复数据") }
    static var sessionRestored: String { localized("status.session_restored", defaultValue: "已恢复上次会话") }
    static var preferencesReset: String { localized("status.preferences_reset", defaultValue: "已恢复默认设置") }
    static var loadingApps: String { localized("loading.apps", defaultValue: "正在加载应用") }
    static var emptyTitle: String { localized("empty.title", defaultValue: "没有匹配的应用") }
    static var emptyDescription: String { localized("empty.description", defaultValue: "尝试修改关键字，或点击右上角刷新。") }
    static var dragFolderExtractHint: String { localized("folder.extract_hint", defaultValue: "拖到文件夹外部可移出") }
    static var folderNamePlaceholder: String { localized("folder.name.placeholder", defaultValue: "文件夹名称") }
    static var settingsTitle: String { localized("settings.title", defaultValue: "设置") }
    static var settingsInteractionSection: String { localized("settings.section.interaction", defaultValue: "交互") }
    static var settingsSessionSection: String { localized("settings.section.session", defaultValue: "恢复与存储") }
    static var settingsDiagnosticsSection: String { localized("settings.section.diagnostics", defaultValue: "诊断") }
    static var settingsAppearanceSection: String { localized("settings.section.appearance", defaultValue: "显示") }
    static var settingsFocusSearchOnLaunch: String { localized("settings.focus_search_on_launch", defaultValue: "启动时聚焦搜索框") }
    static var settingsEnableWheelPaging: String { localized("settings.enable_wheel_paging", defaultValue: "启用滚轮翻页") }
    static var settingsRestoreLastSession: String { localized("settings.restore_last_session", defaultValue: "恢复上次会话") }
    static var settingsShowStatusDetails: String { localized("settings.show_status_details", defaultValue: "显示状态详情") }
    static var settingsPrefetchDepth: String { localized("settings.prefetch_depth", defaultValue: "预取页深度") }
    static var settingsFolderPageSize: String { localized("settings.folder_page_size", defaultValue: "文件夹每页应用数") }
    static var settingsExportDiagnostics: String { localized("settings.export_diagnostics", defaultValue: "导出诊断报告…") }
    static var settingsClearSession: String { localized("settings.clear_session", defaultValue: "清除恢复会话") }
    static var settingsResetDefaults: String { localized("settings.reset_defaults", defaultValue: "恢复默认设置") }
    static var settingsLayoutPath: String { localized("settings.layout_path", defaultValue: "布局文件") }
    static var settingsSessionPath: String { localized("settings.session_path", defaultValue: "会话文件") }
    static var settingsDiagnosticsDescription: String { localized("settings.diagnostics.description", defaultValue: "导出当前布局、偏好、会话与运行摘要，便于排障。") }
    static var diagnosticsFileName: String { localized("diagnostics.file_name", defaultValue: "LaunchDeck-Diagnostics.json") }
    static var diagnosticsExportAction: String { localized("diagnostics.export.action", defaultValue: "导出诊断报告") }
    static var diagnosticsExportPrompt: String { localized("diagnostics.export.prompt", defaultValue: "选择诊断报告的保存位置。") }
    static var exportDiagnosticsCommand: String { localized("command.export_diagnostics", defaultValue: "导出诊断报告…") }
    static var reloadAccessibilityHint: String { localized("accessibility.reload_hint", defaultValue: "重新扫描本机应用并刷新布局") }
    static var settingsAccessibilityHint: String { localized("accessibility.settings_hint", defaultValue: "打开偏好设置窗口") }

    static func appCount(_ count: Int) -> String {
        String(format: localized("status.apps_count", defaultValue: "共 %ld 个应用，可拖拽分组或重排"), count)
    }

    static func defaultFolderNamePair(first: String, second: String) -> String {
        String(format: localized("folder.default_pair", defaultValue: "%1$@ 与 %2$@"), first, second)
    }

    static func appCountInFolder(_ count: Int) -> String {
        String(format: localized("folder.app_count", defaultValue: "%ld 个应用"), count)
    }

    static func pagePosition(current: Int, total: Int) -> String {
        String(format: localized("footer.page_position", defaultValue: "第 %ld / %ld 页"), current, total)
    }

    static func resultsCount(_ count: Int) -> String {
        String(format: localized("footer.results_count", defaultValue: "搜索结果 %ld 项"), count)
    }

    static func scanningStatus() -> String {
        localized("status.scanning", defaultValue: "正在扫描本机应用...")
    }

    static func noAppsStatus() -> String {
        localized("status.no_apps", defaultValue: "未发现可展示的应用。")
    }

    static func editingStatus() -> String {
        localized("status.editing", defaultValue: "编辑模式：拖拽可重排或分组")
    }

    static func folderOpened(_ name: String) -> String {
        String(format: localized("status.folder_opened", defaultValue: "已打开文件夹：%@"), name)
    }

    static func folderRenamed(_ name: String) -> String {
        String(format: localized("status.folder_renamed", defaultValue: "已将文件夹重命名为 %@"), name)
    }

    static func folderReordered(_ name: String) -> String {
        String(format: localized("status.folder_reordered", defaultValue: "已在 %@ 内重排"), name)
    }

    static func folderCrossPageMoved(_ name: String) -> String {
        String(format: localized("status.folder_cross_page", defaultValue: "已在 %@ 内跨页移动"), name)
    }

    static func folderExtracted(_ appName: String) -> String {
        String(format: localized("status.folder_extracted", defaultValue: "已将 %@ 移出文件夹"), appName)
    }

    static func groupedIntoFolder(_ appName: String, folderName: String) -> String {
        String(format: localized("status.grouped_into_folder", defaultValue: "已将 %@ 放入 %@"), appName, folderName)
    }

    static func createdFolder(_ name: String) -> String {
        String(format: localized("status.created_folder", defaultValue: "已创建文件夹：%@"), name)
    }

    static func rootReordered() -> String {
        localized("status.root_reordered", defaultValue: "已重排图标顺序")
    }

    static func rootMovedToPageBoundary(direction: Int) -> String {
        direction < 0
            ? localized("status.root_page_start", defaultValue: "已跨页移动到当前页开头")
            : localized("status.root_page_end", defaultValue: "已跨页移动到当前页末尾")
    }

    static func openingApp(_ appName: String) -> String {
        String(format: localized("status.opening_app", defaultValue: "正在打开 %@..."), appName)
    }

    static func openedApp(_ appName: String) -> String {
        String(format: localized("status.opened_app", defaultValue: "已打开 %@"), appName)
    }

    static func openAppFailed(_ appName: String) -> String {
        String(format: localized("status.open_failed", defaultValue: "打开失败：%@"), appName)
    }

    static func persistenceIncompatible(version: Int, backupPath: String) -> String {
        String(
            format: localized(
                "error.persistence_incompatible",
                defaultValue: "布局版本不兼容（schema v%ld），已备份到：%@。请升级应用后再恢复。"
            ),
            version,
            backupPath
        )
    }

    static func persistenceCorrupted() -> String {
        localized("error.persistence_corrupted", defaultValue: "布局文件损坏，已自动重置。")
    }

    static func persistenceSaveFailed(_ error: String) -> String {
        String(format: localized("error.persistence_save_failed", defaultValue: "保存布局失败：%@"), error)
    }

    static func sessionSaveFailed(_ error: String) -> String {
        String(format: localized("error.session_save_failed", defaultValue: "保存会话失败：%@"), error)
    }

    static func sessionClearFailed(_ error: String) -> String {
        String(format: localized("error.session_clear_failed", defaultValue: "清除恢复会话失败：%@"), error)
    }

    static func diagnosticsExportFailed(_ error: String) -> String {
        String(format: localized("error.diagnostics_export_failed", defaultValue: "导出诊断报告失败：%@"), error)
    }

    private static func localized(_ key: String, defaultValue: String) -> String {
        Bundle.module.localizedString(forKey: key, value: defaultValue, table: tableName)
    }
}
