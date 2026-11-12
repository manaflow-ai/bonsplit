import AppKit
@testable import Bonsplit
import XCTest

/// A dropped tab settles into its slot: the drop asks AppKit to slide the
/// drag image to where the tab lands instead of letting it vanish under the
/// pointer while the tab appears elsewhere at once.
@MainActor
final class TabDropSettleTests: XCTestCase {
    func testLaterTabDroppedEarlierSlidesToTheSlotItTakes() throws {
        let strip = try makeStrip()
        let moved = strip.pane.tabs[3]
        let splits = strip.controller.internalController
        let generation = splits.beginTabDrag(moved, from: strip.pane.id)
        // Over the second tab's leading half: insertion index 1.
        let drop = try makeDrop(for: moved, at: NSPoint(x: 110, y: 15), in: strip)

        XCTAssertTrue(strip.destination.performDragOperation(drop))

        XCTAssertEqual(strip.pane.tabs.firstIndex(where: { $0.id == moved.id }), 1)
        XCTAssertTrue(drop.animatesToDestination)
        XCTAssertEqual(drop.item.draggingFrame, NSRect(x: 100, y: 0, width: 100, height: 30))
        // The tab shows in its slot once the image has landed, not before.
        XCTAssertEqual(splits.settlingTabId, moved.id)
        splits.nativeTabDragSessionDidEnd(generation: generation)
        XCTAssertNil(splits.settlingTabId)
    }

    func testUnpinnedTabDroppedAmongPinnedTabsSlidesToWhereThePaneKeepsIt() throws {
        let strip = try makeStrip()
        strip.pane.tabs[0].isPinned = true
        strip.pane.tabs[1].isPinned = true
        let moved = strip.pane.tabs[3]
        _ = strip.controller.internalController.beginTabDrag(moved, from: strip.pane.id)
        // Dropped between the two pinned tabs: the pane keeps it after them.
        let drop = try makeDrop(for: moved, at: NSPoint(x: 110, y: 15), in: strip)

        XCTAssertTrue(strip.destination.performDragOperation(drop))

        XCTAssertEqual(strip.pane.tabs.firstIndex(where: { $0.id == moved.id }), 2)
        XCTAssertTrue(drop.animatesToDestination)
        XCTAssertEqual(drop.item.draggingFrame, NSRect(x: 200, y: 0, width: 100, height: 30))
    }

    func testReduceMotionDropLandsAtOnce() throws {
        let strip = try makeStrip()
        strip.destination.reducesMotion = { true }
        let moved = strip.pane.tabs[3]
        _ = strip.controller.internalController.beginTabDrag(moved, from: strip.pane.id)
        let drop = try makeDrop(for: moved, at: NSPoint(x: 110, y: 15), in: strip)

        XCTAssertTrue(strip.destination.performDragOperation(drop))

        XCTAssertEqual(strip.pane.tabs.firstIndex(where: { $0.id == moved.id }), 1)
        XCTAssertFalse(drop.animatesToDestination)
        XCTAssertNil(strip.controller.internalController.settlingTabId)
    }

    func testEarlierTabDroppedLaterSlidesToTheSlotItTakes() throws {
        let strip = try makeStrip()
        let moved = strip.pane.tabs[0]
        _ = strip.controller.internalController.beginTabDrag(moved, from: strip.pane.id)
        // Over the fourth tab's leading half: insertion index 3, so the tab
        // lands third, where the third tab ends once the tabs between move up.
        let drop = try makeDrop(for: moved, at: NSPoint(x: 310, y: 15), in: strip)

        XCTAssertTrue(strip.destination.performDragOperation(drop))

        XCTAssertEqual(strip.pane.tabs.firstIndex(where: { $0.id == moved.id }), 2)
        XCTAssertTrue(drop.animatesToDestination)
        XCTAssertEqual(drop.item.draggingFrame, NSRect(x: 200, y: 0, width: 100, height: 30))
    }

    // MARK: Harness

    private struct Strip {
        let window: NSWindow
        let controller: BonsplitController
        let pane: PaneState
        let registry: TabDragTransferRegistry
        let geometry: TabBarItemGeometryRegistry
        let destination: TabBarDropDestinationNSView
    }

    /// Four 100-wide tabs in a 400-wide strip, each tab view registered as
    /// the strip registers its live tab items.
    private func makeStrip() throws -> Strip {
        let registry = TabDragTransferRegistry()
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(
                allowTabReordering: true,
                allowCrossPaneTabMove: true,
                newTabPosition: .end
            ),
            tabDragTransferRegistry: registry
        )
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        _ = controller.createTab(title: "Second")
        _ = controller.createTab(title: "Third")
        _ = controller.createTab(title: "Fourth")
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))
        XCTAssertEqual(pane.tabs.count, 4)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 30),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let contentView = try XCTUnwrap(window.contentView)
        let geometry = TabBarItemGeometryRegistry()
        for (index, tab) in pane.tabs.enumerated() {
            let item = NSView(frame: NSRect(x: CGFloat(index) * 100, y: 0, width: 100, height: 30))
            contentView.addSubview(item)
            geometry.register(item, for: tab.id)
        }
        let destination = TabBarDropDestinationNSView(frame: contentView.bounds)
        destination.pane = pane
        destination.bonsplitController = controller
        destination.splitViewController = controller.internalController
        destination.geometryRegistry = geometry
        // The runner's own Reduce Motion setting must not decide the test.
        destination.reducesMotion = { false }
        contentView.addSubview(destination)
        return Strip(
            window: window,
            controller: controller,
            pane: pane,
            registry: registry,
            geometry: geometry,
            destination: destination
        )
    }

    private func makeDrop(for tab: TabItem, at location: NSPoint, in strip: Strip) throws -> DropInfo {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TabDropSettleTests.\(UUID().uuidString)"))
        _ = pasteboard.clearContents()
        let transfer = TabDragTransfer(tab: Tab(from: tab), sourcePaneId: strip.pane.id)
        let registration = try XCTUnwrap(strip.registry.register(transfer))
        XCTAssertTrue(pasteboard.writeObjects([registration.pasteboardItem]))
        // The drag image as AppKit holds it: tab-sized, under the pointer.
        let item = NSDraggingItem(pasteboardWriter: NSPasteboardItem())
        item.draggingFrame = NSRect(x: location.x - 50, y: 0, width: 100, height: 30)
        return DropInfo(window: strip.window, location: location, pasteboard: pasteboard, item: item)
    }
}

/// The parts of a drop AppKit hands a destination, with the one dragging
/// item whose frame the destination may move.
private final class DropInfo: NSObject, NSDraggingInfo {
    let window: NSWindow
    let location: NSPoint
    let pasteboard: NSPasteboard
    let item: NSDraggingItem

    init(window: NSWindow, location: NSPoint, pasteboard: NSPasteboard, item: NSDraggingItem) {
        self.window = window
        self.location = location
        self.pasteboard = pasteboard
        self.item = item
    }

    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { item.draggingFrame.origin }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        var stop: ObjCBool = false
        block(item, 0, &stop)
    }
}
