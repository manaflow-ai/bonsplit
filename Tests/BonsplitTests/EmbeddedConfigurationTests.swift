import XCTest
@testable import Bonsplit

@MainActor
private final class ReentrantIdentityDelegate: BonsplitDelegate {
    var createAction: ((BonsplitController, PaneID) -> Void)?
    var splitAction: ((BonsplitController, PaneID, SplitOrientation) -> Void)?
    private var didReenterCreate = false
    private var didReenterSplit = false
    private(set) var completedSplitCount = 0

    func splitTabBar(
        _ controller: BonsplitController,
        shouldCreateTab tab: Tab,
        inPane pane: PaneID
    ) -> Bool {
        if !didReenterCreate {
            didReenterCreate = true
            createAction?(controller, pane)
        }
        return true
    }

    func splitTabBar(
        _ controller: BonsplitController,
        shouldSplitPane pane: PaneID,
        orientation: SplitOrientation
    ) -> Bool {
        if !didReenterSplit {
            didReenterSplit = true
            splitAction?(controller, pane, orientation)
        }
        return true
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didSplitPane originalPane: PaneID,
        newPane: PaneID,
        orientation: SplitOrientation
    ) {
        completedSplitCount += 1
    }
}

@MainActor
final class EmbeddedConfigurationTests: XCTestCase {
    func testEmbeddedBehaviorControlsAreOptIn() {
        let configuration = BonsplitConfiguration()

        XCTAssertTrue(configuration.allowsTabContextMenu)
        XCTAssertEqual(configuration.dividerPositionRange, 0.1...0.9)
        XCTAssertTrue(configuration.allowDividerResizing)
        XCTAssertFalse(BonsplitConfiguration.readOnly.allowDividerResizing)
    }

    func testConfiguredDividerRangeAllowsNarrowProgrammaticLayouts() throws {
        let configuration = BonsplitConfiguration(
            allowsTabContextMenu: false,
            dividerPositionRange: 0...1
        )
        let controller = BonsplitController(configuration: configuration)
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        XCTAssertNotNil(controller.splitPane(
            rootPane,
            orientation: .horizontal,
            initialDividerPosition: 0.02
        ))
        guard case .split(let split) = controller.treeSnapshot() else {
            XCTFail("Expected split root")
            return
        }
        XCTAssertEqual(split.dividerPosition, 0.02, accuracy: 0.0001)
        let splitID = try XCTUnwrap(UUID(uuidString: split.id))

        XCTAssertTrue(controller.setDividerPosition(0.98, forSplit: splitID))
        guard case .split(let updated) = controller.treeSnapshot() else {
            XCTFail("Expected split root")
            return
        }
        XCTAssertEqual(updated.dividerPosition, 0.98, accuracy: 0.0001)
    }

    func testDefaultSplitPositionRespectsConfiguredDividerRange() throws {
        let controller = BonsplitController(configuration: BonsplitConfiguration(
            dividerPositionRange: 0.6...0.9
        ))
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        XCTAssertNotNil(controller.splitPane(rootPane, orientation: .horizontal))
        guard case .split(let split) = controller.treeSnapshot() else {
            XCTFail("Expected split root")
            return
        }
        // The implicit 0.5 default must be clamped into the configured range,
        // exactly like an explicit initialDividerPosition.
        XCTAssertEqual(split.dividerPosition, 0.6, accuracy: 0.0001)
    }

    func testMovingTabSplitRespectsConfiguredDividerRange() throws {
        let controller = BonsplitController(configuration: BonsplitConfiguration(
            dividerPositionRange: 0.6...0.9
        ))
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        let firstTab = try XCTUnwrap(controller.createTab(title: "first", inPane: rootPane))
        _ = try XCTUnwrap(controller.createTab(title: "second", inPane: rootPane))
        XCTAssertNotNil(controller.splitPane(
            rootPane,
            orientation: .horizontal,
            movingTab: firstTab,
            insertFirst: false
        ))
        guard case .split(let split) = controller.treeSnapshot() else {
            XCTFail("Expected split root")
            return
        }
        // The moved-tab split path must clamp its implicit default like the
        // tab-creating overloads.
        XCTAssertEqual(split.dividerPosition, 0.6, accuracy: 0.0001)
    }

    func testDisabledTabMovesRejectBothReorderAndCrossPaneMutation() throws {
        let controller = BonsplitController(configuration: BonsplitConfiguration(
            allowTabReordering: false,
            allowCrossPaneTabMove: false
        ))
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        let firstTab = try XCTUnwrap(controller.createTab(title: "first", inPane: rootPane))
        _ = try XCTUnwrap(controller.createTab(title: "second", inPane: rootPane))
        let secondPane = try XCTUnwrap(controller.splitPane(rootPane, orientation: .horizontal))
        let orderBefore = controller.tabs(inPane: rootPane).map(\.id)

        XCTAssertFalse(controller.reorderTab(firstTab, toIndex: 1))
        XCTAssertEqual(controller.tabs(inPane: rootPane).map(\.id), orderBefore)
        XCTAssertFalse(controller.moveTab(firstTab, toPane: secondPane))
        XCTAssertEqual(controller.tabs(inPane: rootPane).map(\.id), orderBefore)
        let paneCountBefore = controller.allPaneIds.count
        XCTAssertNil(controller.splitPane(
            rootPane,
            orientation: .vertical,
            movingTab: firstTab,
            insertFirst: false
        ))
        XCTAssertEqual(controller.allPaneIds.count, paneCountBefore)
        XCTAssertEqual(controller.tabs(inPane: rootPane).map(\.id), orderBefore)
    }

