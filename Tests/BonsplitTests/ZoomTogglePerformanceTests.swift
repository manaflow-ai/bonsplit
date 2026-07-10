import XCTest
@testable import Bonsplit
import AppKit
import SwiftUI

/// Benchmarks the wall-clock cost of toggling pane zoom (maximize/minimize) with
/// multiple panes open, hosted in a real NSWindow like the app does.
///
/// Run with:
///   swift test --filter ZoomTogglePerformanceTests
///
/// The benchmark reports, per toggle direction:
///   - settle latency: time from togglePaneZoom() until the AppKit hierarchy
///     reflects the final layout (zoomed pane fills the container, or all panes
///     are back at their split frames)
///   - AppKit content-view churn: how many pane content NSViews were created
///     during the toggle (teardown/rebuild cost that portals/terminals pay)
final class ZoomTogglePerformanceTests: XCTestCase {

    /// NSView whose lifecycle we can count, standing in for expensive pane content
    /// (Metal-backed terminals in cmux).
    @MainActor
    private final class BenchContentNSView: NSView {
        static var instancesCreated = 0
        let tag2: Int

        init(tag2: Int) {
            self.tag2 = tag2
            super.init(frame: .zero)
            Self.instancesCreated += 1
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError("unsupported") }
    }

    private struct BenchContent: NSViewRepresentable {
        let index: Int

        func makeNSView(context: Context) -> NSView {
            BenchContentNSView(tag2: index)
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    @MainActor
    private func collectBenchViews(in root: NSView) -> [BenchContentNSView] {
        var result: [BenchContentNSView] = []
        var queue: [NSView] = [root]
        while let view = queue.popLast() {
            if let bench = view as? BenchContentNSView {
                result.append(bench)
            }
            queue.append(contentsOf: view.subviews)
        }
        return result
    }

    @MainActor
    private func pump(_ seconds: TimeInterval = 0.001) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor
    private func pumpUntil(
        timeout: TimeInterval,
        window: NSWindow,
        _ condition: () -> Bool
    ) -> TimeInterval? {
        _ = window
        let start = CFAbsoluteTimeGetCurrent()
        while CFAbsoluteTimeGetCurrent() - start < timeout {
            if condition() {
                return CFAbsoluteTimeGetCurrent() - start
            }
            pump()
        }
        return condition() ? CFAbsoluteTimeGetCurrent() - start : nil
    }

    /// True when the view is attached to a window and not hidden anywhere in its chain.
    @MainActor
    private func isEffectivelyVisible(_ view: NSView) -> Bool {
        guard view.window != nil else { return false }
        return !view.isHiddenOrHasHiddenAncestor
    }

    @MainActor
    func testZoomToggleLatencyWithEightPanes() throws {
        let paneCount = 8
        let cycles = 12

        let appearance = BonsplitConfiguration.Appearance(enableAnimations: false)
        let configuration = BonsplitConfiguration(appearance: appearance)
        let controller = BonsplitController(configuration: configuration)

        _ = controller.createTab(title: "pane-0")
        guard var currentPane = controller.focusedPaneId else {
            XCTFail("Expected focused pane")
            return
        }

        // Build an 8-pane layout alternating split orientation, like a busy
        // real-world workspace.
        for index in 1..<paneCount {
            let orientation: SplitOrientation = index % 2 == 0 ? .vertical : .horizontal
            guard let newPane = controller.splitPane(currentPane, orientation: orientation) else {
                XCTFail("Expected splitPane to create pane \(index)")
                return
            }
            _ = controller.createTab(title: "pane-\(index)", inPane: newPane)
            currentPane = newPane
        }
        XCTAssertEqual(controller.allPaneIds.count, paneCount)

        let hostingView = NSHostingView(
            rootView: BonsplitView(controller: controller) { tab, _ in
                BenchContent(index: abs(tab.title.hashValue))
            } emptyPane: { _ in
                Color.clear
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()

        // Let the initial 8-pane layout settle fully.
        let initialSettle = pumpUntil(timeout: 5.0, window: window) {
            collectBenchViews(in: hostingView).filter { isEffectivelyVisible($0) }.count == paneCount
        }
        XCTAssertNotNil(initialSettle, "Initial \(paneCount)-pane layout never settled")
        pump(0.1)

        guard let zoomPane = controller.focusedPaneId else {
            XCTFail("Expected focused pane to zoom")
            return
        }

        var zoomInTimes: [Double] = []
        var zoomOutTimes: [Double] = []
        var zoomInChurn: [Int] = []
        var zoomOutChurn: [Int] = []

        for cycle in 0..<(cycles + 1) {
            // --- Zoom in (maximize) ---
            let createdBeforeIn = BenchContentNSView.instancesCreated
            let zoomInStart = CFAbsoluteTimeGetCurrent()
            XCTAssertTrue(controller.togglePaneZoom(inPane: zoomPane))
            let zoomInSettle = pumpUntil(timeout: 5.0, window: window) {
                let visible = collectBenchViews(in: hostingView).filter { isEffectivelyVisible($0) }
                guard visible.count == 1, let only = visible.first else { return false }
                // Zoomed pane content should span (nearly) the full container width.
                return only.frame.width >= hostingView.bounds.width - 4
            }
            let zoomInElapsed = CFAbsoluteTimeGetCurrent() - zoomInStart
            XCTAssertNotNil(zoomInSettle, "Zoom-in never settled on cycle \(cycle)")
            let inChurn = BenchContentNSView.instancesCreated - createdBeforeIn
            pump(0.05)

            // --- Zoom out (minimize) ---
            let createdBeforeOut = BenchContentNSView.instancesCreated
            let zoomOutStart = CFAbsoluteTimeGetCurrent()
            XCTAssertTrue(controller.togglePaneZoom(inPane: zoomPane))
            let zoomOutSettle = pumpUntil(timeout: 5.0, window: window) {
                let visible = collectBenchViews(in: hostingView).filter { isEffectivelyVisible($0) }
                guard visible.count == paneCount else { return false }
                // Every pane must have a real, laid-out frame again.
                return visible.allSatisfy { $0.frame.width > 1 && $0.frame.height > 1 }
            }
            let zoomOutElapsed = CFAbsoluteTimeGetCurrent() - zoomOutStart
            XCTAssertNotNil(zoomOutSettle, "Zoom-out never settled on cycle \(cycle)")
            let outChurn = BenchContentNSView.instancesCreated - createdBeforeOut
            pump(0.05)

            // Skip the first cycle as warmup.
            if cycle > 0 {
                zoomInTimes.append(zoomInElapsed * 1000)
                zoomOutTimes.append(zoomOutElapsed * 1000)
                zoomInChurn.append(inChurn)
                zoomOutChurn.append(outChurn)
            }
        }

        func stats(_ values: [Double]) -> String {
            let sorted = values.sorted()
            let median = sorted[sorted.count / 2]
            let mean = values.reduce(0, +) / Double(values.count)
            return String(
                format: "median=%.1fms mean=%.1fms min=%.1fms max=%.1fms",
                median, mean, sorted.first ?? 0, sorted.last ?? 0
            )
        }

        print("[ZOOM-BENCH] panes=\(paneCount) cycles=\(cycles)")
        print("[ZOOM-BENCH] zoom-in  (maximize): \(stats(zoomInTimes))")
        print("[ZOOM-BENCH] zoom-out (minimize): \(stats(zoomOutTimes))")
        print("[ZOOM-BENCH] content-view churn per zoom-in:  \(zoomInChurn)")
        print("[ZOOM-BENCH] content-view churn per zoom-out: \(zoomOutChurn)")
    }
}
