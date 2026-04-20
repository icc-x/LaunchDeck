import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum InitialWindowLayout {
        static let widthHeightRatio: CGFloat = 1.618033988749895
    }

    enum WindowIdentifier {
        static let settings = NSUserInterfaceItemIdentifier("launchdeck.settings")
    }

    private var suppressRestoreUntil = Date.distantPast
    private var initializedWindows = Set<ObjectIdentifier>()
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Lifecycle")

    /// Process-wide termination hook. Installed once from `LaunchDeckApp.init()` so that
    /// reordering or re-creating Scenes cannot clobber it.
    private nonisolated(unsafe) static var pendingTerminationHook: (@MainActor () async -> Void)?
    private var onWillTerminate: (@MainActor () async -> Void)?

    static func installTerminationHook(_ hook: @escaping @MainActor () async -> Void) {
        pendingTerminationHook = hook
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installWindowObservers()
        configureAllWindows()
        onWillTerminate = Self.pendingTerminationHook
        logger.info("app.did_finish_launching window_count=\(NSApp.windows.count, privacy: .public)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func installWindowObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleWindowNotification(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleWindowNotification(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @MainActor
    private func configureAllWindows() {
        for window in NSApp.windows {
            configure(window: window)
        }
    }

    @MainActor
    @objc
    private func handleWindowNotification(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        configure(window: window)
    }

    @MainActor
    private func configure(window: NSWindow) {
        if isSettingsWindow(window) {
            configureSettingsWindow(window)
        } else {
            configureMainWindow(window)
            let windowID = ObjectIdentifier(window)
            if initializedWindows.insert(windowID).inserted {
                applyInitialWindowLayout(window)
            }
        }
    }

    @MainActor
    private func configureMainWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        updateMainWindowMinimumSize()
    }

    @MainActor
    private func configureSettingsWindow(_ window: NSWindow) {
        window.identifier = WindowIdentifier.settings
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
    }

    @MainActor
    func updateMainWindowMinimumSize() {
        let preferences = LauncherPreferences.resolvedSnapshot()
        let size = AppGridPageView.minimumWindowSize(for: preferences.minimumVisibleIcons)
        let minimumSize = NSSize(width: ceil(size.width), height: ceil(size.height))

        for window in NSApp.windows where !isSettingsWindow(window) {
            window.contentMinSize = minimumSize
        }
    }

    @MainActor
    private func applyInitialWindowLayout(_ window: NSWindow) {
        let preferences = LauncherPreferences.resolvedSnapshot()
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }

        let minimumWindowSize = AppGridPageView.minimumWindowSize(for: preferences.minimumVisibleIcons)
        let minimumSize = NSSize(
            width: ceil(max(minimumWindowSize.width, window.contentMinSize.width)),
            height: ceil(max(minimumWindowSize.height, window.contentMinSize.height))
        )
        window.contentMinSize = minimumSize

        let screenArea = screenFrame.width * screenFrame.height
        let targetArea = screenArea * preferences.defaultWindowVisibleAreaRatio
        var targetWidth = floor(sqrt(targetArea * InitialWindowLayout.widthHeightRatio))
        var targetHeight = floor(targetWidth / InitialWindowLayout.widthHeightRatio)

        if targetWidth > screenFrame.width {
            targetWidth = floor(screenFrame.width)
            targetHeight = floor(targetWidth / InitialWindowLayout.widthHeightRatio)
        }
        if targetHeight > screenFrame.height {
            targetHeight = floor(screenFrame.height)
            targetWidth = floor(targetHeight * InitialWindowLayout.widthHeightRatio)
        }

        var finalWidth = max(targetWidth, minimumSize.width)
        var finalHeight = max(targetHeight, minimumSize.height)

        // Keep startup aspect around golden ratio while still honoring minimum size.
        if abs((finalWidth / max(1, finalHeight)) - InitialWindowLayout.widthHeightRatio) > 0.001 {
            finalWidth = max(finalWidth, finalHeight * InitialWindowLayout.widthHeightRatio)
            finalHeight = finalWidth / InitialWindowLayout.widthHeightRatio
        }

        finalWidth = min(finalWidth, screenFrame.width)
        finalHeight = min(finalHeight, screenFrame.height)

        let finalSize = NSSize(width: floor(finalWidth), height: floor(finalHeight))

        let origin = NSPoint(
            x: screenFrame.midX - finalSize.width * 0.5,
            y: max(screenFrame.minY, screenFrame.maxY - CGFloat(preferences.startupWindowTopInset) - finalSize.height)
        )
        let frame = NSRect(origin: origin, size: finalSize)
        window.setFrame(frame, display: true)
    }

    @MainActor
    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        // Match ONLY on our explicit identifier. Title-based matching is fragile across
        // locale switches because SwiftUI may update the identifier and title on different
        // run-loop ticks; we assign the identifier in `configureSettingsWindow` before any
        // other code queries it, so this is authoritative.
        if window.identifier == WindowIdentifier.settings {
            return true
        }
        // During the very first presentation, the identifier hasn't been set yet — fall back
        // to the SwiftUI-provided title which uses a stable localized string.
        return window.title == LaunchDeckStrings.settingsTitle
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let now = Date()
        if now < suppressRestoreUntil {
            logger.info("app.reopen.suppressed")
            return false
        }

        let visibleWindows = sender.windows.filter { window in
            window.isVisible && !window.isMiniaturized
        }

        // Reuse native minimize animation when app is already active and visible.
        if sender.isActive, !visibleWindows.isEmpty {
            for window in visibleWindows {
                window.performMiniaturize(nil)
            }
            // Some systems may emit a follow-up reopen callback for the same click.
            suppressRestoreUntil = now.addingTimeInterval(0.25)
            logger.info("app.reopen.minimize_visible_windows count=\(visibleWindows.count, privacy: .public)")
            return false
        }

        let miniaturizedWindows = sender.windows.filter(\.isMiniaturized)
        if !miniaturizedWindows.isEmpty {
            if sender.isHidden {
                sender.unhide(nil)
            }
            for window in miniaturizedWindows {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
            sender.activate(ignoringOtherApps: true)
            logger.info("app.reopen.restore_miniaturized_windows count=\(miniaturizedWindows.count, privacy: .public)")
            return false
        }

        // No visible/miniaturized window (e.g. user closed with red button):
        // hand off to AppKit/SwiftUI default reopen behavior so a fresh window can be created.
        logger.info("app.reopen.request_new_window")
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let onWillTerminate else {
            logger.info("app.terminate.immediate")
            return .terminateNow
        }

        logger.info("app.terminate.defer_for_flush")
        Task { @MainActor in
            await onWillTerminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
