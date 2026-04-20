import Foundation
import XCTest
@testable import LaunchDeck

final class EdgePageScrollerTests: XCTestCase {
    func testFirstHoverNeverFlipsEvenIfDwellExceeded() {
        var scroller = EdgePageScroller()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertFalse(scroller.hover(direction: 1, now: t0))
    }

    func testNoFlipBeforeInitialDwell() {
        var scroller = EdgePageScroller()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = scroller.hover(direction: 1, now: t0)
        XCTAssertFalse(
            scroller.hover(direction: 1, now: t0.addingTimeInterval(LauncherTuning.EdgePaging.initialDwell - 0.01))
        )
    }

    func testFlipsOnceDwellAndDynamicIntervalBothSatisfied() {
        // First flip has to clear both the dwell floor *and* the dynamic rate-limit since
        // `lastFlipAt` is bootstrapped to the hover-start moment. With the default tuning
        // (dwell 0.20, base 0.34, slope 0.22) the equation `elapsed == 0.34 - 0.22*elapsed`
        // gives ≈ 0.28s; we pad slightly above to avoid float equality jitter.
        var scroller = EdgePageScroller()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = scroller.hover(direction: 1, now: t0)
        XCTAssertFalse(scroller.hover(direction: 1, now: t0.addingTimeInterval(0.25)))
        XCTAssertTrue(scroller.hover(direction: 1, now: t0.addingTimeInterval(0.30)))
    }

    func testDirectionChangeRestartsDwell() {
        var scroller = EdgePageScroller()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = scroller.hover(direction: 1, now: t0)
        _ = scroller.hover(direction: 1, now: t0.addingTimeInterval(0.5))
        // Switching to -1 resets the state; the very next hover must not flip.
        XCTAssertFalse(scroller.hover(direction: -1, now: t0.addingTimeInterval(0.6)))
    }

    func testResetDiscardsState() {
        var scroller = EdgePageScroller()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = scroller.hover(direction: 1, now: t0)
        _ = scroller.hover(direction: 1, now: t0.addingTimeInterval(0.5))
        scroller.reset()
        XCTAssertFalse(scroller.hover(direction: 1, now: t0.addingTimeInterval(0.6)))
    }

    func testAccelerationReducesIntervalBetweenFlips() {
        // The tunable formula is `dynamic = max(minimumInterval, baseInterval - hoverElapsed * accelerationSlope)`.
        // The knee (where `dynamic == minimumInterval`) sits at
        // `hoverElapsed = (baseInterval - minimumInterval) / accelerationSlope`; after that
        // point the interval floor rules and `minimumInterval + epsilon` is enough to flip.
        let tuning = LauncherTuning.EdgePaging.self
        let knee = (tuning.baseInterval - tuning.minimumInterval) / tuning.accelerationSlope

        var scroller = EdgePageScroller()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = scroller.hover(direction: 1, now: t0)
        XCTAssertTrue(scroller.hover(direction: 1, now: t0.addingTimeInterval(0.30)))

        var lastFlipTime = t0.addingTimeInterval(max(0.30, knee + 0.05))
        // Prime the scroller past the knee.
        _ = scroller.hover(direction: 1, now: lastFlipTime)

        for _ in 0..<3 {
            let next = lastFlipTime.addingTimeInterval(tuning.minimumInterval + 0.01)
            XCTAssertTrue(scroller.hover(direction: 1, now: next))
            lastFlipTime = next
        }
    }
}
