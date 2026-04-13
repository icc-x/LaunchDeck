import AppKit

enum WheelPageResolver {
    static func targetPage(
        currentPage: Int,
        pageCount: Int,
        event: NSEvent,
        threshold: CGFloat = 3.0
    ) -> Int? {
        guard pageCount > 1 else { return nil }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY

        if abs(deltaY) >= abs(deltaX), abs(deltaY) > threshold {
            if deltaY < 0, currentPage < pageCount - 1 {
                return currentPage + 1
            }
            if deltaY > 0, currentPage > 0 {
                return currentPage - 1
            }
            return nil
        }

        if abs(deltaX) > threshold {
            if deltaX > 0, currentPage > 0 {
                return currentPage - 1
            }
            if deltaX < 0, currentPage < pageCount - 1 {
                return currentPage + 1
            }
        }

        return nil
    }
}
