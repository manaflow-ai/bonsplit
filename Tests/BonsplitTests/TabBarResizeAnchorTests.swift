import AppKit
@testable import Bonsplit
import SwiftUI
import XCTest

@MainActor
final class TabBarResizeAnchorTests: XCTestCase {
    func testPendingSelectionReconcilesWhenScrollViewAttaches() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.registry.register(harness.selectedView, for: harness.selectedTabId)
        harness.registry.revealSelection(harness.selectedTabId)
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)

        harness.registry.attachScrollView(harness.scrollView)

        XCTAssertGreaterThan(
            harness.scrollView.contentView.bounds.origin.x,
            0,
            "Attaching live AppKit geometry must resume a selected-tab reveal that was pending before the scroll view existed."
        )
    }

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

        XCTAssertEqual(
            harness.scrollView.contentView.bounds.origin.x,
            revealedOffset,
            accuracy: 0.5,
            "A later SwiftUI bounds-origin restoration must not overwrite the registry's selected-tab reveal."
        )
    }

    func testLiveUserScrollRelinquishesProgrammaticOffsetOwnership() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.registry.attachScrollView(harness.scrollView)
        harness.registry.register(harness.selectedView, for: harness.selectedTabId)
        harness.registry.revealSelection(harness.selectedTabId)
        XCTAssertGreaterThan(harness.scrollView.contentView.bounds.origin.x, 0)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: harness.scrollView
        )
        let userOffset: CGFloat = 120
        harness.scrollView.contentView.scroll(to: NSPoint(x: userOffset, y: 0))
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)

        XCTAssertEqual(
            harness.scrollView.contentView.bounds.origin.x,
            userOffset,
            accuracy: 0.5,
            "An intentional live user scroll must replace any earlier programmatic reveal target."
        )
    }

    func testVerticalMouseWheelScrollsOverflowingStripHorizontally() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.registry.attachScrollView(harness.scrollView)
        let pointInStrip = harness.scrollView.convert(NSPoint(x: 100, y: 10), to: nil)

        XCTAssertTrue(
            harness.registry.scrollHorizontallyForMouseWheel(
                deltaX: 0,
                deltaY: -3,
                hasPreciseScrollingDeltas: false,
                locationInWindow: pointInStrip,
                window: harness.window
            )
        )
        let scrolledOffset = harness.scrollView.contentView.bounds.origin.x
        XCTAssertGreaterThan(scrolledOffset, 0, "Wheel down must move toward the trailing overflowed tabs.")

        harness.registry.scrollHorizontallyForMouseWheel(
            deltaX: 0,
            deltaY: -1000,
            hasPreciseScrollingDeltas: false,
            locationInWindow: pointInStrip,
            window: harness.window
        )
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin.x, 400, accuracy: 0.5)

        harness.registry.scrollHorizontallyForMouseWheel(
            deltaX: 0,
            deltaY: 1000,
            hasPreciseScrollingDeltas: false,
            locationInWindow: pointInStrip,
            window: harness.window
        )
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    func testMouseWheelLeavesTrackpadAndOutsideEventsAlone() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.registry.attachScrollView(harness.scrollView)
        let pointInStrip = harness.scrollView.convert(NSPoint(x: 100, y: 10), to: nil)

        XCTAssertFalse(
            harness.registry.scrollHorizontallyForMouseWheel(
                deltaX: 0,
                deltaY: -3,
                hasPreciseScrollingDeltas: true,
                locationInWindow: pointInStrip,
                window: harness.window
            ),
            "Trackpad scrolling keeps its native handling."
        )
        XCTAssertFalse(
            harness.registry.scrollHorizontallyForMouseWheel(
                deltaX: -3,
                deltaY: 0,
                hasPreciseScrollingDeltas: false,
                locationInWindow: pointInStrip,
                window: harness.window
            ),
            "Horizontal wheel deltas already scroll the strip natively."
        )
        XCTAssertFalse(
            harness.registry.scrollHorizontallyForMouseWheel(
                deltaX: 0,
                deltaY: -3,
                hasPreciseScrollingDeltas: false,
                locationInWindow: NSPoint(x: 100, y: 500),
                window: harness.window
            ),
            "Wheel events outside the strip belong to whatever is under the pointer."
        )
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    func testMouseWheelPassesThroughWhenTabsFit() throws {
        let harness = try makeGeometryRegistryHarness()
        defer { harness.window.orderOut(nil) }

        harness.scrollView.documentView?.setFrameSize(
            NSSize(width: 150, height: TabBarMetrics.barHeight)
        )
        harness.registry.attachScrollView(harness.scrollView)
        let pointInStrip = harness.scrollView.convert(NSPoint(x: 100, y: 10), to: nil)

        XCTAssertFalse(
            harness.registry.scrollHorizontallyForMouseWheel(
                deltaX: 0,
                deltaY: -3,
                hasPreciseScrollingDeltas: false,
                locationInWindow: pointInStrip,
                window: harness.window
            )
        )
    }

    func testSelectedOverflowTabTracksLiveGeometryAndFullyRevealsChrome() throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 520, height: TabBarMetrics.barHeight),
            tabCount: 3,
            selectedIndex: 0
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try tabBarScrollView(in: harness.hostingView)
        let chromeView = try XCTUnwrap(
            descendants(
                ofType: TabBarSelectionChromeView.ChromeNSView.self,
                in: harness.hostingView
            ).first
        )
        XCTAssertEqual(maxHorizontalOffset(in: scrollView), 0, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)

        let newTab = TabItem(
            title: "New browser tab",
            icon: "globe",
            kind: "browser"
        )
        harness.pane.addTab(newTab)

        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            guard chromeView.selectedTabId == newTab.id,
                  let selectedFrame = chromeView.geometryRegistry?.frame(
                    for: newTab.id,
                    in: chromeView
                  ) else {
                return false
            }
            return selectedFrame.minX >= chromeView.bounds.minX - 0.5
                && selectedFrame.maxX <= chromeView.bounds.maxX + 0.5
        }

        let initialSelectedFrame = try XCTUnwrap(
            chromeView.geometryRegistry?.frame(for: newTab.id, in: chromeView)
        )
        let newTabIndex = try XCTUnwrap(
            harness.pane.tabs.firstIndex(where: { $0.id == newTab.id })
        )
        harness.pane.tabs[newTabIndex].title = String(repeating: "Long browser title ", count: 8)

        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            guard let selectedFrame = chromeView.geometryRegistry?.frame(
                for: newTab.id,
                in: chromeView
            ) else {
                return false
            }
            return selectedFrame.width > initialSelectedFrame.width + 1
                && selectedFrame.minX >= chromeView.bounds.minX - 0.5
                && selectedFrame.maxX <= chromeView.bounds.maxX + 0.5
        }

        let selectedFrame = try XCTUnwrap(
            chromeView.geometryRegistry?.frame(for: newTab.id, in: chromeView)
        )
        XCTAssertEqual(chromeView.selectedTabId, newTab.id)
        XCTAssertGreaterThan(
            selectedFrame.width,
            initialSelectedFrame.width + 1,
            "The regression requires the selected browser tab's live frame to grow."
        )
        XCTAssertGreaterThan(
            maxHorizontalOffset(in: scrollView),
            0,
            "The test must transition the tab strip from fitting to overflowing."
        )
        XCTAssertGreaterThan(
            scrollView.contentView.bounds.origin.x,
            0,
            "Selecting a newly inserted overflow tab must move the live AppKit viewport."
        )
        XCTAssertGreaterThanOrEqual(
            selectedFrame.minX,
            chromeView.bounds.minX - 0.5,
            "The selected tab and its selection chrome must not be clipped at the leading edge."
        )
        XCTAssertLessThanOrEqual(
            selectedFrame.maxX,
            chromeView.bounds.maxX + 0.5,
            "The selected tab and its selection chrome must not be clipped at the trailing edge."
        )
    }

    func testSelectedTabStaysRevealedWhenEarlierTabGrowthMovesItsLiveFrame() throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 520, height: TabBarMetrics.barHeight),
            tabCount: 4,
            selectedIndex: 3
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try tabBarScrollView(in: harness.hostingView)
        let chromeView = try XCTUnwrap(
            descendants(
                ofType: TabBarSelectionChromeView.ChromeNSView.self,
                in: harness.hostingView
            ).first
        )
        let selectedTabId = try XCTUnwrap(harness.pane.selectedTabId)
        XCTAssertEqual(maxHorizontalOffset(in: scrollView), 0, accuracy: 0.5)

        harness.pane.tabs[0].title = String(repeating: "Long earlier title ", count: 8)

        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            guard maxHorizontalOffset(in: scrollView) > 0,
                  let selectedFrame = chromeView.geometryRegistry?.frame(
                    for: selectedTabId,
                    in: chromeView
                  ) else {
                return false
            }
            return scrollView.contentView.bounds.origin.x > 0
                && selectedFrame.minX >= chromeView.bounds.minX - 0.5
                && selectedFrame.maxX <= chromeView.bounds.maxX + 0.5
        }

        let selectedFrame = try XCTUnwrap(
            chromeView.geometryRegistry?.frame(for: selectedTabId, in: chromeView)
        )
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
        XCTAssertGreaterThanOrEqual(selectedFrame.minX, chromeView.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(
            selectedFrame.maxX,
            chromeView.bounds.maxX + 0.5,
            "A sibling layout change must keep scrolling and selection chrome on the same live frame."
        )
    }

    func testSelectingTabBehindActionLaneRevealsItsCloseAffordance() throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 520, height: TabBarMetrics.barHeight),
            tabCount: 4,
            selectedIndex: 0,
            showSplitButtons: true
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try tabBarScrollView(in: harness.hostingView)
        let chromeView = try XCTUnwrap(
            descendants(
                ofType: TabBarSelectionChromeView.ChromeNSView.self,
                in: harness.hostingView
            ).first
        )
        let targetTab = try XCTUnwrap(harness.pane.tabs.last)
        let actionLaneWidth = TabBarStyling.splitButtonsBackdropWidth(
            buttonCount: BonsplitConfiguration.SplitActionButton.defaults.count
        )
        let unobscuredMaxX = chromeView.bounds.maxX - actionLaneWidth

        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            guard maxHorizontalOffset(in: scrollView) > 0,
                  let targetFrame = chromeView.geometryRegistry?.frame(
                    for: targetTab.id,
                    in: chromeView
                  ) else {
                return false
            }
            return targetFrame.maxX > unobscuredMaxX + 1
                && targetFrame.maxX <= chromeView.bounds.maxX + 0.5
        }

        let obscuredFrame = try XCTUnwrap(
            chromeView.geometryRegistry?.frame(for: targetTab.id, in: chromeView)
        )
        XCTAssertGreaterThan(
            obscuredFrame.maxX,
            unobscuredMaxX + 1,
            "The regression requires the target tab's trailing close affordance to begin behind the action lane."
        )
        XCTAssertLessThanOrEqual(
            obscuredFrame.maxX,
            chromeView.bounds.maxX + 0.5,
            "The target must still be inside the raw clip view so the test distinguishes occlusion from ordinary clipping."
        )
        let initialOffset = scrollView.contentView.bounds.origin.x

        harness.pane.selectTab(targetTab.id)
        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            guard chromeView.selectedTabId == targetTab.id,
                  let selectedFrame = chromeView.geometryRegistry?.frame(
                    for: targetTab.id,
                    in: chromeView
                  ) else {
                return false
            }
            return selectedFrame.maxX <= unobscuredMaxX + 0.5
        }

        let selectedFrame = try XCTUnwrap(
            chromeView.geometryRegistry?.frame(for: targetTab.id, in: chromeView)
        )
        XCTAssertGreaterThan(
            scrollView.contentView.bounds.origin.x,
            initialOffset + 0.5,
            "Selecting a tab under the action lane must shift the strip to expose its trailing controls."
        )
        XCTAssertLessThanOrEqual(
            selectedFrame.maxX,
            unobscuredMaxX + 0.5,
            "The selected tab, including its close affordance, must end before the action lane begins."
        )
    }

    func testViewportResizeKeepsLeadingAnchoredWhenTabStripWasLeadingAligned() throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 900, height: TabBarMetrics.barHeight),
            tabCount: 8,
            selectedIndex: 2
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try tabBarScrollView(in: harness.hostingView)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)

        harness.window.setContentSize(NSSize(width: 240, height: TabBarMetrics.barHeight))
        harness.hostingView.frame = harness.window.contentView?.bounds ?? harness.hostingView.frame
        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            abs(scrollView.contentView.bounds.origin.x) <= 0.5
        }

        XCTAssertEqual(
            scrollView.contentView.bounds.origin.x,
            0,
            accuracy: 0.5,
            "A pure pane/window resize must preserve the leading tab-strip anchor instead of recentering the selected tab and shifting icons."
        )
    }

    func testViewportResizeClampsExistingOverflowOffsetToNewRange() throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 240, height: TabBarMetrics.barHeight),
            tabCount: 8,
            selectedIndex: 7
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try tabBarScrollView(in: harness.hostingView)
        let initialMaxOffset = maxHorizontalOffset(in: scrollView)
        XCTAssertGreaterThan(initialMaxOffset, 0)

        scrollView.contentView.scroll(to: NSPoint(x: initialMaxOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, initialMaxOffset, accuracy: 0.5)

        harness.window.setContentSize(NSSize(width: 360, height: TabBarMetrics.barHeight))
        harness.hostingView.frame = harness.window.contentView?.bounds ?? harness.hostingView.frame
        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            let expectedOffset = maxHorizontalOffset(in: scrollView)
            return expectedOffset > 0
                && abs(scrollView.contentView.bounds.origin.x - expectedOffset) <= 0.5
        }

        let expectedOffset = maxHorizontalOffset(in: scrollView)
        XCTAssertGreaterThan(expectedOffset, 0)
        XCTAssertLessThan(expectedOffset, initialMaxOffset)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.x,
            expectedOffset,
            accuracy: 0.5,
            "A resize that reduces the valid scroll range must clamp the existing offset instead of resetting or recentering the tab strip."
        )
    }

    func testContentShrinkReturnsFittingStripToLeadingEdge() throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 360, height: TabBarMetrics.barHeight),
            tabCount: 8,
            selectedIndex: 0
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try tabBarScrollView(in: harness.hostingView)
        let initialMaxOffset = maxHorizontalOffset(in: scrollView)
        XCTAssertGreaterThan(initialMaxOffset, 0)
        scrollView.contentView.scroll(to: NSPoint(x: initialMaxOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        harness.pane.tabs = Array(harness.pane.tabs.prefix(2))
        settleLayout(in: harness.window, hostingView: harness.hostingView) {
            maxHorizontalOffset(in: scrollView) <= 0.5
                && abs(scrollView.contentView.bounds.origin.x) <= 0.5
        }

        XCTAssertEqual(maxHorizontalOffset(in: scrollView), 0, accuracy: 0.5)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.x,
            0,
            accuracy: 0.5,
            "A strip that stops overflowing must not retain a stale clip-view offset."
        )
    }

    func testViewportResizeDoesNotUndoLaterValidOffset() async throws {
        let harness = try makeTabBarHarness(
            initialSize: NSSize(width: 240, height: TabBarMetrics.barHeight),
            tabCount: 8,
            selectedIndex: 7
        )
        defer { harness.window.orderOut(nil) }

        let scrollView = try tabBarScrollView(in: harness.hostingView)
        let initialMaxOffset = maxHorizontalOffset(in: scrollView)
        XCTAssertGreaterThan(initialMaxOffset, 0)

        scrollView.contentView.scroll(to: NSPoint(x: initialMaxOffset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        var laterValidOffset: CGFloat?
        let laterScrollApplied = expectation(description: "later valid scroll applied")
        DispatchQueue.main.async {
            let validOffset = self.maxHorizontalOffset(in: scrollView) / 2
            laterValidOffset = validOffset
            NotificationCenter.default.post(
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollView
            )
            scrollView.contentView.scroll(to: NSPoint(x: validOffset, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            laterScrollApplied.fulfill()
        }

        harness.window.setContentSize(NSSize(width: 360, height: TabBarMetrics.barHeight))
        harness.hostingView.frame = harness.window.contentView?.bounds ?? harness.hostingView.frame
        harness.window.contentView?.layoutSubtreeIfNeeded()
        harness.hostingView.layoutSubtreeIfNeeded()

        let queuedCorrectionsDrained = expectation(description: "queued corrections drained")
        DispatchQueue.main.async {
            queuedCorrectionsDrained.fulfill()
        }
        await fulfillment(of: [laterScrollApplied, queuedCorrectionsDrained], timeout: 1)
        let expectedOffset = try XCTUnwrap(laterValidOffset)
        XCTAssertEqual(
            scrollView.contentView.bounds.origin.x,
            expectedOffset,
            accuracy: 0.5,
            "The queued clamp retry must not overwrite a later scroll position that is already inside the resized tab strip's valid range."
        )
    }

    private struct TabBarHarness {
        let window: NSWindow
        let hostingView: NSView
        let pane: PaneState
    }

    private struct GeometryRegistryHarness {
        let window: NSWindow
        let scrollView: NSScrollView
        let selectedView: NSView
        let selectedTabId: UUID
        let registry: TabBarItemGeometryRegistry
    }

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
        let documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 600, height: viewportSize.height)
        )
        let selectedView = NSView(
            frame: NSRect(x: 480, y: 0, width: 100, height: viewportSize.height)
        )
        let selectedTabId = UUID()
        let registry = TabBarItemGeometryRegistry()

        documentView.addSubview(selectedView)
        scrollView.documentView = documentView
        contentView.addSubview(scrollView)
        window.makeKeyAndOrderFront(nil)

        return GeometryRegistryHarness(
            window: window,
            scrollView: scrollView,
            selectedView: selectedView,
            selectedTabId: selectedTabId,
            registry: registry
        )
    }

    private func makeTabBarHarness(
        initialSize: NSSize,
        tabCount: Int,
        selectedIndex: Int,
        showSplitButtons: Bool = false
    ) throws -> TabBarHarness {
        let controller = BonsplitController(configuration: BonsplitConfiguration(appearance: .default))
        controller.tabShortcutHintsEnabled = false
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)

        let tabs = (0..<tabCount).map { index in
            TabItem(title: "Terminal \(index + 1)", icon: "terminal.fill", kind: "terminal")
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs[selectedIndex].id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: showSplitButtons)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        let contentView = try XCTUnwrap(window.contentView)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        settleLayout(in: window, hostingView: hostingView) {
            tabBarScrollViews(in: hostingView).count == 1
        }

        return TabBarHarness(window: window, hostingView: hostingView, pane: pane)
    }

    private func settleLayout(
        in window: NSWindow,
        hostingView: NSView,
        until condition: () -> Bool
    ) {
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            if condition() {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        window.contentView?.layoutSubtreeIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
    }

    private func tabBarScrollView(
        in root: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSScrollView {
        let matches = tabBarScrollViews(in: root)
        let widestWidth = matches.map(\.frame.width).max()
        let widestMatches = matches.filter { scrollView in
            guard let widestWidth else { return false }
            return abs(scrollView.frame.width - widestWidth) <= 0.5
        }
        XCTAssertEqual(
            widestMatches.count,
            1,
            "The harness should expose exactly one tab-bar-sized scroll view.",
            file: file,
            line: line
        )
        return try XCTUnwrap(widestMatches.first, file: file, line: line)
    }

    private func tabBarScrollViews(in root: NSView) -> [NSScrollView] {
        descendants(ofType: NSScrollView.self, in: root).filter { scrollView in
            let documentHeight = max(
                scrollView.documentView?.frame.height ?? 0,
                scrollView.documentView?.bounds.height ?? 0
            )
            return abs(scrollView.frame.height - TabBarMetrics.barHeight) <= 0.5
                && abs(documentHeight - TabBarMetrics.barHeight) <= 0.5
                && scrollView.frame.width > 0
        }
    }

    private func maxHorizontalOffset(in scrollView: NSScrollView) -> CGFloat {
        let documentWidth = max(
            scrollView.documentView?.frame.width ?? 0,
            scrollView.documentView?.bounds.width ?? 0
        )
        return max(0, documentWidth - scrollView.contentView.bounds.width)
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
