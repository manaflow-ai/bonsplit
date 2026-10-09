import AppKit
import Testing
@testable import Bonsplit

@MainActor
@Suite("Tab strip hover reveal", .serialized)
struct TabBarHoverRevealTests {
    @Test("Hover reveal survives both hover callbacks before document padding changes")
    func repeatedHoverBeforeDocumentResize() throws {
        let harness = try Harness()
        defer { harness.window.orderOut(nil) }

        harness.registry.setTrailingObscuredWidth(60, revealTabId: harness.hoveredTabId)
        harness.registry.setTrailingObscuredWidth(60, revealTabId: harness.hoveredTabId)
        harness.documentView.setFrameSize(NSSize(width: 660, height: 28))

        #expect(harness.hoveredFrame.maxX <= 140.5)
    }

    @Test("Repeated document geometry notifications preserve the hovered tab")
    func repeatedDocumentGeometry() throws {
        let harness = try Harness()
        defer { harness.window.orderOut(nil) }

        harness.registry.setTrailingObscuredWidth(60, revealTabId: harness.hoveredTabId)
        harness.documentView.setFrameSize(NSSize(width: 660, height: 28))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: harness.documentView)

        #expect(harness.hoveredFrame.maxX <= 140.5)
    }

    @Test("Unchanged selected geometry does not replace an unselected hover reveal")
    func selectedGeometryAfterHover() throws {
        let harness = try Harness()
        defer { harness.window.orderOut(nil) }
        harness.documentView.setFrameSize(NSSize(width: 660, height: 28))
        harness.registry.geometryDidChange(for: harness.selectedTabId)

        harness.registry.setTrailingObscuredWidth(60, revealTabId: harness.hoveredTabId)
        harness.selectedView.frame.origin.x = 80
        harness.registry.geometryDidChange(for: harness.selectedTabId)

        #expect(harness.hoveredFrame.maxX <= 140.5)
    }

    @Test("Hover exit clears the deferred reveal before a later document resize")
    func hoverExitClearsReveal() throws {
        let harness = try Harness()
        defer { harness.window.orderOut(nil) }

        harness.registry.setTrailingObscuredWidth(60, revealTabId: harness.hoveredTabId)
        harness.registry.setTrailingObscuredWidth(60, revealTabId: nil)
        harness.documentView.setFrameSize(NSSize(width: 660, height: 28))

        #expect(harness.scrollView.contentView.bounds.origin.x <= 40.5)
        #expect(harness.hoveredFrame.minX >= 459.5)
    }

    @Test("Revealing a clipped tab keeps it under the stationary pointer")
    func stationaryPointerKeepsHoveredTab() throws {
        let harness = try Harness()
        defer { harness.window.orderOut(nil) }
        harness.hoveredView.frame = NSRect(x: 130, y: 0, width: 50, height: 28)
        let pointer = NSPoint(x: 135, y: 14)
        #expect(harness.hoveredFrame.contains(pointer))

        harness.registry.setTrailingObscuredWidth(60, revealTabId: harness.hoveredTabId)

        #expect(harness.hoveredFrame.contains(pointer))
        #expect(TabBarHoveredTabResolver().hoveredTabId(
            pointInView: pointer,
            barBounds: NSRect(x: 0, y: 0, width: 200, height: 28),
            tabIds: [harness.hoveredTabId],
            frames: [harness.hoveredTabId: harness.hoveredFrame],
            trailingObscuredWidth: 60
        ) == harness.hoveredTabId)
    }

    @Test("A tab wider than the uncovered strip exposes its trailing close affordance")
    func wideHoveredTabRevealsTrailingEdge() throws {
        let harness = try Harness()
        defer { harness.window.orderOut(nil) }
        harness.documentView.setFrameSize(NSSize(width: 740, height: 28))

        harness.registry.setTrailingObscuredWidth(140, revealTabId: harness.hoveredTabId)

        #expect(harness.hoveredFrame.maxX <= 60.5)
        #expect(harness.hoveredFrame.maxX >= 59.5)
        #expect(harness.hoveredFrame.contains(NSPoint(x: 30, y: 14)))
    }

    @MainActor
    private struct Harness {
        let window: NSWindow
        let scrollView: NSScrollView
        let documentView: NSView
        let selectedView: NSView
        let hoveredView: NSView
        let selectedTabId = UUID()
        let hoveredTabId = UUID()
        let registry = TabBarItemGeometryRegistry()

        init() throws {
            _ = NSApplication.shared
            let viewport = NSRect(x: 0, y: 0, width: 200, height: 28)
            window = NSWindow(contentRect: viewport, styleMask: [.titled], backing: .buffered, defer: false)
            scrollView = NSScrollView(frame: viewport)
            documentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 28))
            selectedView = NSView(frame: NSRect(x: 40, y: 0, width: 100, height: 28))
            hoveredView = NSView(frame: NSRect(x: 480, y: 0, width: 100, height: 28))
            documentView.addSubview(selectedView)
            documentView.addSubview(hoveredView)
            scrollView.documentView = documentView
            try #require(window.contentView).addSubview(scrollView)
            window.orderFront(nil)
            registry.attachScrollView(scrollView)
            registry.register(selectedView, for: selectedTabId)
            registry.register(hoveredView, for: hoveredTabId)
            registry.revealSelection(selectedTabId)
        }

        var hoveredFrame: NSRect {
            hoveredView.convert(hoveredView.bounds, to: documentView)
                .offsetBy(dx: -scrollView.contentView.bounds.origin.x, dy: 0)
        }
    }
}
