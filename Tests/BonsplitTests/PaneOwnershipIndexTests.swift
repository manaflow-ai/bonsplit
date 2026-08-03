import XCTest
@testable import Bonsplit

final class PaneOwnershipIndexTests: XCTestCase {
    @MainActor
    func testOwnershipIndexBootstrapsAndTracksDirectPaneSelection() {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let paneId = try! XCTUnwrap(controller.focusedPaneId)
        let welcomeTabId = try! XCTUnwrap(controller.tabs(inPane: paneId).only?.id)
        let firstTabId = try! XCTUnwrap(controller.createTab(title: "First"))
        let secondTabId = try! XCTUnwrap(controller.createTab(title: "Second"))

        XCTAssertEqual(controller.paneId(containing: firstTabId), paneId)
        XCTAssertEqual(controller.paneId(containing: secondTabId), paneId)

        // The native tab bar selects through PaneState directly. The indexed query must
        // reflect that UI path without requiring a controller rescan or callback.
        let paneState = try! XCTUnwrap(controller.internalController.paneState(for: paneId))
        paneState.selectTab(firstTabId.uuid)

        XCTAssertEqual(controller.selectedTabId(inPane: paneId), firstTabId)
        XCTAssertEqual(controller.selectedTab(inPane: paneId)?.id, firstTabId)

        XCTAssertTrue(controller.moveTab(firstTabId, toPane: paneId, atIndex: 3))
        XCTAssertEqual(
            paneState.tabs.map(\.id),
            [welcomeTabId.uuid, secondTabId.uuid, firstTabId.uuid]
        )
        XCTAssertEqual(controller.paneId(containing: firstTabId), paneId)
        XCTAssertEqual(controller.selectedTabId(inPane: paneId), firstTabId)

        let firstTabItem = try! XCTUnwrap(paneState.tabs.first { $0.id == firstTabId.uuid })
        controller.internalController.moveTab(
            firstTabItem,
            from: paneId,
            to: paneId,
            atIndex: 0
        )
        XCTAssertEqual(
            paneState.tabs.map(\.id),
            [firstTabId.uuid, welcomeTabId.uuid, secondTabId.uuid]
        )
        XCTAssertEqual(controller.paneId(containing: firstTabId), paneId)
        XCTAssertEqual(controller.selectedTabId(inPane: paneId), firstTabId)

        XCTAssertTrue(controller.closeTab(firstTabId))
        XCTAssertNil(controller.paneId(containing: firstTabId))
        XCTAssertEqual(controller.selectedTabId(inPane: paneId), welcomeTabId)
    }

    @MainActor
    func testSplitVariantsIndexEmptyAndInsertedPanes() {
        let controller = BonsplitController()
        let originalPaneId = try! XCTUnwrap(controller.focusedPaneId)

        let emptyPaneId = try! XCTUnwrap(
            controller.splitPane(originalPaneId, orientation: .vertical)
        )
        XCTAssertNil(controller.selectedTabId(inPane: emptyPaneId))

        let emptyPaneTabId = try! XCTUnwrap(
            controller.createTab(title: "Empty pane tab", inPane: emptyPaneId)
        )
        XCTAssertEqual(controller.paneId(containing: emptyPaneTabId), emptyPaneId)

        let insertedTab = Tab(title: "Inserted first")
        let insertedPaneId = try! XCTUnwrap(
            controller.splitPane(
                originalPaneId,
                orientation: .horizontal,
                withTab: insertedTab,
                insertFirst: true
            )
        )
        XCTAssertEqual(controller.paneId(containing: insertedTab.id), insertedPaneId)
        XCTAssertEqual(controller.selectedTabId(inPane: insertedPaneId), insertedTab.id)
    }

