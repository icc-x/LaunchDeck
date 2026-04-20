import Foundation

/// Encapsulates the state machine for "drag near edge → flip pages" interactions.
///
/// The caller reports hover ticks (`hover(direction:now:)`) and resets when the drag
/// leaves the edge or ends (`reset()`). The scroller returns `true` from `hover` when the
/// caller should perform a flip in the given direction. Timings are pulled from
/// ``LauncherTuning/EdgePaging`` so root-grid and folder-grid behaviour stay identical.
///
/// This type is not thread-safe; use from the main actor (matching the SwiftUI drop
/// delegates that drive it).
struct EdgePageScroller {
    private var activeDirection: Int?
    private var hoverStartedAt: Date = .distantPast
    private var lastFlipAt: Date = .distantPast

    /// Report that the drag is hovering on an edge in `direction` (-1 = leading / left,
    /// +1 = trailing / right). Returns `true` when the caller should flip a page now.
    mutating func hover(direction: Int, now: Date = Date()) -> Bool {
        if activeDirection != direction {
            activeDirection = direction
            hoverStartedAt = now
            lastFlipAt = now
            return false
        }

        let elapsed = now.timeIntervalSince(hoverStartedAt)
        guard elapsed >= LauncherTuning.EdgePaging.initialDwell else { return false }

        let interval = LauncherTuning.EdgePaging.resolvedInterval(forHoverElapsed: elapsed)
        guard now.timeIntervalSince(lastFlipAt) >= interval else { return false }

        lastFlipAt = now
        return true
    }

    /// Reset the scroller. Call when the drag leaves the edge, ends, or is cancelled.
    mutating func reset() {
        activeDirection = nil
        hoverStartedAt = .distantPast
        lastFlipAt = .distantPast
    }
}
