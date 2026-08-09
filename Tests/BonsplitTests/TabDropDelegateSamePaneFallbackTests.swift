@testable import Bonsplit
import XCTest

@MainActor
final class TabDropDelegateSamePaneFallbackTests: XCTestCase {
    func testEarlierTabSwiftUIDropUsesMiddleTargetFromDelegate() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[0]

        let targetIndex = try XCTUnwrap(swiftUISamePaneDropTarget(
            tabId: movedTabId,
            targetIndex: 3,
            harness: harness
        ))

        XCTAssertEqual(targetIndex, 3)
        XCTAssertTrue(TabDropDelegate.performSamePaneReorder(
            tabId: movedTabId,
            targetIndex: targetIndex,
            pane: harness.pane,
            bonsplitController: harness.controller
        ))
        XCTAssertEqual(harness.pane.tabs.map(\.id), [initialIds[1], initialIds[2], movedTabId, initialIds[3]])
    }

    func testLaterTabSwiftUIDropUsesMiddleTargetFromDelegate() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[3]

        let targetIndex = try XCTUnwrap(swiftUISamePaneDropTarget(
            tabId: movedTabId,
            targetIndex: 1,
            harness: harness
        ))

        XCTAssertEqual(targetIndex, 1)
        XCTAssertTrue(TabDropDelegate.performSamePaneReorder(
            tabId: movedTabId,
            targetIndex: targetIndex,
            pane: harness.pane,
            bonsplitController: harness.controller
        ))
        XCTAssertEqual(harness.pane.tabs.map(\.id), [initialIds[0], movedTabId, initialIds[1], initialIds[2]])
    }

    func testSamePaneReorderPreservesControllerMoveContract() throws {
        let harness = try makeHarness()
        let delegate = ReorderDelegateSpy()
        harness.controller.delegate = delegate
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[3]

        XCTAssertTrue(TabDropDelegate.performSamePaneReorder(
            tabId: movedTabId,
            targetIndex: 1,
            pane: harness.pane,
            bonsplitController: harness.controller
        ))

        let expectedOrder = [initialIds[0], movedTabId, initialIds[1], initialIds[2]]
        XCTAssertEqual(harness.pane.tabs.map(\.id), expectedOrder)
        XCTAssertEqual(harness.pane.selectedTabId, movedTabId)
        XCTAssertEqual(harness.controller.focusedPaneId, harness.pane.id)
        XCTAssertEqual(delegate.selectedTabIds, [TabID(id: movedTabId)])
        XCTAssertEqual(delegate.reorderedTabIds, expectedOrder.map { TabID(id: $0) })
        XCTAssertEqual(delegate.geometryChangeCount, 1)
    }

    func testSwiftUIDropSuppressesSamePaneNoopTargets() throws {
        let harness = try makeHarness()
        let movedTabId = harness.pane.tabs[1].id

        XCTAssertNil(swiftUISamePaneDropTarget(tabId: movedTabId, targetIndex: 1, harness: harness))
        XCTAssertNil(swiftUISamePaneDropTarget(tabId: movedTabId, targetIndex: 2, harness: harness))
        XCTAssertEqual(swiftUISamePaneDropTarget(tabId: movedTabId, targetIndex: 0, harness: harness), 0)
        XCTAssertEqual(swiftUISamePaneDropTarget(tabId: movedTabId, targetIndex: 3, harness: harness), 3)
    }

    private func makeHarness() throws -> Harness {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(
                allowTabReordering: true,
                allowCrossPaneTabMove: true,
                newTabPosition: .end
            )
        )
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        _ = controller.createTab(title: "Second")
        _ = controller.createTab(title: "Third")
        _ = controller.createTab(title: "Fourth")
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))
        XCTAssertEqual(pane.tabs.count, 4)
        return Harness(controller: controller, pane: pane)
    }

    private func swiftUISamePaneDropTarget(
        tabId: UUID,
        targetIndex: Int,
        harness: Harness
    ) -> Int? {
        let sourceIndex = harness.pane.tabs.firstIndex { $0.id == tabId }!
        return TabDropDelegate.samePaneDropTarget(sourceIndex: sourceIndex, targetIndex: targetIndex)
    }
}

@MainActor
private struct Harness {
    let controller: BonsplitController
    let pane: PaneState
}

@MainActor
private final class ReorderDelegateSpy: BonsplitDelegate {
    var selectedTabIds: [TabID] = []
    var reorderedTabIds: [TabID] = []
    var geometryChangeCount = 0

    func splitTabBar(_ controller: BonsplitController, didSelectTab tab: Tab, inPane pane: PaneID) {
        selectedTabIds.append(tab.id)
    }

    func splitTabBar(_ controller: BonsplitController, didReorderTabsInPane pane: PaneID, orderedTabIds: [TabID]) {
        reorderedTabIds = orderedTabIds
    }

    func splitTabBar(_ controller: BonsplitController, didChangeGeometry snapshot: LayoutSnapshot) {
        geometryChangeCount += 1
    }
}
