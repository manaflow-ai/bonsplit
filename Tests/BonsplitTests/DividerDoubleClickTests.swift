import AppKit
import SwiftUI
import Testing
@testable import Bonsplit

@Suite("Divider double click", .serialized)
@MainActor
struct DividerDoubleClickTests {
    private final class Delegate: BonsplitDelegate {
        var events: [String] = []
        var splitIds: [UUID] = []
        var handled = true
        var onDoubleClick: (() -> Void)?

        func splitTabBarDividerDragDidBegin(_ controller: BonsplitController) { events.append("begin") }
        func splitTabBarDividerDragDidEnd(_ controller: BonsplitController) { events.append("end") }
        func splitTabBar(_ controller: BonsplitController, didDoubleClickDivider splitId: UUID) -> Bool {
            events.append("doubleClick")
            splitIds.append(splitId)
            onDoubleClick?()
            return handled
        }
    }

    @Test(arguments: [SplitOrientation.horizontal, .vertical])
    func doubleClickDispatchesOnceAfterSessionEnds(orientation: SplitOrientation) throws {
        try exercise(orientation: orientation, clickCount: 2, drag: false, handled: true)
    }

    @Test(arguments: [1, 3])
    func otherClicksKeepNativeTracking(clickCount: Int) throws {
        try exercise(orientation: .horizontal, clickCount: clickCount, drag: false, handled: true)
    }

    @Test func doubleClickThenDragDoesNotDispatch() throws {
        try exercise(orientation: .horizontal, clickCount: 2, drag: true, handled: true)
    }

    @Test func unhandledDoubleClickKeepsNativeTracking() throws {
        try exercise(orientation: .horizontal, clickCount: 2, drag: false, handled: false)
    }

    @Test func releaseIsDequeuedFromTheCapturedWindowWhenTheHostDetachesTheView() throws {
        let controller = BonsplitController()
        let delegate = Delegate()
        controller.delegate = delegate
        let pane = try #require(controller.focusedPaneId)
        _ = try #require(controller.splitPane(pane, orientation: .horizontal))
        guard case .split(let state) = controller.internalController.rootNode else {
            Issue.record("Expected a split")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let splitView = PointerSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())
        splitView.stampedInternalController = controller.internalController
        splitView.stampedSplitId = state.id
        window.contentView?.addSubview(splitView)
        // Equalizing can rebuild the split hierarchy; model that as the view leaving its window.
        delegate.onDoubleClick = { [weak splitView] in splitView?.removeFromSuperview() }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 2, pressure: 1))
        splitView.pointerEvent = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 2, pressure: 0))
        splitView.mouseDown(with: down)
        #expect(splitView.window == nil)
        #expect(splitView.consumedCount == 1)
        #expect(splitView.dequeueWindows.count == 1)
        #expect(splitView.dequeueWindows.first.map { $0 === window } == true)
    }

    @Test func staleDividerAfterSessionEndIsUnhandled() throws {
        try exercise(orientation: .horizontal, clickCount: 2, drag: false, handled: true, stale: true)
    }

    private final class PointerSplitView: ThemedSplitView {
        var pointerEvent: NSEvent?
        var nativeTrackingCount = 0
        var consumedCount = 0
        var dequeueWindows: [NSWindow?] = []

        override func trackDivider(with event: NSEvent) { nativeTrackingCount += 1 }
        override func nextDividerEvent(in window: NSWindow?, dequeue: Bool) -> NSEvent? {
            if dequeue {
                consumedCount += 1
                dequeueWindows.append(window)
            }
            return pointerEvent
        }
    }

    private func exercise(orientation: SplitOrientation, clickCount: Int, drag: Bool, handled: Bool, stale: Bool = false) throws {
        let controller = BonsplitController()
        let delegate = Delegate()
        delegate.handled = handled
        controller.delegate = delegate
        let pane = try #require(controller.focusedPaneId)
        _ = try #require(controller.splitPane(pane, orientation: orientation))
        guard case .split(let state) = controller.internalController.rootNode else {
            Issue.record("Expected a split")
            return
        }
        let splitView = PointerSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        splitView.isVertical = orientation == .horizontal
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())
        splitView.stampedInternalController = controller.internalController
        splitView.stampedSplitId = state.id
        splitView.onDividerDragSession = { [weak splitView] active in
            controller.internalController.noteDividerDragSession(active)
            if !active && stale { splitView?.stampedSplitId = UUID() }
        }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: clickCount, pressure: 1))
        splitView.pointerEvent = try #require(NSEvent.mouseEvent(
            with: drag ? .leftMouseDragged : .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: 0, context: nil,
            eventNumber: 2, clickCount: clickCount, pressure: 0))
        splitView.mouseDown(with: down)
        let dispatch = clickCount == 2 && !drag && !stale
        #expect(delegate.splitIds == (dispatch ? [state.id] : []))
        #expect(delegate.events == (dispatch ? ["begin", "end", "doubleClick"] : ["begin", "end"]))
        #expect(splitView.nativeTrackingCount == (dispatch && handled ? 0 : 1))
        #expect(splitView.consumedCount == (dispatch && handled ? 1 : 0))
        #expect(controller.internalController.activeDividerDragSessions == 0)
        #expect(controller.allPaneIds.count == 2)
    }
}
