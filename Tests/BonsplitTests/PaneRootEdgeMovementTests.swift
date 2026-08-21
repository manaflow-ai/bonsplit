import Foundation
import Testing
@testable import Bonsplit

@Suite("Pane movement to a root edge")
@MainActor
struct PaneRootEdgeMovementTests {
    @Test(
        "A nested pane becomes the requested root child without losing identity",
        arguments: [
            RootSplitEdge.left,
            RootSplitEdge.right,
            RootSplitEdge.above,
            RootSplitEdge.below,
        ]
    )
    func promotesNestedPane(edge: RootSplitEdge) throws {
        let fixture = try Fixture()

        let moved = fixture.controller.movePane(
            fixture.targetPaneID,
            toRootEdge: edge
        )

        #expect(moved)
        #expect(fixture.controller.focusedPaneId == fixture.targetPaneID)
        #expect(fixture.controller.allPaneIds == edge.expectedPaneOrder(
            remainder: fixture.remainderPaneIDs,
            moved: fixture.targetPaneID
        ))
        #expect(
            fixture.controller.tabs(inPane: fixture.targetPaneID).map(\.id)
                == fixture.targetTabIDs
        )
        #expect(
            fixture.controller.selectedTabId(inPane: fixture.targetPaneID)
                == fixture.selectedTargetTabID
        )
        for tabID in fixture.targetTabIDs {
            #expect(fixture.controller.paneId(containing: tabID) == fixture.targetPaneID)
        }

        let root = try #require(fixture.controller.treeSnapshot().split)
        #expect(root.orientation == edge.expectedOrientation)
        #expect(root.dividerPosition == 0.5)
        #expect(root.imposedFirstExtent == nil)
        #expect(root.movedPaneID(on: edge) == fixture.targetPaneID.description)

        let remainder = root.remainder(on: edge)
        let preservedRoot = try #require(remainder.split)
        #expect(preservedRoot.id == fixture.remainderRootID)
        #expect(preservedRoot.dividerPosition == fixture.remainderRootDivider)
        #expect(remainder.paneIDs == fixture.remainderPaneIDs.map(\.description))
    }

    @Test("A successful move clears zoom and publishes focus and geometry once")
    func successfulMovePublishesOnce() throws {
        let fixture = try Fixture()
        let delegate = RecordingDelegate()
        fixture.controller.delegate = delegate
        #expect(fixture.controller.togglePaneZoom(inPane: fixture.targetPaneID))

        #expect(fixture.controller.movePane(fixture.targetPaneID, toRootEdge: .right))

        #expect(fixture.controller.zoomedPaneId == nil)
        #expect(delegate.focusedPaneIDs == [fixture.targetPaneID])
        #expect(delegate.geometryChangeCount == 1)
    }

    @Test("A pane already spanning the requested edge is a complete no-op")
    func alreadyAtRequestedEdgeIsNoOp() throws {
        let controller = BonsplitController()
        let leftPaneID = try #require(controller.focusedPaneId)
        let rightPaneID = try #require(
            controller.splitPane(
                leftPaneID,
                orientation: .horizontal,
                withTab: Tab(title: "Right")
            )
        )
        #expect(controller.togglePaneZoom(inPane: rightPaneID))
        let treeBefore = controller.treeSnapshot()
        let delegate = RecordingDelegate()
        controller.delegate = delegate

        #expect(!controller.movePane(rightPaneID, toRootEdge: .right))

        #expect(controller.treeSnapshot() == treeBefore)
        #expect(controller.focusedPaneId == rightPaneID)
        #expect(controller.zoomedPaneId == rightPaneID)
        #expect(delegate.focusedPaneIDs.isEmpty)
        #expect(delegate.geometryChangeCount == 0)
    }

    @Test("A direct root child can move across to the opposite edge")
    func reordersDirectRootChildren() throws {
        let controller = BonsplitController()
        let leftPaneID = try #require(controller.focusedPaneId)
        let rightPaneID = try #require(
            controller.splitPane(
                leftPaneID,
                orientation: .horizontal,
                withTab: Tab(title: "Right")
            )
        )

        #expect(controller.movePane(leftPaneID, toRootEdge: .right))

        let root = try #require(controller.treeSnapshot().split)
        #expect(root.first.pane?.id == rightPaneID.description)
        #expect(root.second.pane?.id == leftPaneID.description)
        #expect(controller.focusedPaneId == leftPaneID)
    }

    @Test("Invalid, single-pane, and disabled-split moves do not mutate state")
    func rejectsUnavailableMoves() throws {
        let single = BonsplitController()
        let onlyPaneID = try #require(single.focusedPaneId)
        let singleTree = single.treeSnapshot()
        #expect(!single.movePane(onlyPaneID, toRootEdge: .left))
        #expect(!single.movePane(PaneID(), toRootEdge: .right))
        #expect(single.treeSnapshot() == singleTree)

        let fixture = try Fixture()
        let treeBefore = fixture.controller.treeSnapshot()
        fixture.controller.configuration.allowSplits = false
        #expect(!fixture.controller.movePane(fixture.targetPaneID, toRootEdge: .above))
        #expect(fixture.controller.treeSnapshot() == treeBefore)
    }
}

