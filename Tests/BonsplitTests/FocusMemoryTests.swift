import CoreGraphics
import Testing
@testable import Bonsplit

@Suite("Pane focus memory")
@MainActor
struct FocusMemoryTests {
    /// Left pane beside a right column of top and bottom panes.
    private func makeColumnLayout() throws -> (BonsplitController, left: PaneID, top: PaneID, bottom: PaneID) {
        let controller = BonsplitController()
        let left = try #require(controller.focusedPaneId)
        let top = try #require(
            controller.splitPane(left, orientation: .horizontal, withTab: Tab(title: "Top"), insertFirst: false)
        )
        let bottom = try #require(
            controller.splitPane(top, orientation: .vertical, withTab: Tab(title: "Bottom"), insertFirst: false)
        )
        return (controller, left, top, bottom)
    }

    @Test("Moving back across an edge returns to the pane you came from")
    func roundTripReturnsToOrigin() throws {
        let (controller, left, top, bottom) = try makeColumnLayout()

        controller.focusPane(bottom)
        controller.navigateFocus(direction: .left)
        #expect(controller.focusedPaneId == left)
        controller.navigateFocus(direction: .right)
        #expect(controller.focusedPaneId == bottom)

        controller.focusPane(top)
        controller.navigateFocus(direction: .left)
        controller.navigateFocus(direction: .right)
        #expect(controller.focusedPaneId == top)
    }

    @Test("Memory holds across several columns")
    func memoryAcrossColumns() throws {
        let (controller, left, _, bottom) = try makeColumnLayout()
        // Split the left column so it holds two panes, then walk the rows.
        let leftBottom = try #require(
            controller.splitPane(left, orientation: .vertical, withTab: Tab(title: "LB"), insertFirst: false)
        )
        controller.focusPane(leftBottom)
        controller.navigateFocus(direction: .right)
        controller.navigateFocus(direction: .down)
        #expect(controller.focusedPaneId == bottom)
        controller.navigateFocus(direction: .left)
        #expect(controller.focusedPaneId == leftBottom)
    }

    @Test("Unfocused neighbors resolve by overlap, then layout order")
    func freshLayoutUsesOverlapThenOrder() throws {
        let controller = BonsplitController()
        let left = try #require(controller.focusedPaneId)
        let right = try #require(
            controller.splitPane(left, orientation: .horizontal, withTab: Tab(title: "R"), insertFirst: false)
        )
        let rightBottom = try #require(
            controller.splitPane(right, orientation: .vertical, withTab: Tab(title: "RB"), insertFirst: false)
        )
        _ = rightBottom
        let internalController = controller.internalController
        let fresh = SplitViewController(
            rootNode: internalController.rootNode,
            tabDragTransferRegistry: TabDragTransferRegistry()
        )
        #expect(fresh.adjacentPane(to: left, direction: .right) == right)

        // Give the bottom pane more overlap with the left pane.
        guard case .split(let root) = fresh.rootNode, case .split(let column) = root.second else {
            Issue.record("unexpected tree")
            return
        }
        column.dividerPosition = 0.3
        #expect(fresh.adjacentPane(to: left, direction: .right) == rightBottom)
    }

    @Test("Navigation never jumps past a column or diagonally")
    func requiresSharedEdge() throws {
        let (controller, left, top, _) = try makeColumnLayout()
        #expect(controller.adjacentPane(to: top, direction: .up) == nil)
        #expect(controller.adjacentPane(to: left, direction: .left) == nil)
        #expect(controller.adjacentPane(to: left, direction: .down) == nil)
    }

    @Test("Closing the focused pane returns to the last used pane")
    func closeReturnsToMostRecentPane() throws {
        let (controller, left, top, bottom) = try makeColumnLayout()
        controller.focusPane(left)
        controller.focusPane(top)
        controller.focusPane(bottom)

        // Top was used last before bottom.
        #expect(controller.closePane(bottom))
        #expect(controller.focusedPaneId == top)

        controller.focusPane(left)
        let extra = try #require(
            controller.splitPane(top, orientation: .vertical, withTab: Tab(title: "X"), insertFirst: false)
        )
        #expect(controller.focusedPaneId == extra)
        #expect(controller.closePane(extra))
        #expect(controller.focusedPaneId == left)
    }
}
