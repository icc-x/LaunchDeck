import XCTest
@testable import LaunchDeck

final class LauncherPagingTests: XCTestCase {
    func testChunkedSplitsIntoStablePages() {
        let pages = LauncherPaging.chunked(Array(0..<7), pageSize: 3)

        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(Array(pages[0]), [0, 1, 2])
        XCTAssertEqual(Array(pages[1]), [3, 4, 5])
        XCTAssertEqual(Array(pages[2]), [6])
    }

    func testChunkedReturnsSingleSliceWhenPageSizeIsNonPositive() {
        let pages = LauncherPaging.chunked(Array(0..<4), pageSize: 0)

        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(Array(pages[0]), [0, 1, 2, 3])
    }
}
