import AppKit
@testable import Bonsplit
import XCTest

/// The initial divider position needs a real `bounds`, and only an AppKit layout
/// pass supplies one. These tests pin the edge it waits on.
///
/// The retry used to hop `DispatchQueue.main.async` — the next runloop turn, which
/// is not a layout pass. Every attempt read the same empty bounds, the budget was
/// spent without one real chance, and the fallback then recorded the position as
/// applied when it never was. Nothing re-derives a position the coordinator
/// believes it already set, so the pane kept its entry default for good.
@MainActor
final class SplitEntryLayoutEdgeTests: XCTestCase {
    /// A runloop turn is not a layout pass.
    ///
    /// This is the property the old code violated: it retried on a clock that ticks
    /// whether or not AppKit has laid anything out, so a chain of retries could run
    /// to exhaustion inside a single layout. Draining the main queue must NOT run
    /// work parked for the layout edge.
    func testWorkParkedForLayoutDoesNotRunOnAMereRunloopTurn() throws {
        let splitView = ThemedSplitView(frame: .zero)
        var ran = 0
        splitView.afterNextLayout = { ran += 1 }

        // Spin the runloop hard — the old retry's entire budget was twelve of these
        // inside 13ms. None of them is a layout.
        for _ in 0..<12 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }

        XCTAssertEqual(
            ran, 0,
            "Work parked for the layout edge must not fire on a runloop turn: that is "
                + "exactly how twelve retries burned in 13ms without one real attempt."
        )
    }

    /// The layout pass is the edge that changes the answer.
    func testWorkParkedForLayoutRunsOnTheNextLayoutPass() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        defer { window.orderOut(nil) }
        let content = try XCTUnwrap(window.contentView)
        let splitView = ThemedSplitView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        content.addSubview(splitView)

        var ran = 0
        var availableAtRun: CGFloat = -1
        splitView.afterNextLayout = {
            ran += 1
            availableAtRun = splitView.bounds.width
        }

        splitView.needsLayout = true
        splitView.layoutSubtreeIfNeeded()

        XCTAssertEqual(ran, 1, "The layout pass must run work parked for it.")
        XCTAssertGreaterThan(
            availableAtRun, 0,
            "The hook must observe a real bounds — that is the whole reason it waits "
                + "for layout rather than a runloop turn."
        )
    }

    /// Cleared before it runs, so the hook can re-arm itself for the following pass.
    ///
    /// The retry re-arms when the view still has no width. If `layout()` cleared the
    /// hook after invoking it, that re-arm would be wiped out and the position would
    /// never be applied.
    func testHookIsClearedBeforeItRunsSoItCanRearmForTheFollowingPass() throws {
        let splitView = ThemedSplitView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var runs = 0
        func arm() {
            splitView.afterNextLayout = {
                runs += 1
                if runs < 3 { arm() }   // re-arm from inside the hook, as the retry does
            }
        }
        arm()

        for _ in 0..<3 {
            splitView.needsLayout = true
            splitView.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(
            runs, 3,
            "A hook that re-arms itself must survive: clearing after the call would "
                + "discard the re-arm and strand the divider unapplied."
        )
    }

    /// One layout, one attempt — the budget must measure layouts, not turns.
    func testOneLayoutPassRunsTheHookExactlyOnce() throws {
        let splitView = ThemedSplitView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var ran = 0
        splitView.afterNextLayout = { ran += 1 }

        splitView.needsLayout = true
        splitView.layoutSubtreeIfNeeded()
        splitView.needsLayout = true
        splitView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            ran, 1,
            "A one-shot hook must not re-fire on later layouts it did not arm for."
        )
    }
}