@MainActor
private extension PaneRootEdgeMovementTests {
    struct Fixture {
        let controller: BonsplitController
        let targetPaneID: PaneID
        let targetTabIDs: [TabID]
        let selectedTargetTabID: TabID
        let remainderPaneIDs: [PaneID]
        let remainderRootID: String
        let remainderRootDivider: Double

        @MainActor
        init() throws {
            let controller = BonsplitController(
                configuration: BonsplitConfiguration(newTabPosition: .end)
            )
            let leftPaneID = try #require(controller.focusedPaneId)
            let rightTopPaneID = try #require(
                controller.splitPane(
                    leftPaneID,
                    orientation: .horizontal,
                    withTab: Tab(title: "Right top"),
                    initialDividerPosition: 0.3
                )
            )
            let targetPaneID = try #require(
                controller.splitPane(
                    rightTopPaneID,
                    orientation: .vertical,
                    withTab: Tab(title: "Target one"),
                    initialDividerPosition: 0.7
                )
            )
            let targetTabID = try #require(controller.tabs(inPane: targetPaneID).only?.id)
            let selectedTargetTabID = try #require(
                controller.createTab(title: "Target two", inPane: targetPaneID)
            )
            controller.selectTab(selectedTargetTabID)

            let originalRoot = try #require(controller.treeSnapshot().split)
            self.controller = controller
            self.targetPaneID = targetPaneID
            self.targetTabIDs = [targetTabID, selectedTargetTabID]
            self.selectedTargetTabID = selectedTargetTabID
            self.remainderPaneIDs = [leftPaneID, rightTopPaneID]
            self.remainderRootID = originalRoot.id
            self.remainderRootDivider = originalRoot.dividerPosition
        }
    }
}

@MainActor
private final class RecordingDelegate: BonsplitDelegate {
    var focusedPaneIDs: [PaneID] = []
    var geometryChangeCount = 0

    func splitTabBar(
        _ controller: BonsplitController,
        didFocusPane pane: PaneID
    ) {
        focusedPaneIDs.append(pane)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didChangeGeometry snapshot: LayoutSnapshot
    ) {
        geometryChangeCount += 1
    }
}

private extension RootSplitEdge {
    var expectedOrientation: String {
        switch self {
        case .left, .right: "horizontal"
        case .above, .below: "vertical"
        }
    }

    func expectedPaneOrder(
        remainder: [PaneID],
        moved: PaneID
    ) -> [PaneID] {
        switch self {
        case .left, .above: [moved] + remainder
        case .right, .below: remainder + [moved]
        }
    }
}

private extension ExternalTreeNode {
    var pane: ExternalPaneNode? {
        guard case .pane(let pane) = self else { return nil }
        return pane
    }

    var split: ExternalSplitNode? {
        guard case .split(let split) = self else { return nil }
        return split
    }

    var paneIDs: [String] {
        switch self {
        case .pane(let pane): [pane.id]
        case .split(let split): split.first.paneIDs + split.second.paneIDs
        }
    }
}

private extension ExternalSplitNode {
    func movedPaneID(on edge: RootSplitEdge) -> String? {
        switch edge {
        case .left, .above: first.pane?.id
        case .right, .below: second.pane?.id
        }
    }

    func remainder(on edge: RootSplitEdge) -> ExternalTreeNode {
        switch edge {
        case .left, .above: second
        case .right, .below: first
        }
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
