import XCTest
@testable import Bonsplit

/// The top-trailing pane owns the host's reserved tab-bar trailing inset.
@MainActor
final class TopTrailingPaneTests: XCTestCase {
    func testSinglePaneIsTopTrailing() throws {
        let controller = BonsplitController()
        let pane = try XCTUnwrap(controller.allPaneIds.first)
        XCTAssertEqual(controller.internalController.rootNode.topTrailingPaneId, pane)
    }

    func testSideBySideSplitUsesTrailingPane() throws {
        let controller = BonsplitController()
        let leading = try XCTUnwrap(controller.allPaneIds.first)
        let trailing = try XCTUnwrap(controller.splitPane(leading, orientation: .horizontal))
        XCTAssertEqual(controller.internalController.rootNode.topTrailingPaneId, trailing)
    }

    func testStackedSplitUsesTopPane() throws {
        let controller = BonsplitController()
        let top = try XCTUnwrap(controller.allPaneIds.first)
        _ = try XCTUnwrap(controller.splitPane(top, orientation: .vertical))
        XCTAssertEqual(controller.internalController.rootNode.topTrailingPaneId, top)
    }

    func testNestedSplitUsesTopOfTrailingColumn() throws {
        let controller = BonsplitController()
        let leading = try XCTUnwrap(controller.allPaneIds.first)
        let trailingTop = try XCTUnwrap(controller.splitPane(leading, orientation: .horizontal))
        _ = try XCTUnwrap(controller.splitPane(trailingTop, orientation: .vertical))
        XCTAssertEqual(controller.internalController.rootNode.topTrailingPaneId, trailingTop)
    }
}
