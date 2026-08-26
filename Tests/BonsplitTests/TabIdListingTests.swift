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

        // Warm both paths so neither pays first-call costs in its window.
        _ = controller.tabs(inPane: paneId)
        _ = controller.tabIds(inPane: paneId)

        let tabsStart = ContinuousClock.now
        for _ in 0..<iterations {
            _ = controller.tabs(inPane: paneId).map(\.id)
        }
        let tabsElapsed = ContinuousClock.now - tabsStart

        let idsStart = ContinuousClock.now
        for _ in 0..<iterations {
            _ = controller.tabIds(inPane: paneId)
        }
        let idsElapsed = ContinuousClock.now - idsStart

        print("[tab-ids] \(iterations) listings of 13 tabs: tabs \(tabsElapsed), ids \(idsElapsed)")
        XCTAssertLessThan(idsElapsed, tabsElapsed / 2)
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
