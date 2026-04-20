import Foundation
import SwiftUI

/// Wrap a view that needs a `Binding` so it can be used from an Xcode `#Preview` block
/// without having to hoist state into the enclosing preview provider.
///
/// Previews cannot own `@State` directly at the top level of a `#Preview { ... }` closure,
/// so we use this wrapper to materialize a binding on first render.
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

/// Sample data used throughout SwiftUI previews. Centralized here so that previews don't
/// rely on filesystem scanning and render deterministically.
enum LaunchDeckPreviewFixtures {
    static let safari = AppItem(
        name: "Safari",
        url: URL(fileURLWithPath: "/Applications/Safari.app"),
        bundleIdentifier: "com.apple.Safari"
    )

    static let mail = AppItem(
        name: "Mail",
        url: URL(fileURLWithPath: "/Applications/Mail.app"),
        bundleIdentifier: "com.apple.mail"
    )

    static let notes = AppItem(
        name: "Notes",
        url: URL(fileURLWithPath: "/Applications/Notes.app"),
        bundleIdentifier: "com.apple.Notes"
    )

    static let reminders = AppItem(
        name: "Reminders",
        url: URL(fileURLWithPath: "/Applications/Reminders.app"),
        bundleIdentifier: "com.apple.reminders"
    )

    static let utilitiesFolder = FolderItem(
        id: "utilities",
        name: "Utilities",
        apps: [safari, mail, notes, reminders]
    )
}
