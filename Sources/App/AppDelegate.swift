import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum InitialWindowLayout {
        static let targetVisibleAreaRatio: CGFloat = 0.40
        static let widthHeightRatio: CGFloat = 1.618033988749895
    }

    private var suppressRestoreUntil = Date.distantPast
    private var initializedWindows = Set<ObjectIdentifier>()
    private let logger = Logger(subsystem: "com.icc.launchdeck", category: "Lifecycle")
    var onWillTerminate: (@MainActor () async -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installWindowObservers()
        configureAllWindows()
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
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true

        let windowID = ObjectIdentifier(window)
        if initializedWindows.insert(windowID).inserted {
            applyInitialWindowSize(window)
        }
    }

    @MainActor
    private func applyInitialWindowSize(_ window: NSWindow) {
        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }

        let screenArea = screenFrame.width * screenFrame.height
        let targetArea = screenArea * InitialWindowLayout.targetVisibleAreaRatio
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

        let minimumSize = window.contentMinSize
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
            y: screenFrame.midY - finalSize.height * 0.5
        )
        let frame = NSRect(origin: origin, size: finalSize)
        window.setFrame(frame, display: true)
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
