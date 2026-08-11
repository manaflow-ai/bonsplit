import AppKit
import Testing

@testable import Bonsplit

@MainActor
@Suite struct TabBarDragEventRoutingTests {
    @Test func dragStartForwardsThresholdMoveToCancelPendingSwiftUIPress() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try #require(window.contentView)
        let sourceView = TabBarDragAndHoverView.TabBarBackgroundNSView(frame: contentView.bounds)
        let tabView = NSView(frame: NSRect(x: 20, y: 20, width: 120, height: 30))
        let tabId = UUID()
        let geometryRegistry = TabBarItemGeometryRegistry()
        var beganTabId: UUID?

        contentView.addSubview(sourceView)
        sourceView.addSubview(tabView)
        geometryRegistry.register(tabView, for: tabId)
        sourceView.geometryRegistry = geometryRegistry
        sourceView.tabIds = [tabId]
        sourceView.onBeginTabDrag = { tabId, _, _, _, _ in
            beganTabId = tabId
            return true
        }
        window.makeKeyAndOrderFront(nil)

        let mouseDown = try mouseEvent(
            type: .leftMouseDown,
            in: sourceView,
            at: NSPoint(x: 40, y: 35)
        )
        let mouseDragged = try mouseEvent(
            type: .leftMouseDragged,
            in: sourceView,
            at: NSPoint(x: 50, y: 45)
        )

        #expect(sourceView.handleTabDragEvent(mouseDown) === mouseDown)
        #expect(sourceView.handleTabDragEvent(mouseDragged) === mouseDragged)
        #expect(beganTabId == tabId)
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        in view: NSView,
        at point: NSPoint
    ) throws -> NSEvent {
        let window = try #require(view.window)
        return try #require(NSEvent.mouseEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
