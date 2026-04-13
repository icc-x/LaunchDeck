import AppKit
import SwiftUI

struct ScrollWheelCaptureView: NSViewRepresentable {
    let onScroll: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        context.coordinator.onScroll = onScroll
        nsView.coordinator = context.coordinator
    }
}

final class CaptureView: NSView {
    weak var coordinator: ScrollWheelCaptureView.Coordinator?
    private var isRegistered = false

    private static let registeredViews = NSHashTable<CaptureView>.weakObjects()
    private static var sharedMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            unregisterIfNeeded()
        } else {
            registerIfNeeded()
        }
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        unregisterIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    fileprivate func handleScrollEvent(_ event: NSEvent) -> Bool {
        guard let coordinator, let window, event.window === window else { return false }
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else { return false }
        return coordinator.onScroll(event)
    }

    private func registerIfNeeded() {
        guard !isRegistered else { return }
        isRegistered = true
        Self.registeredViews.add(self)
        Self.installSharedMonitorIfNeeded()
    }

    private func unregisterIfNeeded() {
        guard isRegistered else { return }
        isRegistered = false
        Self.registeredViews.remove(self)
        Self.removeSharedMonitorIfPossible()
    }

    private static func installSharedMonitorIfNeeded() {
        guard sharedMonitor == nil else { return }
        sharedMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            for view in registeredViews.allObjects where view.handleScrollEvent(event) {
                return nil
            }
            return event
        }
    }

    private static func removeSharedMonitorIfPossible() {
        guard registeredViews.allObjects.isEmpty, let sharedMonitor else { return }
        NSEvent.removeMonitor(sharedMonitor)
        self.sharedMonitor = nil
    }
}

extension ScrollWheelCaptureView {
    final class Coordinator {
        var onScroll: (NSEvent) -> Bool

        init(onScroll: @escaping (NSEvent) -> Bool) {
            self.onScroll = onScroll
        }
    }
}
