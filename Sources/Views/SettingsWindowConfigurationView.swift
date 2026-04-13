import AppKit
import SwiftUI

struct SettingsWindowConfigurationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfAvailable(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfAvailable(for: nsView)
        }
    }

    @MainActor
    private func configureWindowIfAvailable(for view: NSView) {
        guard let window = view.window else { return }
        window.identifier = AppDelegate.WindowIdentifier.settings
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
    }
}
