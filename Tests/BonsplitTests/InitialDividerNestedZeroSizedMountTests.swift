import AppKit
@testable import Bonsplit
import SwiftUI
import XCTest

/// End-to-end shape for the layout-edge retry: a nested split mounted at zero size.
///
/// A `BonsplitView` can be added to a window before its host has a real frame —
/// docking a panel does exactly this — and sit at zero size for a few runloop
/// turns before the first real resize arrives. The old retry counted those turns
/// as attempts, so both dividers burned their budget reading an empty bounds and
/// the fallback recorded the seeded positions as applied. After expansion the
/// outer divider self-repaired on the first real resize, but that repair holds
/// the resize synchronization depth while it recursively lays out its children,
/// so the nested divider never got its own repair: the view stayed at 50/50
/// while the model carried the seeded fraction.
///
/// The assertions therefore read actual `NSSplitView.arrangedSubviews` frames.
/// The model (and anything derived from it, like snapshot fractions) still holds
/// the seeded values on broken code — only the real frames show the defect.
@MainActor
final class InitialDividerNestedZeroSizedMountTests: XCTestCase {
    func testNestedSeededFractionsSurviveZeroSizedMountThenFirstRealLayout() throws {
        var appearance = BonsplitConfiguration.Appearance.default
        appearance.minimumPaneWidth = 48
        appearance.minimumPaneHeight = 48
        appearance.enableAnimations = false
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(
                dividerPositionRange: 0.1...0.9,
                appearance: appearance
            )
        )

        // Three stacked panes: outer divider at 0.20, nested divider at 0.375.
        _ = controller.createTab(title: "A")
        let top = try XCTUnwrap(controller.focusedPaneId)
        let middle = try XCTUnwrap(
            controller.splitPane(top, orientation: .vertical, initialDividerPosition: 0.2)
        )
        XCTAssertNotNil(
            controller.splitPane(middle, orientation: .vertical, initialDividerPosition: 0.375)
        )

        let host = NSHostingView(
            rootView: BonsplitView(controller: controller) { _, _ in
                Color.clear
            } emptyPane: { _ in
                Color.clear
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 1000),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        defer { window.orderOut(nil) }
        let content = try XCTUnwrap(window.contentView)

        // Mount at zero size and wait until both splits actually exist before
        // starting the dwell, so the retries are provably armed while the
        // bounds are still empty.
        host.frame = .zero
        content.addSubview(host)
        window.makeKeyAndOrderFront(nil)
        content.layoutSubtreeIfNeeded()
        let mountDeadline = Date().addingTimeInterval(1.0)
        while Date() < mountDeadline, !bothSplitsMounted(in: host) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            content.layoutSubtreeIfNeeded()
        }
        let mounted = allSplitViews(in: host)
        XCTAssertEqual(mounted.count, 2, "Both splits should be mounted")
        for split in mounted {
            XCTAssertEqual(split.arrangedSubviews.count, 2)
            XCTAssertEqual(
                split.bounds.height, 0, accuracy: 0.01,
                "The dwell must start while the split still has no usable height"
            )
        }

        // Dwell at zero size. This is the window in which the old retry spent
        // its whole budget on empty bounds (twelve turns inside 13ms), so
        // 150ms of runloop turns exhausts it many times over.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        content.layoutSubtreeIfNeeded()

        // First real resize: the host gets its actual frame and AppKit lays out.
        host.frame = content.bounds
        content.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()

        // Wait (bounded) for both dividers to land, then assert real frames.
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline, !nestedFractionsMatch(in: host) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            content.layoutSubtreeIfNeeded()
        }

        let splits = allSplitViews(in: host).sorted { $0.bounds.height > $1.bounds.height }
        XCTAssertEqual(splits.count, 2)
        let outer = try XCTUnwrap(splits.first)
        let inner = try XCTUnwrap(splits.last)
        XCTAssertEqual(
            outer.arrangedSubviews[0].frame.height
                / (outer.bounds.height - outer.dividerThickness),
            0.2,
            accuracy: 0.02,
            "Outer divider must land on its seeded fraction"
        )
        XCTAssertEqual(
            inner.arrangedSubviews[0].frame.height
                / (inner.bounds.height - inner.dividerThickness),
            0.375,
            accuracy: 0.02,
            "Nested divider must land on its seeded fraction, not the 50/50 entry "
                + "default it is stranded at when the outer repair swallows its layout"
        )
    }

    private func bothSplitsMounted(in root: NSView) -> Bool {
        let splits = allSplitViews(in: root)
        return splits.count == 2 && splits.allSatisfy { $0.arrangedSubviews.count == 2 }
    }

    private func nestedFractionsMatch(in root: NSView) -> Bool {
        let splits = allSplitViews(in: root).sorted { $0.bounds.height > $1.bounds.height }
        guard splits.count == 2,
              let outer = splits.first, let inner = splits.last,
              outer.bounds.height > outer.dividerThickness,
              inner.bounds.height > inner.dividerThickness,
              !outer.arrangedSubviews.isEmpty, !inner.arrangedSubviews.isEmpty
        else { return false }
        let outerFraction = outer.arrangedSubviews[0].frame.height
            / (outer.bounds.height - outer.dividerThickness)
        let innerFraction = inner.arrangedSubviews[0].frame.height
            / (inner.bounds.height - inner.dividerThickness)
        return abs(outerFraction - 0.2) <= 0.02 && abs(innerFraction - 0.375) <= 0.02
    }

    private func allSplitViews(in root: NSView) -> [NSSplitView] {
        var result: [NSSplitView] = []
        if let split = root as? NSSplitView { result.append(split) }
        for child in root.subviews {
            result += allSplitViews(in: child)
        }
        return result
    }
}