    @MainActor
    func testCrossPaneMovesTrackOwnerSourceSuccessorAndAutomaticPaneClose() {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let sourcePaneId = try! XCTUnwrap(controller.focusedPaneId)
        let movedTabId = try! XCTUnwrap(controller.createTab(title: "Moved"))
        let successorTabId = try! XCTUnwrap(controller.createTab(title: "Successor"))
        let targetTab = Tab(title: "Target")
        let targetPaneId = try! XCTUnwrap(
            controller.splitPane(sourcePaneId, orientation: .horizontal, withTab: targetTab)
        )

        controller.selectTab(movedTabId)
        XCTAssertTrue(controller.moveTab(movedTabId, toPane: targetPaneId))

        XCTAssertEqual(controller.paneId(containing: movedTabId), targetPaneId)
        XCTAssertEqual(controller.selectedTabId(inPane: sourcePaneId), successorTabId)

        let soleTab = Tab(title: "Sole")
        let soleTabPaneId = try! XCTUnwrap(
            controller.splitPane(targetPaneId, orientation: .vertical, withTab: soleTab)
        )
        XCTAssertTrue(controller.moveTab(soleTab.id, toPane: targetPaneId))

        XCTAssertEqual(controller.paneId(containing: soleTab.id), targetPaneId)
        XCTAssertFalse(controller.allPaneIds.contains(soleTabPaneId))
        XCTAssertNil(controller.selectedTabId(inPane: soleTabPaneId))
    }

    @MainActor
    func testMovingSoleTabIntoSplitIndexesPlaceholderAndDestination() {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let sourcePaneId = try! XCTUnwrap(controller.focusedPaneId)
        let welcomeTabId = try! XCTUnwrap(controller.tabs(inPane: sourcePaneId).first?.id)
        XCTAssertTrue(controller.closeTab(welcomeTabId))
        let movedTabId = try! XCTUnwrap(controller.createTab(title: "Moved"))

        let newPaneId = try! XCTUnwrap(
            controller.splitPane(
                sourcePaneId,
                orientation: .horizontal,
                movingTab: movedTabId,
                insertFirst: true
            )
        )

        let placeholder = try! XCTUnwrap(controller.tabs(inPane: sourcePaneId).only)
        XCTAssertEqual(placeholder.title, "Empty")
        XCTAssertEqual(controller.paneId(containing: placeholder.id), sourcePaneId)
        XCTAssertEqual(controller.selectedTabId(inPane: sourcePaneId), placeholder.id)
        XCTAssertEqual(controller.paneId(containing: movedTabId), newPaneId)
        XCTAssertEqual(controller.selectedTabId(inPane: newPaneId), movedTabId)
    }

    @MainActor
    func testClosingZoomedPaneRemovesOwnershipAndFocusesSibling() {
        let controller = BonsplitController()
        let originalPaneId = try! XCTUnwrap(controller.focusedPaneId)
        let closingTab = Tab(title: "Closing")
        let closingPaneId = try! XCTUnwrap(
            controller.splitPane(originalPaneId, orientation: .horizontal, withTab: closingTab)
        )

        XCTAssertTrue(controller.togglePaneZoom(inPane: closingPaneId))
        XCTAssertTrue(controller.closePane(closingPaneId))

        XCTAssertNil(controller.paneId(containing: closingTab.id))
        XCTAssertNil(controller.selectedTabId(inPane: closingPaneId))
        XCTAssertEqual(controller.focusedPaneId, originalPaneId)
        XCTAssertNil(controller.zoomedPaneId)

        controller.focusPane(PaneID())
        XCTAssertEqual(controller.focusedPaneId, originalPaneId)
    }

    @MainActor
    func testRestoredTreeBootstrapsIndexesAndRejectsInvalidFocus() {
        let leftTab = TabItem(title: "Left")
        let rightTab = TabItem(title: "Right")
        let leftPane = PaneState(tabs: [leftTab])
        let rightPane = PaneState(tabs: [rightTab])
        let restoredRoot = SplitNode.split(
            SplitState(
                orientation: .horizontal,
                first: .pane(leftPane),
                second: .pane(rightPane)
            )
        )
        let controller = SplitViewController(rootNode: restoredRoot)

        XCTAssertEqual(controller.paneId(containing: leftTab.id), leftPane.id)
        XCTAssertEqual(controller.paneId(containing: rightTab.id), rightPane.id)
        controller.focusPane(rightPane.id)
        XCTAssertTrue(controller.togglePaneZoom(rightPane.id))
        controller.focusPane(PaneID())

        XCTAssertEqual(controller.focusedPaneId, rightPane.id)
        XCTAssertEqual(controller.zoomedPaneId, rightPane.id)

        controller.closePane(rightPane.id)
        XCTAssertNil(controller.paneId(containing: rightTab.id))
        XCTAssertEqual(controller.paneId(containing: leftTab.id), leftPane.id)
        XCTAssertEqual(controller.focusedPaneId, leftPane.id)
        XCTAssertNil(controller.zoomedPaneId)
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