    func testCallerCanInstallStablePaneIdentities() throws {
        let rootPane = PaneID(id: UUID())
        let secondPane = PaneID(id: UUID())
        let controller = BonsplitController(initialPaneID: rootPane)

        XCTAssertEqual(controller.allPaneIds, [rootPane])
        XCTAssertEqual(
            controller.splitPane(
                rootPane,
                orientation: .horizontal,
                newPaneID: secondPane
            ),
            secondPane
        )
        XCTAssertEqual(Set(controller.allPaneIds), [rootPane, secondPane])
    }

    func testCallerCannotInstallDuplicateOrEmptyPaneIdentities() throws {
        let rootPane = PaneID(id: UUID())
        let secondPane = PaneID(id: UUID())
        let emptyPane = PaneID(id: BonsplitController.emptyIdentityUUID)
        let controller = BonsplitController(initialPaneID: rootPane)

        XCTAssertEqual(
            controller.splitPane(rootPane, orientation: .horizontal, newPaneID: secondPane),
            secondPane
        )
        let paneIDsBefore = controller.allPaneIds
        let focusedPaneBefore = controller.focusedPaneId
        guard case .split(let split) = controller.treeSnapshot(),
              let splitID = UUID(uuidString: split.id) else {
            XCTFail("Expected split root with a stable identity")
            return
        }
        let splitIdentityAsPane = PaneID(id: splitID)

        XCTAssertNil(controller.splitPane(rootPane, orientation: .vertical, newPaneID: rootPane))
        XCTAssertNil(controller.splitPane(rootPane, orientation: .vertical, newPaneID: secondPane))
        XCTAssertNil(controller.splitPane(rootPane, orientation: .vertical, newPaneID: emptyPane))
        XCTAssertNil(controller.splitPane(rootPane, orientation: .vertical, newPaneID: splitIdentityAsPane))
        XCTAssertEqual(controller.allPaneIds, paneIDsBefore)
        XCTAssertEqual(controller.focusedPaneId, focusedPaneBefore)
    }

    func testEmptyInitialPaneIdentityIsReplaced() throws {
        let emptyPane = PaneID(id: BonsplitController.emptyIdentityUUID)
        let controller = BonsplitController(initialPaneID: emptyPane)

        let resolvedPane = try XCTUnwrap(controller.allPaneIds.first)
        XCTAssertNotEqual(resolvedPane, emptyPane)
        XCTAssertEqual(controller.focusedPaneId, resolvedPane)
    }

    func testCallerCannotCreateTabWithEmptyIdentity() throws {
        let controller = BonsplitController()
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        let tabIDsBefore = controller.tabs(inPane: rootPane).map(\.id)
        let emptyTab = TabID(uuid: BonsplitController.emptyIdentityUUID)

        XCTAssertNil(controller.createTab(title: "invalid", tabID: emptyTab, inPane: rootPane))
        XCTAssertEqual(controller.tabs(inPane: rootPane).map(\.id), tabIDsBefore)
    }

    func testReentrantDelegateCannotCreateDuplicateStableTabIdentity() throws {
        let controller = BonsplitController()
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        let stableTab = TabID()
        let delegate = ReentrantIdentityDelegate()
        var reentrantResult: TabID?
        delegate.createAction = { controller, pane in
            reentrantResult = controller.createTab(
                title: "reentrant",
                tabID: stableTab,
                inPane: pane
            )
        }
        controller.delegate = delegate

        let outerResult = controller.createTab(
            title: "outer",
            tabID: stableTab,
            inPane: rootPane
        )

        XCTAssertEqual(reentrantResult, stableTab)
        XCTAssertNil(outerResult)
        XCTAssertEqual(controller.allTabIds.filter { $0 == stableTab }.count, 1)
    }

    func testReentrantDelegateCannotConsumeMovingTabBeforeDuplicatePaneRejection() throws {
        let controller = BonsplitController()
        let rootPane = try XCTUnwrap(controller.allPaneIds.first)
        let movingTab = try XCTUnwrap(controller.createTab(title: "moving", inPane: rootPane))
        let stablePane = PaneID()
        let delegate = ReentrantIdentityDelegate()
        var reentrantResult: PaneID?
        delegate.splitAction = { controller, pane, orientation in
            reentrantResult = controller.splitPane(
                pane,
                orientation: orientation,
                newPaneID: stablePane
            )
        }
        controller.delegate = delegate

        let outerResult = controller.splitPane(
            rootPane,
            orientation: .horizontal,
            movingTab: movingTab,
            insertFirst: false,
            newPaneID: stablePane
        )

        XCTAssertEqual(reentrantResult, stablePane)
        XCTAssertNil(outerResult)
        XCTAssertEqual(controller.allPaneIds.filter { $0 == stablePane }.count, 1)
        XCTAssertTrue(controller.tabs(inPane: rootPane).contains { $0.id == movingTab })
        XCTAssertEqual(delegate.completedSplitCount, 1)
    }
}
