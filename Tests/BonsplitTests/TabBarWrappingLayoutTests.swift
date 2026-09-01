import XCTest
@testable import Bonsplit

final class TabBarWrappingLayoutTests: XCTestCase {
    func testItemsWrapIntoRowsWhenNaturalWidthsOverflow() {
        let result = TabBarWrapLayoutMetrics.arrangement(
            sizes: [
                CGSize(width: 120, height: 30),
                CGSize(width: 120, height: 30),
                CGSize(width: 120, height: 30),
            ],
            availableWidth: 250,
            horizontalSpacing: 0,
            verticalSpacing: 0
        )

        XCTAssertEqual(result.rowCount, 2)
        XCTAssertEqual(result.size.height, 60, accuracy: 0.001)
        XCTAssertEqual(result.frames[0].minY, 0, accuracy: 0.001)
        XCTAssertEqual(result.frames[1].minY, 0, accuracy: 0.001)
        XCTAssertEqual(result.frames[2].minY, 30, accuracy: 0.001)
    }

    func testItemsStayOnOneRowWhenTheyFit() {
        let result = TabBarWrapLayoutMetrics.arrangement(
            sizes: [
                CGSize(width: 120, height: 30),
                CGSize(width: 120, height: 30),
            ],
            availableWidth: 250,
            horizontalSpacing: 0,
            verticalSpacing: 0
        )

        XCTAssertEqual(result.rowCount, 1)
        XCTAssertEqual(result.size, CGSize(width: 250, height: 30))
        XCTAssertEqual(result.frames.map(\.minX), [0, 120])
    }

    func testAnItemWiderThanTheViewportIsClampedToTheViewport() {
        let result = TabBarWrapLayoutMetrics.arrangement(
            sizes: [CGSize(width: 400, height: 30)],
            availableWidth: 250,
            horizontalSpacing: 0,
            verticalSpacing: 0
        )

        XCTAssertEqual(result.rowCount, 1)
        XCTAssertEqual(result.frames[0].width, 250, accuracy: 0.001)
        XCTAssertEqual(result.size.width, 250, accuracy: 0.001)
    }
}
