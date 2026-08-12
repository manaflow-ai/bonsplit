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
        var beganEvent: NSEvent?

        contentView.addSubview(sourceView)
        sourceView.addSubview(tabView)
        geometryRegistry.register(tabView, for: tabId)
        sourceView.geometryRegistry = geometryRegistry
        sourceView.tabIds = [tabId]
        sourceView.onBeginTabDrag = { tabId, _, event, _, _ in
            beganTabId = tabId
            beganEvent = event
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
        #expect(beganEvent === mouseDragged)
    }

    @Test func secondClickOfDoubleClickStillArmsTabDrag() throws {
        // Regression (issue 10033): selecting a tab and immediately dragging it
        // delivers the press with clickCount == 2, because AppKit keeps counting
        // clicks that land near the same point inside the double-click interval.
        // Drag arming must accept those presses or the drag silently never starts.
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
            at: NSPoint(x: 40, y: 35),
            clickCount: 2
        )
        let mouseDragged = try mouseEvent(
            type: .leftMouseDragged,
            in: sourceView,
            at: NSPoint(x: 50, y: 45),
            clickCount: 2
        )

        _ = sourceView.handleTabDragEvent(mouseDown)
        _ = sourceView.handleTabDragEvent(mouseDragged)

        #expect(beganTabId == tabId)
    }

    @Test func staticTitleControlDoesNotBlockTabDragArming() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try #require(window.contentView)
        let sourceView = TabBarDragAndHoverView.TabBarBackgroundNSView(frame: contentView.bounds)
        let tabId = UUID()
        let geometryRegistry = TabBarItemGeometryRegistry()
        let tabView = NSView(frame: NSRect(x: 20, y: 20, width: 180, height: 30))
        let title = NSTextField(labelWithString: "A very wide tab title")
        title.frame = tabView.bounds.insetBy(dx: 8, dy: 4)
        var began = false

        contentView.addSubview(sourceView)
        sourceView.addSubview(tabView)
        tabView.addSubview(title)
        geometryRegistry.register(tabView, for: tabId)
        sourceView.geometryRegistry = geometryRegistry
        sourceView.tabIds = [tabId]
        sourceView.onBeginTabDrag = { _, _, _, _, _ in
            began = true
            return true
        }
        window.makeKeyAndOrderFront(nil)

        let mouseDown = try mouseEvent(
            type: .leftMouseDown,
            in: sourceView,
            at: NSPoint(x: 80, y: 35)
        )
        let mouseDragged = try mouseEvent(
            type: .leftMouseDragged,
            in: sourceView,
            at: NSPoint(x: 92, y: 35)
        )

        _ = sourceView.handleTabDragEvent(mouseDown)
        _ = sourceView.handleTabDragEvent(mouseDragged)

        #expect(began)
    }

    @Test func actionableButtonKeepsOwnershipOfTabPress() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try #require(window.contentView)
        let sourceView = TabBarDragAndHoverView.TabBarBackgroundNSView(frame: contentView.bounds)
        let tabId = UUID()
        let geometryRegistry = TabBarItemGeometryRegistry()
        let tabView = NSView(frame: NSRect(x: 20, y: 20, width: 180, height: 30))
        let button = NSButton(title: "Close", target: nil, action: nil)
        button.frame = NSRect(x: 150, y: 4, width: 26, height: 22)
        var began = false

        contentView.addSubview(sourceView)
        sourceView.addSubview(tabView)
        tabView.addSubview(button)
        geometryRegistry.register(tabView, for: tabId)
        sourceView.geometryRegistry = geometryRegistry
        sourceView.tabIds = [tabId]
        sourceView.onBeginTabDrag = { _, _, _, _, _ in
            began = true
            return true
        }
        window.makeKeyAndOrderFront(nil)

        let hitPoint = sourceView.convert(NSPoint(x: 183, y: 31), to: nil)
        #expect(contentView.hitTest(contentView.convert(hitPoint, from: nil)) === button)

        let mouseDown = try mouseEvent(
            type: .leftMouseDown,
            in: sourceView,
            at: NSPoint(x: 183, y: 31)
        )
        let mouseDragged = try mouseEvent(
            type: .leftMouseDragged,
            in: sourceView,
            at: NSPoint(x: 195, y: 31)
        )

        _ = sourceView.handleTabDragEvent(mouseDown)
        _ = sourceView.handleTabDragEvent(mouseDragged)

        #expect(!began)
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        in view: NSView,
        at point: NSPoint,
        clickCount: Int = 1
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
            clickCount: clickCount,
            pressure: 1
        ))
    }
}
