import AppKit
import Observation
import SwiftUI
import Testing
@testable import Bonsplit

/// The split root observes its nested splits with `withObservationTracking`.
/// Those registrations are one-shot, and arming a new one on every
/// `updateNSView` left one behind per SwiftUI update. Over a long session the
/// leftovers grew without bound: each tracked change re-rendered the whole
/// tree once per leftover, and SwiftUI's own observation of the same split
/// state slowed with the registrar (Sentry CMUXTERM-MACOS-3ZVC).
@Suite("Split tree observation")
@MainActor
struct SplitTreeObservationTests {
    @Observable
    final class Tick {
        var value = 0
    }

    struct Host: View {
        let controller: BonsplitController
        let tick: Tick

        var body: some View {
            // Reading the tick re-evaluates this body, which hands the split
            // root new content builders and so drives its `updateNSView`.
            let value = tick.value
            BonsplitView(controller: controller) { _, _ in
                Text("\(value)")
            } emptyPane: { _ in
                Color.clear
            }
        }
    }

    @Test("Repeated SwiftUI updates do not multiply tree re-renders for one change")
    func repeatedUpdatesKeepOneTreeObservation() async throws {
        _ = NSApplication.shared
        let controller = BonsplitController()
        controller.createTab(title: "First")
        let firstPane = try #require(controller.focusedPaneId)
        _ = try #require(controller.splitPane(firstPane, orientation: .horizontal))

        let tick = Tick()
        let hostingView = NSHostingView(rootView: Host(controller: controller, tick: tick))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer {
            hostingView.removeFromSuperview()
            window.orderOut(nil)
        }
        let contentView = try #require(window.contentView)
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)
        await settle(contentView)

        let splitView = try #require(Self.firstSplitView(in: hostingView))
        let coordinator = try #require(
            splitView.delegate as? SplitContainerView<Text, Color>.Coordinator
        )

        for value in 1...25 {
            tick.value = value
            await settle(contentView)
        }
        let rendersBeforeChange = coordinator.observedTreeRenderCount

        controller.isInteractive = false
        await settle(contentView)

        #expect(
            coordinator.observedTreeRenderCount - rendersBeforeChange == 1,
            "One observed change must re-render the tree once, not once per earlier SwiftUI update"
        )
        #expect(splitView.isHidden, "The observed change must still reach the split view")

        // The re-armed observation keeps working after it fired.
        controller.isInteractive = true
        await settle(contentView)
        #expect(coordinator.observedTreeRenderCount - rendersBeforeChange == 2)
        #expect(!splitView.isHidden)
    }

    /// The root posts each observed re-render with `DispatchQueue.main.async`.
    /// This test runs as a main-queue job, so that block can run only while
    /// the test is suspended; queue behind it before reading the counts.
    private func settle(_ contentView: NSView) async {
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        contentView.layoutSubtreeIfNeeded()
    }

    private static func firstSplitView(in root: NSView) -> NSSplitView? {
        if let split = root as? NSSplitView { return split }
        for subview in root.subviews {
            if let match = firstSplitView(in: subview) { return match }
        }
        return nil
    }
}
