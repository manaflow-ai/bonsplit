import Observation
import XCTest
@testable import Bonsplit

/// `PaneState.tabs` is an `@Observable` property. `TabBarView.body` reads it to
/// build its `ForEach`, and `TabItemView.body` reads a single tab's `title`.
///
/// When `TabItem` was a struct, `tabs[i].title = x` wrote the whole array, so a
/// title change invalidated everything that had read `tabs`: every tab item, the
/// scroll content, and the split button row. A host whose tab titles animate
/// drove that about 20 times a second.
///
/// These tests pin who gets woken.
final class TabObservationScopeTests: XCTestCase {
    @MainActor
    func testChangingOneTabTitleDoesNotInvalidateTheTabsArray() throws {
        let controller = BonsplitController()
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))
        let tabId = try XCTUnwrap(controller.createTab(title: "First"))

        // Stand in for TabBarView.body, which reads the array to lay out tabs.
        var tabsInvalidated = false
        withObservationTracking {
            _ = pane.tabs
        } onChange: {
            tabsInvalidated = true
        }

        controller.updateTab(tabId, title: "First (running)")

        XCTAssertFalse(
            tabsInvalidated,
            "A title change must not invalidate readers of the tabs array"
        )
    }

    @MainActor
    func testChangingOneTabTitleInvalidatesThatTab() throws {
        let controller = BonsplitController()
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))
        let tabId = try XCTUnwrap(controller.createTab(title: "First"))
        let tab = try XCTUnwrap(pane.tabs.first { $0.id == tabId.id })

        // Stand in for TabItemView.body, which renders the title.
        var titleInvalidated = false
        withObservationTracking {
            _ = tab.title
        } onChange: {
            titleInvalidated = true
        }

        controller.updateTab(tabId, title: "First (running)")

        XCTAssertTrue(titleInvalidated, "The tab whose title changed must still redraw")
        XCTAssertEqual(tab.title, "First (running)")
    }

    @MainActor
    func testChangingOneTabTitleDoesNotInvalidateItsSiblings() throws {
        let controller = BonsplitController()
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))
        let firstId = try XCTUnwrap(controller.createTab(title: "First"))
        let secondId = try XCTUnwrap(controller.createTab(title: "Second"))
        let second = try XCTUnwrap(pane.tabs.first { $0.id == secondId.id })

        var siblingInvalidated = false
        withObservationTracking {
            _ = second.title
        } onChange: {
            siblingInvalidated = true
        }

        controller.updateTab(firstId, title: "First (running)")

        XCTAssertFalse(siblingInvalidated, "A sibling tab must not redraw for another tab's title")
    }

    /// The array must still publish the changes it is the right home for.
    @MainActor
    func testAddingATabStillInvalidatesTheTabsArray() throws {
        let controller = BonsplitController()
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))

        var tabsInvalidated = false
        withObservationTracking {
            _ = pane.tabs
        } onChange: {
            tabsInvalidated = true
        }

        _ = controller.createTab(title: "Second")

        XCTAssertTrue(tabsInvalidated, "Adding a tab changes the layout and must invalidate the array")
    }

    @MainActor
    func testRemovingATabStillInvalidatesTheTabsArray() throws {
        let controller = BonsplitController()
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))
        let tabId = try XCTUnwrap(controller.createTab(title: "Second"))

        var tabsInvalidated = false
        withObservationTracking {
            _ = pane.tabs
        } onChange: {
            tabsInvalidated = true
        }

        _ = controller.closeTab(tabId)

        XCTAssertTrue(tabsInvalidated, "Removing a tab changes the layout and must invalidate the array")
    }

    /// A no-op write stays a no-op. `updateTab` guards on `didChange`, and that
    /// guard is what keeps a terminal re-emitting an unchanged title free.
    @MainActor
    func testWritingTheSameTitleWakesNobody() throws {
        let controller = BonsplitController()
        let paneId = try XCTUnwrap(controller.focusedPaneId)
        let pane = try XCTUnwrap(controller.internalController.paneState(for: paneId))
        let tabId = try XCTUnwrap(controller.createTab(title: "First"))
        let tab = try XCTUnwrap(pane.tabs.first { $0.id == tabId.id })

        var titleInvalidated = false
        withObservationTracking {
            _ = tab.title
        } onChange: {
            titleInvalidated = true
        }

        controller.updateTab(tabId, title: "First")

        XCTAssertFalse(titleInvalidated)
    }
}
