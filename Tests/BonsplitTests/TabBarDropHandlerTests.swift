import AppKit
@testable import Bonsplit
import XCTest

@MainActor
final class TabBarDropHandlerTests: XCTestCase {
    func testEarlierTabDropUsesResolvedMiddleIndex() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[0]
        let pasteboard = try makePasteboard(for: harness.pane.tabs[0], in: harness)
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[0], from: harness.pane.id)

        XCTAssertTrue(makeHandler(harness).performDrop(from: pasteboard, at: 3))
        XCTAssertEqual(harness.pane.tabs.map(\.id), [initialIds[1], initialIds[2], movedTabId, initialIds[3]])
    }

    func testLaterTabDropUsesResolvedMiddleIndex() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[3]
        let pasteboard = try makePasteboard(for: harness.pane.tabs[3], in: harness)
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[3], from: harness.pane.id)

        XCTAssertTrue(makeHandler(harness).performDrop(from: pasteboard, at: 1))
        XCTAssertEqual(harness.pane.tabs.map(\.id), [initialIds[0], movedTabId, initialIds[1], initialIds[2]])
    }

    func testCrossPaneDropUsesResolvedMiddleIndexInDestinationSplit() throws {
        let harness = try makeHarness()
        let sourcePane = harness.pane
        let movedTab = sourcePane.tabs[3]
        let targetPaneId = try XCTUnwrap(
            harness.controller.splitPane(sourcePane.id, orientation: .vertical)
        )
        _ = harness.controller.createTab(title: "Target First")
        _ = harness.controller.createTab(title: "Target Second")
        _ = harness.controller.createTab(title: "Target Third")
        let targetPane = try XCTUnwrap(
            harness.controller.internalController.paneState(for: targetPaneId)
        )
        let initialTargetIds = targetPane.tabs.map(\.id)
        let pasteboard = try makePasteboard(for: movedTab, sourcePane: sourcePane)
        _ = harness.controller.internalController.beginTabDrag(movedTab, from: sourcePane.id)

        XCTAssertTrue(makeHandler(controller: harness.controller, pane: targetPane).performDrop(
            from: pasteboard,
            at: 1
        ))
        XCTAssertEqual(
            targetPane.tabs.map(\.id),
            [initialTargetIds[0], movedTab.id, initialTargetIds[1], initialTargetIds[2]]
        )
        XCTAssertFalse(sourcePane.tabs.contains(where: { $0.id == movedTab.id }))
    }

    func testSamePaneReorderPreservesControllerMoveContract() throws {
        let harness = try makeHarness()
        let delegate = ReorderDelegateSpy()
        harness.controller.delegate = delegate
        let initialIds = harness.pane.tabs.map(\.id)
        let movedTabId = initialIds[3]
        let pasteboard = try makePasteboard(for: harness.pane.tabs[3], in: harness)
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[3], from: harness.pane.id)

        XCTAssertTrue(makeHandler(harness).performDrop(from: pasteboard, at: 1))

        let expectedOrder = [initialIds[0], movedTabId, initialIds[1], initialIds[2]]
        XCTAssertEqual(harness.pane.tabs.map(\.id), expectedOrder)
        XCTAssertEqual(harness.pane.selectedTabId, movedTabId)
        XCTAssertEqual(harness.controller.focusedPaneId, harness.pane.id)
        XCTAssertEqual(delegate.selectedTabIds, [TabID(id: movedTabId)])
        XCTAssertEqual(delegate.reorderedTabIds, expectedOrder.map { TabID(id: $0) })
        XCTAssertEqual(delegate.geometryChangeCount, 1)
    }

    func testDropIndicatorSuppressesSamePaneNoopTargets() throws {
        let harness = try makeHarness()
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[1], from: harness.pane.id)
        let handler = makeHandler(harness)

        XCTAssertNil(handler.indicatorIndex(for: 1))
        XCTAssertNil(handler.indicatorIndex(for: 2))
        XCTAssertEqual(handler.indicatorIndex(for: 0), 0)
        XCTAssertEqual(handler.indicatorIndex(for: 3), 3)
    }

    func testLiveDragIsAcceptedBeforePasteboardTypePublication() throws {
        let harness = try makeHarness()
        let emptyPasteboard = makeEmptyPasteboard()
        let initialIds = harness.pane.tabs.map(\.id)
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[3], from: harness.pane.id)

        XCTAssertEqual(makeHandler(harness).operation(for: emptyPasteboard), .move)
        XCTAssertTrue(makeHandler(harness).performDrop(from: emptyPasteboard, at: 1))
        XCTAssertEqual(
            harness.pane.tabs.map(\.id),
            [initialIds[0], initialIds[3], initialIds[1], initialIds[2]]
        )
    }

    func testFileOnlyDropIgnoresStaleLiveTabDrag() throws {
        let harness = try makeHarness()
        let initialIds = harness.pane.tabs.map(\.id)
        let pasteboard = makeEmptyPasteboard()
        let fileURL = URL(fileURLWithPath: "/tmp/bonsplit-tab-drop-handler-file")
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[3], from: harness.pane.id)

        var receivedURLs: [URL] = []
        harness.controller.onExternalFileDrop = { request in
            receivedURLs = request.urls
            return true
        }

        XCTAssertEqual(makeHandler(harness).operation(for: pasteboard), .copy)
        XCTAssertTrue(makeHandler(harness).performDrop(from: pasteboard, at: 1))
        XCTAssertEqual(receivedURLs, [fileURL])
        XCTAssertEqual(harness.pane.tabs.map(\.id), initialIds)
    }

    func testInactiveControllerRejectsLiveDrag() throws {
        let harness = try makeHarness()
        let emptyPasteboard = makeEmptyPasteboard()
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[1], from: harness.pane.id)
        harness.controller.isInteractive = false

        XCTAssertEqual(makeHandler(harness).operation(for: emptyPasteboard), [])
    }

    func testDestinationCapturesOnlyCompatibleDragEvents() {
        XCTAssertTrue(TabBarDropDestinationNSView.shouldCaptureHitTest(
            eventType: .leftMouseDragged,
            pasteboardTypes: nil,
            hasLocalTabDrag: true
        ))
        XCTAssertFalse(TabBarDropDestinationNSView.shouldCaptureHitTest(
            eventType: .leftMouseDown,
            pasteboardTypes: [TabBarDropHandler.tabTransferPasteboardType],
            hasLocalTabDrag: true
        ))
        XCTAssertFalse(TabBarDropDestinationNSView.shouldCaptureHitTest(
            eventType: .leftMouseDragged,
            pasteboardTypes: nil
        ))
    }

    func testTranslatedDestinationHitTestsInSuperviewCoordinates() throws {
        let harness = try makeHarness()
        _ = harness.controller.internalController.beginTabDrag(harness.pane.tabs[1], from: harness.pane.id)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        let destination = TabBarDropDestinationNSView(
            frame: NSRect(x: 240, y: 20, width: 200, height: 34)
        )
        destination.pane = harness.pane
        destination.bonsplitController = harness.controller
        destination.splitViewController = harness.controller.internalController
        container.addSubview(destination)

        XCTAssertTrue(container.hitTest(NSPoint(x: 260, y: 30)) === destination)
        XCTAssertFalse(container.hitTest(NSPoint(x: 20, y: 30)) === destination)
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

    private func makeHandler(_ harness: Harness) -> TabBarDropHandler {
        makeHandler(controller: harness.controller, pane: harness.pane)
    }

    private func makeHandler(controller: BonsplitController, pane: PaneState) -> TabBarDropHandler {
        TabBarDropHandler(
            pane: pane,
            bonsplitController: controller,
            splitViewController: controller.internalController
        )
    }

    private func makeEmptyPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TabBarDropHandlerTests.\(UUID().uuidString)")
        )
        _ = pasteboard.clearContents()
        return pasteboard
    }

    private func makePasteboard(for tab: TabItem, in harness: Harness) throws -> NSPasteboard {
        try makePasteboard(for: tab, sourcePane: harness.pane)
    }

    private func makePasteboard(for tab: TabItem, sourcePane: PaneState) throws -> NSPasteboard {
        let pasteboard = makeEmptyPasteboard()
        let transfer = TabTransferData(tab: tab, sourcePaneId: sourcePane.id.id)
        let data = try JSONEncoder().encode(transfer)
        XCTAssertTrue(pasteboard.setData(data, forType: TabBarDropHandler.tabTransferPasteboardType))
        return pasteboard
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
