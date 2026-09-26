import XCTest
@testable import Bonsplit

/// `tabIds(inPane:)` exists so a caller that wants ordering or identity does
/// not have to build a `Tab` per tab to get it. These pin it to the ordering
/// `tabs(inPane:)` already produces, so the cheap call and the expensive one
/// can never disagree.
final class TabIdListingTests: XCTestCase {
    @MainActor
    func testTabIdsMatchTabsInOrderAcrossMovesAndCloses() {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let paneId = try! XCTUnwrap(controller.focusedPaneId)
        let first = try! XCTUnwrap(controller.createTab(title: "First"))
        let second = try! XCTUnwrap(controller.createTab(title: "Second"))

        XCTAssertEqual(
            controller.tabIds(inPane: paneId),
            controller.tabs(inPane: paneId).map(\.id)
        )
        XCTAssertEqual(controller.tabIds(inPane: paneId).suffix(2), [first, second])

        XCTAssertTrue(controller.moveTab(second, toPane: paneId, atIndex: 0))
        XCTAssertEqual(controller.tabIds(inPane: paneId).first, second)
        XCTAssertEqual(
            controller.tabIds(inPane: paneId),
            controller.tabs(inPane: paneId).map(\.id)
        )

        XCTAssertTrue(controller.closeTab(first))
        XCTAssertFalse(controller.tabIds(inPane: paneId).contains(first))
        XCTAssertEqual(
            controller.tabIds(inPane: paneId),
            controller.tabs(inPane: paneId).map(\.id)
        )
    }

    /// A title write must not reorder or drop anything. The ids are the same
    /// list before and after, which is the property callers depend on when
    /// they stop reading titles they never wanted.
    @MainActor
    func testRenamingATabLeavesTheIdListingAlone() {
        let controller = BonsplitController()
        let paneId = try! XCTUnwrap(controller.focusedPaneId)
        let tabId = try! XCTUnwrap(controller.createTab(title: "Before"))

        let before = controller.tabIds(inPane: paneId)
        controller.updateTab(tabId, title: "After")

        XCTAssertEqual(controller.tabIds(inPane: paneId), before)
        XCTAssertEqual(controller.tab(tabId)?.title, "After")
    }

    /// The point of the accessor. Timed rather than counted so the assertion
    /// still means something if the implementation changes later. The bound is
    /// loose on purpose: the measured gap is several times, not a few percent.
    ///
    /// Sampled alternately and compared on medians. One sample each would let a
    /// scheduler hiccup landing in the wrong window fail a correct build, and
    /// alternating keeps a slow stretch of machine from landing entirely on one
    /// of the two paths.
    @MainActor
    func testListingIdsIsSubstantiallyCheaperThanListingTabs() {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let paneId = try! XCTUnwrap(controller.focusedPaneId)
        for index in 0..<12 {
            _ = controller.createTab(title: "Tab \(index)")
        }
        let iterations = 2_000
        let samples = 7

        // Warm both paths so neither pays first-call costs in its window.
        _ = controller.tabs(inPane: paneId)
        _ = controller.tabIds(inPane: paneId)

        func time(_ body: () -> Void) -> Duration {
            let start = ContinuousClock.now
            for _ in 0..<iterations { body() }
            return ContinuousClock.now - start
        }

        var tabsSamples: [Duration] = []
        var idsSamples: [Duration] = []
        for _ in 0..<samples {
            tabsSamples.append(time { _ = controller.tabs(inPane: paneId).map(\.id) })
            idsSamples.append(time { _ = controller.tabIds(inPane: paneId) })
        }

        let tabsMedian = tabsSamples.sorted()[samples / 2]
        let idsMedian = idsSamples.sorted()[samples / 2]

        print("""
        [tab-ids] \(samples) samples of \(iterations) listings of 13 tabs: \
        tabs median \(tabsMedian), ids median \(idsMedian)
        """)
        XCTAssertLessThan(idsMedian, tabsMedian / 2)
    }

    @MainActor
    func testEmptyAndUnknownPanesListNoTabs() {
        let controller = BonsplitController()
        let originalPaneId = try! XCTUnwrap(controller.focusedPaneId)
        let emptyPaneId = try! XCTUnwrap(
            controller.splitPane(originalPaneId, orientation: .vertical)
        )

        XCTAssertEqual(controller.tabIds(inPane: emptyPaneId), [])
        XCTAssertEqual(controller.tabIds(inPane: PaneID()), [])
    }
}
