import AppKit
@testable import Bonsplit
import SwiftUI
import Testing

@Suite("Active pane chrome")
@MainActor
struct TabActivePaneInvariantTests {
    @Test("Only the focused pane renders active during a tab drag")
    func onlyFocusedPaneRendersActiveDuringTabDrag() throws {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(appearance: .default)
        )
        controller.tabShortcutHintsEnabled = false

        let sourcePane = try #require(controller.internalController.focusedPane)
        let sourceTab = try #require(sourcePane.selectedTab)
        let focusedPaneId = try #require(
            controller.splitPane(sourcePane.id, orientation: .horizontal)
        )
        let focusedPane = try #require(
            controller.internalController.paneState(for: focusedPaneId)
        )
        _ = controller.internalController.beginTabDrag(sourceTab, from: sourcePane.id)

        #expect(controller.focusedPaneId == focusedPaneId)

        let sourceColor = try indicatorColor(
            controller: controller,
            pane: sourcePane,
            isFocused: false
        )
        let focusedColor = try indicatorColor(
            controller: controller,
            pane: focusedPane,
            isFocused: true
        )

        #expect(saturation(of: sourceColor) < 0.1)
        #expect(saturation(of: focusedColor) > 0.4)
    }

    private func indicatorColor(
        controller: BonsplitController,
        pane: PaneState,
        isFocused: Bool
    ) throws -> NSColor {
        let hostingView = NSHostingView(
            rootView: TabBarView(
                pane: pane,
                isFocused: isFocused,
                showSplitButtons: false
            )
            .environment(controller)
            .environment(controller.internalController)
        )
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: 160,
            height: TabBarMetrics.barHeight
        )
        hostingView.layoutSubtreeIfNeeded()

        let chrome = try #require(
            firstDescendant(
                ofType: TabBarSelectionChromeView.ChromeNSView.self,
                in: hostingView
            )
        )
        return chrome.indicatorColor
    }

    private func saturation(of color: NSColor) -> CGFloat {
        color.usingColorSpace(.deviceRGB)?.saturationComponent ?? 0
    }

    private func firstDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
