import AppKit
@testable import Bonsplit
import SwiftUI
import XCTest

#if DEBUG
@MainActor
final class TabBarLayoutFeedbackTests: XCTestCase {
    func testPinnedTabStaysAtLeadingEdgeWhileUnpinnedTabsScroll() throws {
        let size = NSSize(width: 420, height: TabBarMetrics.barHeight)
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(appearance: .default)
        )
        controller.tabShortcutHintsEnabled = false
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        let pinnedTab = TabItem(
            title: "Pinned Claude session",
            icon: "terminal.fill",
            kind: "terminal",
            isPinned: true
        )
        let unpinnedTabs = (0..<50).map { index in
            TabItem(
                title: "Terminal \(index + 1) — \(String(repeating: "x", count: index % 17))",
                icon: "terminal.fill",
                kind: "terminal"
            )
        }
        let tabs = [pinnedTab] + unpinnedTabs
        pane.tabs = tabs
        pane.selectedTabId = pinnedTab.id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: false)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try XCTUnwrap(window.contentView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        settleLayout(in: window, hostingView: hostingView)
        let scrollView = try XCTUnwrap(tabBarScrollView(in: hostingView))
        let chromeView = try XCTUnwrap(
            descendants(ofType: TabBarSelectionChromeView.ChromeNSView.self, in: hostingView).first
        )
        let initialFrames = try XCTUnwrap(
            chromeView.geometryRegistry?.frames(for: tabs.map(\.id), in: chromeView)
        )
        let maximumOffset = max(
            0,
            max(
                scrollView.documentView?.frame.width ?? 0,
                scrollView.documentView?.bounds.width ?? 0
            ) - scrollView.contentView.bounds.width
        )
        XCTAssertGreaterThan(maximumOffset, 0)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        scrollView.contentView.scroll(to: NSPoint(x: maximumOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settleLayout(in: window, hostingView: hostingView, passes: 2)

        let scrolledFrames = try XCTUnwrap(
            chromeView.geometryRegistry?.frames(for: tabs.map(\.id), in: chromeView)
        )
        let initialPinnedFrame = try XCTUnwrap(initialFrames[pinnedTab.id])
        let scrolledPinnedFrame = try XCTUnwrap(scrolledFrames[pinnedTab.id])
        XCTAssertEqual(
            scrolledPinnedFrame.minX,
            initialPinnedFrame.minX,
            accuracy: 1,
            "Pinned tabs must remain fixed while the unpinned tab row scrolls."
        )
        let initialUnpinnedFrame = try XCTUnwrap(initialFrames[unpinnedTabs[0].id])
        let scrolledUnpinnedFrame = try XCTUnwrap(scrolledFrames[unpinnedTabs[0].id])
        XCTAssertLessThan(
            scrolledUnpinnedFrame.minX,
            initialUnpinnedFrame.minX - 1,
            "Unpinned tabs should continue to scroll horizontally."
        )
    }

    func testScrollingManyTabsKeepsPlatformGeometryLive() throws {
        let size = NSSize(width: 420, height: TabBarMetrics.barHeight)
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(appearance: .default)
        )
        controller.tabShortcutHintsEnabled = false
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        let tabs = (0..<50).map { index in
            TabItem(
                title: "Terminal \(index + 1) — \(String(repeating: "x", count: index % 17))",
                icon: "terminal.fill",
                kind: "terminal"
            )
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs.first?.id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: false)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try XCTUnwrap(window.contentView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        settleLayout(in: window, hostingView: hostingView)
        let scrollView = try XCTUnwrap(tabBarScrollView(in: hostingView))
        let chromeView = try XCTUnwrap(
            descendants(ofType: TabBarSelectionChromeView.ChromeNSView.self, in: hostingView).first
        )
        let initialFirstFrame = try XCTUnwrap(
            chromeView.geometryRegistry?.frame(for: tabs[0].id, in: chromeView)
        )
        let maximumOffset = max(
            0,
            max(
                scrollView.documentView?.frame.width ?? 0,
                scrollView.documentView?.bounds.width ?? 0
            ) - scrollView.contentView.bounds.width
        )
        XCTAssertGreaterThan(maximumOffset, 0)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        for step in 1...8 {
            let offset = maximumOffset * CGFloat(step) / 8
            scrollView.contentView.scroll(to: NSPoint(x: offset, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            settleLayout(in: window, hostingView: hostingView, passes: 2)
        }

        let registeredFrames = try XCTUnwrap(chromeView.geometryRegistry?.frames(
            for: tabs.map(\.id),
            in: chromeView
        ))
        let scrolledFirstFrame = try XCTUnwrap(registeredFrames[tabs[0].id])
        XCTAssertEqual(registeredFrames.count, tabs.count)
        XCTAssertLessThanOrEqual(
            abs((initialFirstFrame.minX - maximumOffset) - scrolledFirstFrame.minX),
            1
        )
    }

    func testPointerOverEachTabHoversThatTab() throws {
        let size = NSSize(width: 600, height: TabBarMetrics.barHeight)
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(appearance: .default)
        )
        controller.tabShortcutHintsEnabled = false
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        let tabs = (0..<3).map { _ in
            TabItem(title: "terminal", icon: "terminal.fill", kind: "terminal")
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs.last?.id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: true)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try XCTUnwrap(window.contentView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        settleLayout(in: window, hostingView: hostingView)
        let chromeView = try XCTUnwrap(
            descendants(ofType: TabBarSelectionChromeView.ChromeNSView.self, in: hostingView).first
        )
        let registry = try XCTUnwrap(chromeView.geometryRegistry)
        let tabIds = tabs.map(\.id)
        let itemFrames = registry.frames(for: tabIds, in: chromeView)
        let visibleFrames = registry.visibleFrames(for: tabIds, in: chromeView)

        for tabId in tabIds {
            let itemFrame = try XCTUnwrap(itemFrames[tabId])
            XCTAssertEqual(
                visibleFrames[tabId],
                itemFrame,
                "An unscrolled tab's hover region must be the tab itself, not the whole strip."
            )
            let hovered = TabBarHoveredTabResolver().hoveredTabId(
                pointInView: NSPoint(x: itemFrame.midX, y: itemFrame.midY),
                barBounds: chromeView.bounds,
                tabIds: tabIds,
                frames: visibleFrames,
                trailingObscuredWidth: registry.trailingObscuredWidth
            )
            XCTAssertEqual(hovered, tabId, "The pointer over a tab must hover that tab.")
        }
    }

    func testTabScrolledPastLeadingEdgeHasNoHoverRegion() throws {
        let size = NSSize(width: 420, height: TabBarMetrics.barHeight)
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(appearance: .default)
        )
        controller.tabShortcutHintsEnabled = false
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        let tabs = (0..<30).map { index in
            TabItem(title: "Terminal \(index + 1)", icon: "terminal.fill", kind: "terminal")
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs.first?.id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: false)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try XCTUnwrap(window.contentView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)

        settleLayout(in: window, hostingView: hostingView)
        let scrollView = try XCTUnwrap(tabBarScrollView(in: hostingView))
        let chromeView = try XCTUnwrap(
            descendants(ofType: TabBarSelectionChromeView.ChromeNSView.self, in: hostingView).first
        )
        let registry = try XCTUnwrap(chromeView.geometryRegistry)
        let firstWidth = try XCTUnwrap(registry.frame(for: tabs[0].id, in: chromeView)).width

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        scrollView.contentView.scroll(to: NSPoint(x: firstWidth * 2, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settleLayout(in: window, hostingView: hostingView, passes: 2)

        let clip = scrollView.contentView.convert(scrollView.contentView.bounds, to: chromeView)
        let visibleFrames = registry.visibleFrames(for: tabs.map(\.id), in: chromeView)
        XCTAssertNil(visibleFrames[tabs[0].id], "A tab scrolled out of view must not be hoverable.")
        for (tabId, frame) in visibleFrames {
            XCTAssertTrue(
                clip.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                "Tab \(tabId) hover region \(frame) extends past the visible strip \(clip)."
            )
        }
    }

    private func settleLayout(in window: NSWindow, hostingView: NSView, passes: Int = 6) {
        for _ in 0..<passes {
            window.contentView?.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.01))
        }
    }

    private func tabBarScrollView(in root: NSView) -> NSScrollView? {
        descendants(ofType: NSScrollView.self, in: root).first { scrollView in
            let documentHeight = max(
                scrollView.documentView?.frame.height ?? 0,
                scrollView.documentView?.bounds.height ?? 0
            )
            return abs(scrollView.frame.height - TabBarMetrics.barHeight) <= 0.5
                && abs(documentHeight - TabBarMetrics.barHeight) <= 0.5
                && scrollView.frame.width > 0
        }
    }

    private func descendants<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var matches: [T] = []
        if let match = root as? T {
            matches.append(match)
        }
        for subview in root.subviews {
            matches.append(contentsOf: descendants(ofType: type, in: subview))
        }
        return matches
    }
}
#endif
