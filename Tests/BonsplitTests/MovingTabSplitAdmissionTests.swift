import XCTest
@testable import Bonsplit

@MainActor
final class MovingTabSplitAdmissionTests: XCTestCase {
    private final class LegacySplitDelegate: BonsplitDelegate {
        var calls: [(PaneID, SplitOrientation)] = []

        func splitTabBar(
            _ controller: BonsplitController,
            shouldSplitPane pane: PaneID,
            orientation: SplitOrientation
        ) -> Bool {
            calls.append((pane, orientation))
            return false
        }
    }

    private final class MovingTabSplitDelegate: BonsplitDelegate {
        let permitsSplit: Bool
        var targetPane: PaneID?
        var movingTab: Tab?
        var sourcePaneDuringCallback: PaneID?
        var sourceTabsDuringCallback: [TabID] = []

        init(permitsSplit: Bool) {
            self.permitsSplit = permitsSplit
        }

        func splitTabBar(
            _ controller: BonsplitController,
            shouldSplitPane pane: PaneID,
            orientation: SplitOrientation,
            movingTab: Tab
        ) -> Bool {
            targetPane = pane
            self.movingTab = movingTab
            sourcePaneDuringCallback = controller.paneId(containing: movingTab.id)
            sourceTabsDuringCallback = sourcePaneDuringCallback.map(controller.tabIds(inPane:)) ?? []
            return permitsSplit
        }
    }

    private final class BothSplitOverloadsDelegate: BonsplitDelegate {
        var legacyCallCount = 0
        var movingTabCallCount = 0

        func splitTabBar(
            _ controller: BonsplitController,
            shouldSplitPane pane: PaneID,
            orientation: SplitOrientation
        ) -> Bool {
            legacyCallCount += 1
            return true
        }

        func splitTabBar(
            _ controller: BonsplitController,
            shouldSplitPane pane: PaneID,
            orientation: SplitOrientation,
            movingTab: Tab
        ) -> Bool {
            movingTabCallCount += 1
            return false
        }
    }

    private func controllerWithSoleTab() throws -> (controller: BonsplitController, pane: PaneID, tab: TabID) {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let pane = try XCTUnwrap(controller.focusedPaneId)
        let initialTabs = controller.tabs(inPane: pane)
        XCTAssertEqual(initialTabs.count, 1)
        let welcomeTab = try XCTUnwrap(initialTabs.first?.id)
        XCTAssertTrue(controller.closeTab(welcomeTab))
        let tab = try XCTUnwrap(controller.createTab(title: "Moved", inPane: pane))
        return (controller, pane, tab)
    }

    func testMovingTabSplitForwardsToExistingDelegateOverload() throws {
        let setup = try controllerWithSoleTab()
        let delegate = LegacySplitDelegate()
        setup.controller.delegate = delegate

        XCTAssertNil(setup.controller.splitPane(
            setup.pane,
            orientation: .horizontal,
            movingTab: setup.tab,
            insertFirst: false
        ))

        XCTAssertEqual(delegate.calls.count, 1)
        XCTAssertEqual(delegate.calls.first?.0, setup.pane)
        XCTAssertEqual(delegate.calls.first?.1, .horizontal)
        XCTAssertEqual(setup.controller.paneId(containing: setup.tab), setup.pane)
    }

    func testMovingTabSplitUsesMovingTabOverloadWhenDelegateImplementsBoth() throws {
        let setup = try controllerWithSoleTab()
        let delegate = BothSplitOverloadsDelegate()
        setup.controller.delegate = delegate

        XCTAssertNil(setup.controller.splitPane(
            setup.pane,
            orientation: .horizontal,
            movingTab: setup.tab,
            insertFirst: false
        ))

        XCTAssertEqual(delegate.movingTabCallCount, 1)
        XCTAssertEqual(delegate.legacyCallCount, 0)
        XCTAssertEqual(setup.controller.paneId(containing: setup.tab), setup.pane)
    }

    func testVetoedMovingTabSplitLeavesSourceAndTreeUnchanged() throws {
        let setup = try controllerWithSoleTab()
        let treeBefore = setup.controller.treeSnapshot()
        let paneIdsBefore = setup.controller.allPaneIds
        let tabIdsBefore = setup.controller.tabIds(inPane: setup.pane)
        let delegate = MovingTabSplitDelegate(permitsSplit: false)
        setup.controller.delegate = delegate

        XCTAssertNil(setup.controller.splitPane(
            setup.pane,
            orientation: .vertical,
            movingTab: setup.tab,
            insertFirst: true
        ))

        XCTAssertEqual(delegate.targetPane, setup.pane)
        XCTAssertEqual(delegate.movingTab?.id, setup.tab)
        XCTAssertEqual(delegate.sourcePaneDuringCallback, setup.pane)
        XCTAssertEqual(delegate.sourceTabsDuringCallback, [setup.tab])
        XCTAssertEqual(setup.controller.treeSnapshot(), treeBefore)
        XCTAssertEqual(setup.controller.allPaneIds, paneIdsBefore)
        XCTAssertEqual(setup.controller.tabIds(inPane: setup.pane), tabIdsBefore)
        XCTAssertFalse(setup.controller.tabs(inPane: setup.pane).contains { $0.title == "Empty" })
    }

    func testPermittedCrossPaneMovingTabSplitReportsTargetAndCompletes() throws {
        let setup = try controllerWithSoleTab()
        let targetPane = try XCTUnwrap(setup.controller.splitPane(
            setup.pane,
            orientation: .vertical,
            withTab: Tab(title: "Target")
        ))
        let delegate = MovingTabSplitDelegate(permitsSplit: true)
        setup.controller.delegate = delegate

        let newPane = try XCTUnwrap(setup.controller.splitPane(
            targetPane,
            orientation: .horizontal,
            movingTab: setup.tab,
            insertFirst: false
        ))

        XCTAssertEqual(delegate.targetPane, targetPane)
        XCTAssertEqual(delegate.movingTab?.id, setup.tab)
        XCTAssertEqual(delegate.sourcePaneDuringCallback, setup.pane)
        XCTAssertEqual(delegate.sourceTabsDuringCallback, [setup.tab])
        XCTAssertEqual(setup.controller.paneId(containing: setup.tab), newPane)
        XCTAssertFalse(setup.controller.allPaneIds.contains(setup.pane))
    }
}
