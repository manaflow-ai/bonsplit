import AppKit
@testable import Bonsplit
import XCTest

#if DEBUG
@MainActor
final class TabBarLayoutFeedbackTests: XCTestCase {
    func testScrollingManyTabsKeepsPlatformGeometryLive() throws {
        let size = NSSize(width: 420, height: 180)
        let controller = BonsplitController(configuration: .init(appearance: .default))
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        let tabs = (0..<50).map { index in
            TabItem(
                title: "Terminal \(index + 1) \(String(repeating: "x", count: index % 17))",
                icon: "terminal.fill",
                kind: "terminal"
            )
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs.first?.id

        let renderer = BonsplitViewController(controller: controller) { _, _ in
            let child = NSViewController()
            child.view = NSView()
            return child
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.contentViewController = renderer
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        settleLayout(in: window, root: renderer.view)

        let tabBar = try XCTUnwrap(descendants(ofType: BonsplitNativeTabBarView.self, in: renderer.view).first)
        let scrollView = tabBar.scrollViewForTesting
        let firstView = try XCTUnwrap(tabBar.tabViewsForTesting[tabs[0].id])
        let initialFrame = tabBar.convert(firstView.bounds, from: firstView)
        let maximumOffset = max(
            0,
            max(scrollView.documentView?.frame.width ?? 0, scrollView.documentView?.bounds.width ?? 0)
                - scrollView.contentView.bounds.width
        )
        XCTAssertGreaterThan(maximumOffset, 0)

        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scrollView)
        for step in 1...8 {
            scrollView.contentView.scroll(to: NSPoint(x: maximumOffset * CGFloat(step) / 8, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            settleLayout(in: window, root: renderer.view, passes: 2)
        }

        let scrolledFrame = tabBar.convert(firstView.bounds, from: firstView)
        XCTAssertEqual(tabBar.tabViewsForTesting.count, tabs.count)
        XCTAssertEqual(scrolledFrame.minX, initialFrame.minX - maximumOffset, accuracy: 1)
    }

    private func settleLayout(in window: NSWindow, root: NSView, passes: Int = 8) {
        for _ in 0..<passes {
            window.contentView?.layoutSubtreeIfNeeded()
            root.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.005))
        }
    }

    private func descendants<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var matches = (root as? T).map { [$0] } ?? []
        for subview in root.subviews {
            matches.append(contentsOf: descendants(ofType: type, in: subview))
        }
        return matches
    }
}
#endif
