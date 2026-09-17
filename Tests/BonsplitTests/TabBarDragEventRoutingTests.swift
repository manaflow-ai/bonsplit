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
        // The strip only holds its pane weakly, exactly like production where
        // the split tree owns the model; keep it alive for the whole press.
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "Tab")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
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
        // The strip only holds its pane weakly, exactly like production where
        // the split tree owns the model; keep it alive for the whole press.
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "Tab")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
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
        // The strip only holds its pane weakly, exactly like production where
        // the split tree owns the model; keep it alive for the whole press.
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "Tab")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
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
        // The strip only holds its pane weakly, exactly like production where
        // the split tree owns the model; keep it alive for the whole press.
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "Tab")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
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

    @Test func laidOutTabStillArmsWhenGeometryRegistryLagsBehindTheStrip() throws {
        // Regression (cmux issue 12152): the press gate must judge a press
        // against what is on screen, not against the strip's bookkeeping.
        // SwiftUI mounts each tab's hit-region view as a sibling subtree of
        // the strip background and the registry entry is pushed separately;
        // a laid-out tab whose registry entry lags (or was dropped) is still a
        // real tab under the pointer and must arm a drag.
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
        let regionView = TabItemHitRegionView.RegionNSView(
            frame: NSRect(x: 20, y: 20, width: 120, height: 30)
        )
        regionView.configure(tabId: tabId, geometryRegistry: geometryRegistry)
        var beganTabId: UUID?

        contentView.addSubview(sourceView)
        contentView.addSubview(regionView)
        sourceView.geometryRegistry = geometryRegistry
        // The strip only holds its pane weakly, exactly like production where
        // the split tree owns the model; keep it alive for the whole press.
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "Tab")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
        sourceView.onBeginTabDrag = { tabId, _, _, _, _ in
            beganTabId = tabId
            return true
        }
        window.makeKeyAndOrderFront(nil)
        defer { regionView.removeFromSuperview() }

        // The strip's geometry registry has not caught up with the laid-out tab.
        geometryRegistry.unregister(regionView, for: tabId)
        #expect(geometryRegistry.frame(for: tabId, in: sourceView) == nil)

        let mouseDown = try mouseEvent(
            type: .leftMouseDown,
            in: sourceView,
            at: NSPoint(x: 40, y: 35)
        )
        let mouseDragged = try mouseEvent(
            type: .leftMouseDragged,
            in: sourceView,
            at: NSPoint(x: 52, y: 35)
        )

        _ = sourceView.handleTabDragEvent(mouseDown)
        _ = sourceView.handleTabDragEvent(mouseDragged)

        #expect(beganTabId == tabId)
    }

    @Test func pressOverLaidOutTabIsATabPressWhenGeometryRegistryLagsBehindTheStrip() throws {
        // Regression (cmux issue 12152): the same laid-out tab must also count
        // as a tab press for the strip background, or minimal mode turns the
        // press into a window drag and the double-click path into a new tab.
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
        let regionView = TabItemHitRegionView.RegionNSView(
            frame: NSRect(x: 20, y: 20, width: 120, height: 30)
        )
        regionView.configure(tabId: tabId, geometryRegistry: geometryRegistry)

        contentView.addSubview(sourceView)
        contentView.addSubview(regionView)
        sourceView.geometryRegistry = geometryRegistry
        // The strip only holds its pane weakly, exactly like production where
        // the split tree owns the model; keep it alive for the whole press.
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "Tab")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
        window.makeKeyAndOrderFront(nil)
        defer { regionView.removeFromSuperview() }

        geometryRegistry.unregister(regionView, for: tabId)

        #expect(sourceView.containsBonsplitTabItemHit(localPoint: NSPoint(x: 40, y: 35)))
        #expect(!sourceView.containsBonsplitTabItemHit(localPoint: NSPoint(x: 200, y: 35)))
    }

    /// Models cmux's main window: the content view is a flipped SwiftUI host
    /// while the window frame is not, so a point converted into the content
    /// view mirrors vertically if it is handed to `hitTest` directly.
    private final class FlippedContentView: NSView {
        override var isFlipped: Bool { true }
    }

    @Test func flippedHostContentViewStillArmsAndStillYieldsToTheTabsOwnControl() throws {
        // Regression (cmux issue 12152): with a flipped content view the veto
        // hit-tested the mirror image of the press, so the file editor at the
        // bottom of the window answered for presses on the strip at the top.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = FlippedContentView(frame: NSRect(x: 0, y: 0, width: 240, height: 200))
        window.contentView = contentView
        // Flipped coordinates: y grows downward, so the strip sits at the top.
        let sourceView = TabBarDragAndHoverView.TabBarBackgroundNSView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 30)
        )
        let tabId = UUID()
        let geometryRegistry = TabBarItemGeometryRegistry()
        let tabView = NSView(frame: NSRect(x: 20, y: 0, width: 180, height: 30))
        let closeButton = NSButton(title: "Close", target: nil, action: nil)
        closeButton.frame = NSRect(x: 150, y: 4, width: 26, height: 22)
        let editor = NSTextView(frame: NSRect(x: 0, y: 40, width: 240, height: 160))
        editor.isEditable = true
        var beganTabId: UUID?

        contentView.addSubview(editor)
        contentView.addSubview(sourceView)
        sourceView.addSubview(tabView)
        tabView.addSubview(closeButton)
        geometryRegistry.register(tabView, for: tabId)
        sourceView.geometryRegistry = geometryRegistry
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "report.html", kind: "filePreview")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
        sourceView.onBeginTabDrag = { tabId, _, _, _, _ in
            beganTabId = tabId
            return true
        }
        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(editor))

        // A press on the tab body arms, even though its mirror image lands in the editor.
        _ = sourceView.handleTabDragEvent(try mouseEvent(type: .leftMouseDown, in: sourceView, at: NSPoint(x: 60, y: 15)))
        _ = sourceView.handleTabDragEvent(try mouseEvent(type: .leftMouseDragged, in: sourceView, at: NSPoint(x: 72, y: 15)))
        #expect(beganTabId == tabId)

        // A press on the tab's own close button still belongs to the button.
        beganTabId = nil
        _ = sourceView.handleTabDragEvent(try mouseEvent(type: .leftMouseUp, in: sourceView, at: NSPoint(x: 72, y: 15)))
        _ = sourceView.handleTabDragEvent(try mouseEvent(type: .leftMouseDown, in: sourceView, at: NSPoint(x: 183, y: 15)))
        _ = sourceView.handleTabDragEvent(try mouseEvent(type: .leftMouseDragged, in: sourceView, at: NSPoint(x: 195, y: 15)))
        #expect(beganTabId == nil)
    }

    /// Models a host whose window hit-test answers a view the pointer is not
    /// inside: cmux's main window resolved the focused file editor for presses
    /// on the pane tab strip (cmux issue 12152).
    private final class EditorAnsweringContentView: NSView {
        weak var editor: NSTextView?

        override func hitTest(_ point: NSPoint) -> NSView? {
            editor ?? super.hitTest(point)
        }
    }

    @Test func editableTextViewOutsideTheStripNeverVetoesATabPress() throws {
        // Regression (cmux issue 12152): the native-interaction veto exists so a
        // control inside a tab (close button, rename field) keeps its press. A
        // view the press is not inside, such as the focused file editor below
        // the strip, owns nothing about that press and must not block the drag.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = EditorAnsweringContentView(frame: NSRect(x: 0, y: 0, width: 240, height: 200))
        window.contentView = contentView
        let sourceView = TabBarDragAndHoverView.TabBarBackgroundNSView(
            frame: NSRect(x: 0, y: 170, width: 240, height: 30)
        )
        let tabId = UUID()
        let geometryRegistry = TabBarItemGeometryRegistry()
        let tabView = NSView(frame: NSRect(x: 20, y: 0, width: 120, height: 30))
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        editor.isEditable = true
        var beganTabId: UUID?

        contentView.addSubview(editor)
        contentView.addSubview(sourceView)
        sourceView.addSubview(tabView)
        contentView.editor = editor
        geometryRegistry.register(tabView, for: tabId)
        sourceView.geometryRegistry = geometryRegistry
        let pane = PaneState(tabs: [TabItem(id: tabId, title: "report.html", kind: "filePreview")])
        defer { withExtendedLifetime(pane) {} }
        sourceView.pane = pane
        sourceView.onBeginTabDrag = { tabId, _, _, _, _ in
            beganTabId = tabId
            return true
        }
        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(editor))

        let mouseDown = try mouseEvent(
            type: .leftMouseDown,
            in: sourceView,
            at: NSPoint(x: 40, y: 15)
        )
        let mouseDragged = try mouseEvent(
            type: .leftMouseDragged,
            in: sourceView,
            at: NSPoint(x: 52, y: 15)
        )

        _ = sourceView.handleTabDragEvent(mouseDown)
        _ = sourceView.handleTabDragEvent(mouseDragged)

        #expect(beganTabId == tabId)
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
