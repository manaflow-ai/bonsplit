import AppKit
@testable import Bonsplit
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@MainActor
final class TabDropDelegateSamePaneFallbackTests: XCTestCase {
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
                newTabPosition: .end,
                allowTabReordering: true,
                allowCrossPaneTabMove: true
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
        writeTransferToDragPasteboard(tab: tab, sourcePaneId: harness.pane.id.id)

        var dropTargetIndex: Int?
        var dropLifecycle: TabDropLifecycle = .hovering
        let delegate = TabDropDelegate(
            targetIndex: targetIndex,
            pane: harness.pane,
            bonsplitController: harness.controller,
            controller: harness.controller.internalController,
            dropTargetIndex: Binding(
                get: { dropTargetIndex },
                set: { dropTargetIndex = $0 }
            ),
            dropLifecycle: Binding(
                get: { dropLifecycle },
                set: { dropLifecycle = $0 }
            )
        )

        return delegate.performDrop(info: FakeDropInfo())
    }

    private func writeTransferToDragPasteboard(tab: TabItem, sourcePaneId: UUID) {
        let pasteboard = NSPasteboard(name: .drag)
        pasteboard.clearContents()
        let transfer = TabTransferData(tab: tab, sourcePaneId: sourcePaneId)
        let data = try! JSONEncoder().encode(transfer)
        pasteboard.setData(
            data,
            forType: NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
        )
    }
}

@MainActor
private struct Harness {
    let controller: BonsplitController
    let pane: PaneState
}

private struct FakeDropInfo: DropInfo {
    var location: CGPoint { .zero }

    func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] {
        []
    }

    func hasItemsConforming(to contentTypes: [UTType]) -> Bool {
        contentTypes.contains(.tabTransfer)
    }
}
