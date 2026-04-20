import AppKit
import SwiftUI

/// Canonical animation tokens. Callers should prefer the `launchAnimation(_:value:)` view
/// modifier or the `withLaunchAnimation(_:_:)` free function below so that the
/// "Reduce Motion" accessibility preference is honoured automatically.
enum LaunchMotion {
    static let reorder = Animation.interactiveSpring(
        response: 0.28,
        dampingFraction: 0.84,
        blendDuration: 0.16
    )

    static let page = Animation.interactiveSpring(
        response: 0.46,
        dampingFraction: 0.90,
        blendDuration: 0.22
    )

    static let modal = Animation.interactiveSpring(
        response: 0.42,
        dampingFraction: 0.88,
        blendDuration: 0.18
    )

    static let hover = Animation.spring(
        response: 0.30,
        dampingFraction: 0.86,
        blendDuration: 0.12
    )

    static let smooth = Animation.easeInOut(duration: 0.28)
    static let quickFade = Animation.easeInOut(duration: 0.20)
}

extension View {
    /// `.animation(_:value:)` that automatically drops to `nil` (no animation) when the user
    /// has enabled "Reduce Motion" in System Settings ▸ Accessibility ▸ Display.
    func launchAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }
}

/// `withAnimation(_:_:)` that honours "Reduce Motion".
///
/// Must be called from the main actor (same constraint as `withAnimation`). Reads the
/// accessibility preference synchronously via `NSWorkspace`, which is cheap and cached by
/// AppKit.
@MainActor
@discardableResult
func withLaunchAnimation<Result>(
    _ animation: Animation,
    _ body: () throws -> Result
) rethrows -> Result {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        return try withAnimation(nil, body)
    }
    return try withAnimation(animation, body)
}

private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
