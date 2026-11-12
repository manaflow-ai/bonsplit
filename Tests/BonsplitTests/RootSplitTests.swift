import XCTest
@testable import Bonsplit

@MainActor
final class RootSplitTests: XCTestCase {
    func testRootSplitAddsPaneBesideEntireExistingTree() throws {
        let controller = BonsplitController(configuration: BonsplitConfiguration(
            dividerPositionRange: 0...1
        ))
        let originalPane = try XCTUnwrap(controller.allPaneIds.first)
        _ = try XCTUnwrap(controller.splitPane(originalPane, orientation: .vertical))
        let originalTree = controller.treeSnapshot()

        let newPane = try XCTUnwrap(controller.splitRoot(
            orientation: .horizontal,
            withTab: .init(title: "root split"),
            insertFirst: false
        ))

        guard case .split(let root) = controller.treeSnapshot() else {
            return XCTFail("Expected root split")
        }
        guard case .split = root.first else {
            return XCTFail("Expected the previous tree to remain intact")
        }
        guard case .pane(let created) = root.second else {
            return XCTFail("Expected the new root sibling to be a pane")
        }
        guard case .split = originalTree else {
            return XCTFail("Expected the setup tree to be nested")
        }
        XCTAssertEqual(created.id, newPane.id.uuidString)
        XCTAssertEqual(root.orientation, "horizontal")
        XCTAssertEqual(root.dividerPosition, 0.5, accuracy: 0.0001)
    }
}
