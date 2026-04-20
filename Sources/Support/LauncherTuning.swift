import CoreGraphics
import Foundation

/// Tuning constants governing drag/drop interaction, edge-paging acceleration, and the
/// rectangle inside a tile that counts as "drop-onto-entry to group" vs "drop-between-entries
/// to reorder".
///
/// These values were formerly scattered as magic numbers across `LauncherStore`,
/// `AppGridPageView`, and `FolderOverlayView`. Consolidating them here makes it possible
/// to A/B tune the feel of the app, and ensures root-grid and folder-grid behaviour stay
/// in sync.
enum LauncherTuning {
    /// Edge-hover page-flip pacing: how long the cursor must linger before any flip fires,
    /// and how quickly subsequent flips accelerate.
    enum EdgePaging {
        /// Minimum dwell time before the first flip after the user starts hovering on an
        /// edge.
        static let initialDwell: TimeInterval = 0.20

        /// Lower bound for the interval between successive flips. Prevents runaway paging.
        static let minimumInterval: TimeInterval = 0.08

        /// Base interval from which the dynamic interval decays.
        static let baseInterval: TimeInterval = 0.34

        /// How strongly hover duration decays the interval.
        static let accelerationSlope: TimeInterval = 0.22

        /// Resolved "next flip may fire" interval given how long the cursor has lingered.
        static func resolvedInterval(forHoverElapsed hoverElapsed: TimeInterval) -> TimeInterval {
            max(minimumInterval, baseInterval - hoverElapsed * accelerationSlope)
        }
    }

    /// Wheel-paging pacing: minimum interval between successive wheel-triggered flips so
    /// users with high-resolution scroll wheels don't fly across the deck.
    enum WheelPaging {
        static let minimumInterval: TimeInterval = 0.16
    }

    /// Debounce intervals for async work. Expressed in nanoseconds to match `Task.sleep`.
    enum Debounce {
        /// Search filter debounce.
        static let searchFilter: UInt64 = 160_000_000

        /// Layout-mutation persistence debounce.
        static let layoutPersist: UInt64 = 260_000_000

        /// Session-state persistence debounce.
        static let sessionPersist: UInt64 = 180_000_000
    }

    /// Geometry describing the "group onto this tile" hit-rectangle within a tile. A drop
    /// whose point falls inside this rectangle is treated as a grouping intent; outside it,
    /// as a reorder intent.
    enum Grouping {
        /// Compute the grouping rectangle within a tile of the given size.
        ///
        /// The rectangle is centered horizontally, biased slightly toward the icon (top)
        /// so that dropping on the label still behaves as a reorder.
        static func rect(in size: CGSize) -> CGRect {
            let width = min(84, size.width * 0.76)
            let height = min(90, size.height * 0.68)
            return CGRect(
                x: (size.width - width) * 0.5,
                y: 4,
                width: width,
                height: height
            )
        }
    }
}
