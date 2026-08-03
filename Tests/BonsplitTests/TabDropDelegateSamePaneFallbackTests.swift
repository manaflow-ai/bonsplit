@testable import Bonsplit
import XCTest

@MainActor
final class TabDropDelegateSamePaneFallbackTests: XCTestCase {
    func testEarlierTabLocalDropUsesManualMiddleIndexInsteadOfStaticEndTarget() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[0]

        let targetIndex = effectiveSamePaneLocalDropTarget(
            tabId: movedTabId,
            staticTargetIndex: harness.pane.tabs.count,
            manualTargetIndex: 3,
            harness: harness
        )

        XCTAssertEqual(targetIndex, 3)
        XCTAssertTrue(harness.controller.reorderTab(TabID(uuid: movedTabId), toIndex: targetIndex))
        XCTAssertEqual(harness.pane.tabs.map(\.id), [initialIds[1], initialIds[2], movedTabId, initialIds[3]])
    }

    func testLaterActiveTabLocalDropUsesManualMiddleIndexInsteadOfStaticEndNoop() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[3]

        let targetIndex = effectiveSamePaneLocalDropTarget(
            tabId: movedTabId,
            staticTargetIndex: harness.pane.tabs.count,
            manualTargetIndex: 1,
            harness: harness
        )

        XCTAssertEqual(targetIndex, 1)
        XCTAssertTrue(harness.controller.reorderTab(TabID(uuid: movedTabId), toIndex: targetIndex))
        XCTAssertEqual(harness.pane.tabs.map(\.id), [initialIds[0], movedTabId, initialIds[1], initialIds[2]])
    }

    func testEarlierTabManualMiddleReorderIgnoresStaleSamePaneEndFallback() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[0]

        XCTAssertTrue(harness.controller.reorderTab(TabID(uuid: movedTabId), toIndex: 3))
        let expectedMiddleOrder = [initialIds[1], initialIds[2], movedTabId, initialIds[3]]
        XCTAssertEqual(harness.pane.tabs.map(\.id), expectedMiddleOrder)

        let handled = performStaleSamePaneFallbackDrop(
            tabId: movedTabId,
            targetIndex: harness.pane.tabs.count,
            harness: harness
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(harness.pane.tabs.map(\.id), expectedMiddleOrder)
    }

    func testLaterTabManualMiddleReorderIgnoresStaleSamePaneEndFallback() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[3]

        XCTAssertTrue(harness.controller.reorderTab(TabID(uuid: movedTabId), toIndex: 1))
        let expectedMiddleOrder = [initialIds[0], movedTabId, initialIds[1], initialIds[2]]
        XCTAssertEqual(harness.pane.tabs.map(\.id), expectedMiddleOrder)

        let handled = performStaleSamePaneFallbackDrop(
            tabId: movedTabId,
            targetIndex: harness.pane.tabs.count,
            harness: harness
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(harness.pane.tabs.map(\.id), expectedMiddleOrder)
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
        controller.onExternalTabDrop = { request in
            guard case .insert(let targetPane, let targetIndex) = request.destination else {
                return false
            }
            return controller.moveTab(request.tabId, toPane: targetPane, atIndex: targetIndex)
        }
        return Harness(controller: controller, pane: pane)
    }

    private func performStaleSamePaneFallbackDrop(
        tabId: UUID,
        targetIndex: Int,
        harness: Harness
    ) -> Bool {
        let tab = harness.pane.tabs.first { $0.id == tabId }!
        let transfer = TabTransferData(tab: tab, sourcePaneId: harness.pane.id.id)
        guard let request = TabDropDelegate.sameProcessFallbackRequest(
            transfer: transfer,
            targetPane: harness.pane.id,
            targetIndex: targetIndex,
            allowCrossPaneTabMove: harness.controller.configuration.allowCrossPaneTabMove
        ) else {
            return false
        }
        return harness.controller.onExternalTabDrop?(request) ?? false
    }

    private func effectiveSamePaneLocalDropTarget(
        tabId: UUID,
        staticTargetIndex: Int,
        manualTargetIndex: Int,
        harness: Harness
    ) -> Int {
        let sourceIndex = harness.pane.tabs.firstIndex { $0.id == tabId }
        return TabDropDelegate.effectiveLocalDropTargetIndex(
            staticTargetIndex: staticTargetIndex,
            manualTargetIndex: manualTargetIndex,
            sourcePaneMatchesTarget: true,
            sourceIndex: sourceIndex
        )
    }
}

@MainActor
private struct Harness {
    let controller: BonsplitController
    let pane: PaneState
}
