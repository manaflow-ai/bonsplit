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
        splitView.queuedEvents = [try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 2, clickCount: 2, pressure: 0))]
        splitView.mouseDown(with: down)
        #expect(splitView.window == nil)
        #expect(splitView.consumedCount == 1)
        #expect(splitView.dequeueWindows.count == 1)
        #expect(splitView.dequeueWindows.first.map { $0 === window } == true)
    }

    /// A host callback can run a nested event loop (an alert, a menu), which would
    /// consume a release still in the queue. Reading it afterward would then wait
    /// until `.distantFuture` for a release that already happened, hanging the app.
    @Test func hostCallbackThatDrainsTheQueueDoesNotStrandTheDivider() throws {
        let fixture = try makeDoubleClickFixture()
        fixture.delegate.onDoubleClick = { [weak splitView = fixture.splitView] in
            splitView?.queuedEvents.removeAll()
        }
        fixture.splitView.mouseDown(with: fixture.down)
        #expect(fixture.delegate.events == ["begin", "end", "doubleClick"])
        #expect(fixture.splitView.readsOfEmptyQueue == 0)
        #expect(fixture.splitView.consumedCount == 1)
        #expect(fixture.splitView.nativeTrackingCount == 0)
    }

    @Test func releaseLeavesTheQueueBeforeTheHostCallback() throws {
        let fixture = try makeDoubleClickFixture()
        var queuedAtCallback: Int?
        fixture.delegate.onDoubleClick = { [weak splitView = fixture.splitView] in
            queuedAtCallback = splitView?.queuedEvents.count
        }
        fixture.splitView.mouseDown(with: fixture.down)
        #expect(queuedAtCallback == 0)
    }

    /// A host can drain the queue and still decline. Native tracking must then
    /// get that same release back, or it would wait for a mouse-up that happened.
    @Test func declinedDoubleClickHandsTheSameReleaseToNativeTracking() throws {
        let fixture = try makeDoubleClickFixture()
        fixture.delegate.handled = false
        fixture.delegate.onDoubleClick = { [weak splitView = fixture.splitView] in
            splitView?.queuedEvents.removeAll()
        }
        fixture.splitView.mouseDown(with: fixture.down)
        #expect(fixture.splitView.nativeTrackingCount == 1)
        #expect(fixture.splitView.queuedAtNativeTracking.count == 1)
        #expect(fixture.splitView.queuedAtNativeTracking.first === fixture.release)
        #expect(fixture.splitView.readsOfEmptyQueue == 0)
    }

    /// The real seam, not the test double: AppKit must return the requeued release
    /// to the next reader, which is what native tracking relies on.
    @Test func requeuedReleaseIsTheNextEventAppKitDelivers() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let release = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: window.windowNumber, context: nil,
            eventNumber: 7, clickCount: 2, pressure: 0))
        ThemedSplitView().requeueDividerEvent(release, in: window)
        let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                    until: Date(timeIntervalSinceNow: 2),
                                    inMode: .eventTracking, dequeue: true)
        #expect(next?.type == .leftMouseUp)
        #expect(next?.eventNumber == 7)
    }

    /// The whole decline path with nothing stubbed: a real window queue and
    /// NSSplitView's own tracking loop must take the reposted release and return.
    /// The timer posts a second release, so a loop that ignores the first one fails
    /// here instead of hanging the test run.
    @Test func declinedDoubleClickEndsRealSplitViewTracking() throws {
        _ = NSApplication.shared
        let controller = BonsplitController()
        let delegate = Delegate()
        delegate.handled = false
        controller.delegate = delegate
        let pane = try #require(controller.focusedPaneId)
        _ = try #require(controller.splitPane(pane, orientation: .horizontal))
        guard case .split(let state) = controller.internalController.rootNode else {
            Issue.record("Expected a split")
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let splitView = QueueObservingSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        splitView.isVertical = true
        splitView.addArrangedSubview(NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600)))
        splitView.addArrangedSubview(NSView(frame: NSRect(x: 400, y: 0, width: 400, height: 600)))
        splitView.stampedInternalController = controller.internalController
        splitView.stampedSplitId = state.id
        window.contentView?.addSubview(splitView)
        window.orderFront(nil)
        splitView.adjustSubviews()
        splitView.setPosition(400, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
        let dividerX = splitView.arrangedSubviews[0].frame.maxX + splitView.dividerThickness / 2
        let location = splitView.convert(NSPoint(x: dividerX, y: 300), to: nil)
        func mouseEvent(_ type: NSEvent.EventType, number: Int) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: number, clickCount: 2, pressure: type == .leftMouseDown ? 1 : 0))
        }
        let rescue = try mouseEvent(.leftMouseUp, number: 3)
        final class Flag { var fired = false }
        let rescued = Flag()
        let timer = Timer(timeInterval: 3, repeats: false) { _ in
            MainActor.assumeIsolated {
                rescued.fired = true
                window.postEvent(rescue, atStart: false)
            }
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .default)
        defer { timer.invalidate() }

        window.postEvent(try mouseEvent(.leftMouseUp, number: 2), atStart: false)
        splitView.mouseDown(with: try mouseEvent(.leftMouseDown, number: 1))

        #expect(delegate.events.contains("doubleClick"))
        #expect(!rescued.fired, "Native tracking must take the release the host declined")
        #expect(splitView.releaseBeforeTracking?.eventNumber == 2,
                "Native tracking must start with the same release back in the queue")
        #expect(splitView.releaseAfterTracking == nil,
                "Only AppKit's tracking loop can have consumed it, so a click that missed the divider fails here")
    }

    /// Leaves the event queue and AppKit's tracking real and only looks at the queue around it.
    private final class QueueObservingSplitView: ThemedSplitView {
        var releaseBeforeTracking: NSEvent?
        var releaseAfterTracking: NSEvent?

        private func queuedRelease() -> NSEvent? {
            window?.nextEvent(matching: [.leftMouseUp], until: .distantPast, inMode: .eventTracking, dequeue: false)
        }

        override func trackDivider(with event: NSEvent) {
            releaseBeforeTracking = queuedRelease()
            super.trackDivider(with: event)
            releaseAfterTracking = queuedRelease()
        }
    }

    private struct DoubleClickFixture {
        let controller: BonsplitController
        let delegate: Delegate
        let splitView: PointerSplitView
        let down: NSEvent
        let release: NSEvent
    }

    private func makeDoubleClickFixture() throws -> DoubleClickFixture {
        let controller = BonsplitController()
        let delegate = Delegate()
        controller.delegate = delegate
        let pane = try #require(controller.focusedPaneId)
        _ = try #require(controller.splitPane(pane, orientation: .horizontal))
        guard case .split(let state) = controller.internalController.rootNode else {
            throw FixtureError.expectedSplit
        }
        let splitView = PointerSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        splitView.isVertical = true
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())
        splitView.stampedInternalController = controller.internalController
        splitView.stampedSplitId = state.id
        splitView.onDividerDragSession = { active in
            controller.internalController.noteDividerDragSession(active)
        }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 2, pressure: 1))
        let release = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: 0, context: nil,
            eventNumber: 2, clickCount: 2, pressure: 0))
        splitView.queuedEvents = [release]
        return DoubleClickFixture(controller: controller, delegate: delegate, splitView: splitView, down: down, release: release)
    }

    private enum FixtureError: Error { case expectedSplit }

    @Test func staleDividerAfterSessionEndIsUnhandled() throws {
        try exercise(orientation: .horizontal, clickCount: 2, drag: false, handled: true, stale: true)
    }

    private final class PointerSplitView: ThemedSplitView {
        /// Models the window's event queue, so a host callback can drain it the
        /// way a nested event loop would.
        var queuedEvents: [NSEvent] = []
        var nativeTrackingCount = 0
        var consumedCount = 0
        var dequeueWindows: [NSWindow?] = []
        /// Counts reads of an empty queue. The real read waits until
        /// `.distantFuture`, so outside a test each of these is a stuck main thread.
        var readsOfEmptyQueue = 0
        var queuedAtNativeTracking: [NSEvent] = []

        override func trackDivider(with event: NSEvent) {
            nativeTrackingCount += 1
            queuedAtNativeTracking = queuedEvents
        }
        override func requeueDividerEvent(_ event: NSEvent, in window: NSWindow?) {
            queuedEvents.insert(event, at: 0)
        }
        override func nextDividerEvent(in window: NSWindow?, dequeue: Bool) -> NSEvent? {
            guard let head = queuedEvents.first else {
                readsOfEmptyQueue += 1
                return nil
            }
            if dequeue {
                consumedCount += 1
                dequeueWindows.append(window)
                queuedEvents.removeFirst()
            }
            return head
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
        splitView.queuedEvents = [try #require(NSEvent.mouseEvent(
            with: drag ? .leftMouseDragged : .leftMouseUp, location: .zero,
            modifierFlags: [], timestamp: 1.1, windowNumber: 0, context: nil,
            eventNumber: 2, clickCount: clickCount, pressure: 0))]
        splitView.mouseDown(with: down)
        let dispatch = clickCount == 2 && !drag && !stale
        #expect(delegate.splitIds == (dispatch ? [state.id] : []))
        #expect(delegate.events == (dispatch ? ["begin", "end", "doubleClick"] : ["begin", "end"]))
        #expect(splitView.nativeTrackingCount == (dispatch && handled ? 0 : 1))
        let releaseWasOffered = clickCount == 2 && !drag
        #expect(splitView.consumedCount == (releaseWasOffered ? 1 : 0))
        if splitView.nativeTrackingCount == 1 {
            #expect(splitView.queuedAtNativeTracking.count == 1,
                    "Native tracking must still find the event in the queue")
        }
        #expect(controller.internalController.activeDividerDragSessions == 0)
        #expect(controller.allPaneIds.count == 2)
    }
}
