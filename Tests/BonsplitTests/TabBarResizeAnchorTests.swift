import AppKit
@testable import Bonsplit
import XCTest

final class TabBarResizeAnchorTests: XCTestCase {
    @MainActor
    func testPendingSelectionReconcilesWhenScrollViewAttaches() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.registry.register(harness.selectedView, for: harness.selectedTabId)
        harness.registry.revealSelection(harness.selectedTabId)
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)

        harness.registry.attachScrollView(harness.scrollView)
        XCTAssertGreaterThan(harness.scrollView.contentView.bounds.origin.x, 0)
    }

    @MainActor
    func testProgrammaticRevealSurvivesLaterBoundsOriginRestoration() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.registry.attachScrollView(harness.scrollView)
        harness.registry.register(harness.selectedView, for: harness.selectedTabId)
        harness.registry.revealSelection(harness.selectedTabId)
        let revealedOffset = harness.scrollView.contentView.bounds.origin.x
        XCTAssertGreaterThan(revealedOffset, 0)

        harness.scrollView.contentView.scroll(to: .zero)
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin.x, revealedOffset, accuracy: 0.5)
    }

    @MainActor
    func testLiveUserScrollRelinquishesProgrammaticOffsetOwnership() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.registry.attachScrollView(harness.scrollView)
        harness.registry.register(harness.selectedView, for: harness.selectedTabId)
        harness.registry.revealSelection(harness.selectedTabId)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: harness.scrollView
        )
        harness.scrollView.contentView.scroll(to: NSPoint(x: 120, y: 0))
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin.x, 120, accuracy: 0.5)
    }

    @MainActor
    func testNativeTabBarRevealsNewlySelectedOverflowTab() throws {
        let harness = try makeNativeHarness(width: 320, tabCount: 8, selectedIndex: 0)
        defer { harness.window.orderOut(nil) }
        let tabBar = try nativeTabBar(in: harness.viewController.view)
        let lastTab = try XCTUnwrap(harness.pane.tabs.last)

        harness.pane.selectTab(lastTab.id)
        settleLayout(in: harness.window, root: harness.viewController.view)

        let tabView = try XCTUnwrap(tabBar.tabViewsForTesting[lastTab.id])
        let visible = tabBar.scrollViewForTesting.documentVisibleRect
        XCTAssertGreaterThan(tabBar.scrollViewForTesting.contentView.bounds.origin.x, 0)
        XCTAssertGreaterThanOrEqual(tabView.frame.minX, visible.minX - 0.5)
        XCTAssertLessThanOrEqual(tabView.frame.maxX, visible.maxX + 0.5)
    }

    @MainActor
    func testNativeTabBarReturnsToLeadingEdgeWhenContentShrinks() throws {
        let harness = try makeNativeHarness(width: 320, tabCount: 8, selectedIndex: 7)
        defer { harness.window.orderOut(nil) }
        let tabBar = try nativeTabBar(in: harness.viewController.view)
        XCTAssertGreaterThan(tabBar.scrollViewForTesting.contentView.bounds.origin.x, 0)

        harness.pane.tabs = Array(harness.pane.tabs.prefix(1))
        harness.pane.selectedTabId = harness.pane.tabs.first?.id
        settleLayout(in: harness.window, root: harness.viewController.view)

        XCTAssertEqual(tabBar.scrollViewForTesting.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    @MainActor
    func testNativeTabBarPreservesValidUserOffsetAcrossResize() throws {
        let harness = try makeNativeHarness(width: 260, tabCount: 10, selectedIndex: 0)
        defer { harness.window.orderOut(nil) }
        let tabBar = try nativeTabBar(in: harness.viewController.view)
        let scrollView = tabBar.scrollViewForTesting
        let maximum = max(0, (scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width)
        let userOffset = maximum * 0.35
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: userOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        harness.window.setContentSize(NSSize(width: 300, height: 180))
        settleLayout(in: harness.window, root: harness.viewController.view)

        let resizedMaximum = max(0, (scrollView.documentView?.frame.width ?? 0) - scrollView.contentView.bounds.width)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, min(userOffset, resizedMaximum), accuracy: 1)
    }

    @MainActor
    func testSelectedOverflowTabTracksLiveGeometryAndFullyRevealsChrome() throws {
        let harness = try makeNativeHarness(width: 420, tabCount: 3, selectedIndex: 0)
        defer { harness.window.orderOut(nil) }
        let tabBar = try nativeTabBar(in: harness.viewController.view)
        XCTAssertEqual(maxHorizontalOffset(in: tabBar.scrollViewForTesting), 0, accuracy: 0.5)

        let newTab = TabItem(title: "New browser tab", icon: "globe", kind: "browser")
        harness.pane.addTab(newTab)
        settleLayout(in: harness.window, root: harness.viewController.view)
        let initialFrame = try visibleFrame(for: newTab.id, in: tabBar)

        let index = try XCTUnwrap(harness.pane.tabs.firstIndex(where: { $0.id == newTab.id }))
        harness.pane.tabs[index].title = String(repeating: "Long browser title ", count: 8)
        settleLayout(in: harness.window, root: harness.viewController.view)

        let selectedFrame = try visibleFrame(for: newTab.id, in: tabBar)
        XCTAssertGreaterThan(selectedFrame.width, initialFrame.width + 1)
        XCTAssertGreaterThan(maxHorizontalOffset(in: tabBar.scrollViewForTesting), 0)
        XCTAssertGreaterThan(tabBar.scrollViewForTesting.contentView.bounds.origin.x, 0)
        XCTAssertGreaterThanOrEqual(selectedFrame.minX, tabBar.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(selectedFrame.maxX, tabBar.bounds.maxX + 0.5)
    }

    @MainActor
    func testSelectedTabStaysRevealedWhenEarlierTabGrowthMovesItsLiveFrame() throws {
        let harness = try makeNativeHarness(width: 420, tabCount: 4, selectedIndex: 3)
        defer { harness.window.orderOut(nil) }
        let tabBar = try nativeTabBar(in: harness.viewController.view)
        let selectedID = try XCTUnwrap(harness.pane.selectedTabId)

        harness.pane.tabs[0].title = String(repeating: "Long earlier title ", count: 8)
        settleLayout(in: harness.window, root: harness.viewController.view)

        let selectedFrame = try visibleFrame(for: selectedID, in: tabBar)
        XCTAssertGreaterThan(maxHorizontalOffset(in: tabBar.scrollViewForTesting), 0)
        XCTAssertGreaterThan(tabBar.scrollViewForTesting.contentView.bounds.origin.x, 0)
        XCTAssertGreaterThanOrEqual(selectedFrame.minX, tabBar.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(selectedFrame.maxX, tabBar.bounds.maxX + 0.5)
    }

    @MainActor
    func testSelectingTabBehindActionLaneRevealsItsCloseAffordance() throws {
        let harness = try makeNativeHarness(
            width: 520,
            tabCount: 5,
            selectedIndex: 0,
            showSplitButtons: true
        )
        defer { harness.window.orderOut(nil) }
        let tabBar = try nativeTabBar(in: harness.viewController.view)
        let scrollView = tabBar.scrollViewForTesting
        let target = try XCTUnwrap(harness.pane.tabs.last)
        let laneWidth = TabBarStyling.splitButtonsBackdropWidth(
            buttonCount: BonsplitConfiguration.SplitActionButton.defaults.count
        )
        let unobscuredMaxX = tabBar.bounds.maxX - laneWidth
        let targetView = try XCTUnwrap(tabBar.tabViewsForTesting[target.id])
        let rawTrailingOffset = max(0, targetView.frame.maxX - tabBar.bounds.width)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: rawTrailingOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        settleLayout(in: harness.window, root: harness.viewController.view)
        let obscuredFrame = try visibleFrame(for: target.id, in: tabBar)
        XCTAssertGreaterThan(obscuredFrame.maxX, unobscuredMaxX + 1)
        XCTAssertLessThanOrEqual(obscuredFrame.maxX, tabBar.bounds.maxX + 0.5)
        let initialOffset = scrollView.contentView.bounds.origin.x

        harness.pane.selectTab(target.id)
        settleLayout(in: harness.window, root: harness.viewController.view)
        let selectedFrame = try visibleFrame(for: target.id, in: tabBar)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, initialOffset + 0.5)
        XCTAssertLessThanOrEqual(selectedFrame.maxX, unobscuredMaxX + 0.5)
    }

    @MainActor
    func testViewportResizeKeepsLeadingAnchoredWhenTabStripWasLeadingAligned() throws {
        let harness = try makeNativeHarness(width: 900, tabCount: 8, selectedIndex: 2)
        defer { harness.window.orderOut(nil) }
        let scrollView = try nativeTabBar(in: harness.viewController.view).scrollViewForTesting
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)

        harness.window.setContentSize(NSSize(width: 240, height: 180))
        settleLayout(in: harness.window, root: harness.viewController.view)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    @MainActor
    func testViewportResizeClampsExistingOverflowOffsetToNewRange() throws {
        let harness = try makeNativeHarness(width: 240, tabCount: 8, selectedIndex: 7)
        defer { harness.window.orderOut(nil) }
        let scrollView = try nativeTabBar(in: harness.viewController.view).scrollViewForTesting
        let initialMaximum = maxHorizontalOffset(in: scrollView)
        XCTAssertGreaterThan(initialMaximum, 0)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: initialMaximum, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        harness.window.setContentSize(NSSize(width: 360, height: 180))
        settleLayout(in: harness.window, root: harness.viewController.view)
        let resizedMaximum = maxHorizontalOffset(in: scrollView)
        XCTAssertGreaterThan(resizedMaximum, 0)
        XCTAssertLessThan(resizedMaximum, initialMaximum)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, resizedMaximum, accuracy: 0.5)
    }

    @MainActor
    func testContentShrinkReturnsFittingStripToLeadingEdge() throws {
        let harness = try makeNativeHarness(width: 360, tabCount: 8, selectedIndex: 0)
        defer { harness.window.orderOut(nil) }
        let scrollView = try nativeTabBar(in: harness.viewController.view).scrollViewForTesting
        let initialMaximum = maxHorizontalOffset(in: scrollView)
        XCTAssertGreaterThan(initialMaximum, 0)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: initialMaximum, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        harness.pane.tabs = Array(harness.pane.tabs.prefix(2))
        harness.pane.selectedTabId = harness.pane.tabs.first?.id
        settleLayout(in: harness.window, root: harness.viewController.view)
        XCTAssertEqual(maxHorizontalOffset(in: scrollView), 0, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    @MainActor
    func testViewportResizeDoesNotUndoLaterValidOffset() async throws {
        let harness = try makeNativeHarness(width: 240, tabCount: 8, selectedIndex: 7)
        defer { harness.window.orderOut(nil) }
        let scrollView = try nativeTabBar(in: harness.viewController.view).scrollViewForTesting
        harness.window.setContentSize(NSSize(width: 360, height: 180))
        settleLayout(in: harness.window, root: harness.viewController.view)

        let validOffset = maxHorizontalOffset(in: scrollView) / 2
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        scrollView.contentView.scroll(to: NSPoint(x: validOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await Task.yield()
        settleLayout(in: harness.window, root: harness.viewController.view)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, validOffset, accuracy: 0.5)
    }

    private struct GeometryRegistryHarness {
        let window: NSWindow
        let scrollView: NSScrollView
        let selectedView: NSView
        let selectedTabId: UUID
        let registry: TabBarItemGeometryRegistry
    }

    private struct NativeHarness {
        let window: NSWindow
        let viewController: BonsplitViewController
        let pane: PaneState
    }

    @MainActor
    private func makeGeometryRegistryHarness() throws -> GeometryRegistryHarness {
        let viewportSize = NSSize(width: 200, height: TabBarMetrics.barHeight)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewportSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let contentView = try XCTUnwrap(window.contentView)
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: viewportSize))
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: viewportSize.height))
        let selectedView = NSView(frame: NSRect(x: 480, y: 0, width: 100, height: viewportSize.height))
        let selectedTabId = UUID()
        let registry = TabBarItemGeometryRegistry()

        documentView.addSubview(selectedView)
        scrollView.documentView = documentView
        contentView.addSubview(scrollView)
        window.makeKeyAndOrderFront(nil)

        return .init(
            window: window,
            scrollView: scrollView,
            selectedView: selectedView,
            selectedTabId: selectedTabId,
            registry: registry
        )
    }

    @MainActor
    private func makeNativeHarness(
        width: CGFloat,
        tabCount: Int,
        selectedIndex: Int,
        showSplitButtons: Bool = false
    ) throws -> NativeHarness {
        let appearance = BonsplitConfiguration.Appearance(
            splitButtons: showSplitButtons
                ? BonsplitConfiguration.SplitActionButton.defaults
                : []
        )
        let controller = BonsplitController(configuration: .init(
            contentViewLifecycle: .keepAllAlive,
            appearance: appearance
        ))
        controller.tabShortcutHintsEnabled = false
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        pane.tabs = (0..<tabCount).map {
            TabItem(title: "Terminal \($0 + 1)", icon: "terminal.fill", kind: "terminal")
        }
        pane.selectedTabId = pane.tabs[selectedIndex].id

        let renderer = BonsplitViewController(controller: controller) { _, _ in
            let child = NSViewController()
            child.view = NSView()
            return child
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = renderer
        window.setContentSize(NSSize(width: width, height: 180))
        window.makeKeyAndOrderFront(nil)
        settleLayout(in: window, root: renderer.view)
        return .init(window: window, viewController: renderer, pane: pane)
    }

    @MainActor
    private func nativeTabBar(in root: NSView) throws -> BonsplitNativeTabBarView {
        try XCTUnwrap(descendants(ofType: BonsplitNativeTabBarView.self, in: root).first)
    }

    @MainActor
    private func visibleFrame(for tabID: UUID, in tabBar: BonsplitNativeTabBarView) throws -> NSRect {
        let tabView = try XCTUnwrap(tabBar.tabViewsForTesting[tabID])
        return tabBar.convert(tabView.bounds, from: tabView)
    }

    @MainActor
    private func maxHorizontalOffset(in scrollView: NSScrollView) -> CGFloat {
        let documentWidth = max(
            scrollView.documentView?.frame.width ?? 0,
            scrollView.documentView?.bounds.width ?? 0
        )
        return max(0, documentWidth - scrollView.contentView.bounds.width)
    }

    @MainActor
    private func settleLayout(in window: NSWindow, root: NSView, passes: Int = 12) {
        for _ in 0..<passes {
            window.contentView?.layoutSubtreeIfNeeded()
            root.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.005))
        }
    }

    @MainActor
    private func descendants<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var matches = (root as? T).map { [$0] } ?? []
        for subview in root.subviews {
            matches.append(contentsOf: descendants(ofType: type, in: subview))
        }
        return matches
    }
}
