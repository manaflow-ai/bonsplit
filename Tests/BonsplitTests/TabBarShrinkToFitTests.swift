import AppKit
@testable import Bonsplit
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct TabBarShrinkToFitTests {
    @Test
    func crowdedTabsStayInsideViewportWhenResized() throws {
        let appearance = BonsplitConfiguration.Appearance(tabWidthMode: .shrink)
        let controller = BonsplitController(configuration: BonsplitConfiguration(appearance: appearance))
        controller.tabShortcutHintsEnabled = false
        let pane = try #require(controller.internalController.rootNode.allPanes.first)
        pane.tabs = (0..<9).map { index in
            TabItem(title: "Agent \(index + 1) with a long session title", icon: "terminal.fill", kind: "terminal")
        }
        pane.selectedTabId = pane.tabs.last?.id
        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 30),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        for width: CGFloat in [600, 420, 900] {
            window.setContentSize(NSSize(width: width, height: 30))
            for _ in 0..<10 {
                hostingView.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date.now.addingTimeInterval(0.01))
            }
            let chrome = try #require(descendants(TabBarSelectionChromeView.ChromeNSView.self, in: hostingView).first)
            let frames = try #require(chrome.geometryRegistry?.frames(for: pane.tabs.map(\.id), in: chrome))
            #expect(frames.count == pane.tabs.count)
            for tab in pane.tabs {
                let frame = try #require(frames[tab.id])
                #expect(frame.width > 0)
                #expect(frame.minX >= -0.5)
                // Every tab must precede the action buttons, not just the pane edge.
                let layout = TabBarLayout(
                    tabBarHeight: 30, availableWidth: width,
                    splitButtonCount: appearance.splitButtons.count,
                    splitButtonLaneVisible: true, reservesSplitButtonLane: true
                )
                #expect(frame.maxX <= width - layout.trailingTabContentInset + 0.5)
            }
        }
    }

    private func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { descendants(type, in: $0) }
    }
}
