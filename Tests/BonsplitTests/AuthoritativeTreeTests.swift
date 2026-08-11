import XCTest
@testable import Bonsplit

final class AuthoritativeTreeTests: XCTestCase {
    @MainActor
    private final class DelegateSpy: BonsplitDelegate {
        private(set) var geometryNotifications = 0
        private(set) var mutationCallbacks: [String] = []

        func splitTabBar(
            _ controller: BonsplitController,
            shouldCreateTab tab: Tab,
            inPane pane: PaneID
        ) -> Bool {
            mutationCallbacks.append("should-create-tab")
            return true
        }

        func splitTabBar(
            _ controller: BonsplitController,
            shouldCloseTab tab: Tab,
            inPane pane: PaneID
        ) -> Bool {
            mutationCallbacks.append("should-close-tab")
            return true
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didCreateTab tab: Tab,
            inPane pane: PaneID
        ) {
            mutationCallbacks.append("did-create-tab")
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didCloseTab tabId: TabID,
            fromPane pane: PaneID
        ) {
            mutationCallbacks.append("did-close-tab")
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didSelectTab tab: Tab,
            inPane pane: PaneID
        ) {
            mutationCallbacks.append("did-select-tab")
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didMoveTab tab: Tab,
            fromPane source: PaneID,
            toPane destination: PaneID
        ) {
            mutationCallbacks.append("did-move-tab")
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didReorderTabsInPane pane: PaneID,
            orderedTabIds: [TabID]
        ) {
            mutationCallbacks.append("did-reorder-tabs")
        }

        func splitTabBar(
            _ controller: BonsplitController,
            shouldSplitPane pane: PaneID,
            orientation: SplitOrientation
        ) -> Bool {
            mutationCallbacks.append("should-split-pane")
            return true
        }

        func splitTabBar(_ controller: BonsplitController, shouldClosePane pane: PaneID) -> Bool {
            mutationCallbacks.append("should-close-pane")
            return true
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didSplitPane originalPane: PaneID,
            newPane: PaneID,
            orientation: SplitOrientation
        ) {
            mutationCallbacks.append("did-split-pane")
        }

        func splitTabBar(_ controller: BonsplitController, didClosePane paneId: PaneID) {
            mutationCallbacks.append("did-close-pane")
        }

        func splitTabBar(_ controller: BonsplitController, didFocusPane pane: PaneID) {
            mutationCallbacks.append("did-focus-pane")
        }

        func splitTabBar(
            _ controller: BonsplitController,
            didChangeGeometry snapshot: LayoutSnapshot
        ) {
            geometryNotifications += 1
        }
    }

    @MainActor
    func testApplyBuildsArbitraryTreePreservesMetadataAndSkipsMutationDelegates() throws {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let originalPane = try XCTUnwrap(controller.focusedPaneId)
        let welcome = try XCTUnwrap(controller.tabs(inPane: originalPane).first?.id)
        let alpha = try XCTUnwrap(controller.createTab(title: "Alpha"))
        let beta = try XCTUnwrap(controller.createTab(title: "Beta"))
        let gamma = try XCTUnwrap(controller.createTab(title: "Gamma"))
        controller.updateTab(alpha, title: "Alpha metadata", isDirty: true, isPinned: true)
        XCTAssertTrue(controller.setFullWidthTabMode(true, inPane: originalPane))

        let secondPane = PaneID()
        let thirdPane = PaneID()
        let rootSplit = UUID()
        let nestedSplit = UUID()
        let tree = BonsplitAuthoritativeTree(
            root: .split(.init(
                id: rootSplit,
                orientation: .vertical,
                ratio: 0.6,
                first: .pane(.init(id: thirdPane, tabs: [gamma])),
                second: .split(.init(
                    id: nestedSplit,
                    orientation: .horizontal,
                    ratio: 0.3,
                    first: .pane(.init(id: originalPane, tabs: [beta, welcome])),
                    second: .pane(.init(
                        id: secondPane,
                        tabs: [alpha],
                        selection: .tab(alpha),
                        fullWidthTabMode: .value(true)
                    ))
                ))
            )),
            focusedPane: .pane(thirdPane),
            zoomedPane: .pane(secondPane)
        )
        requiresSendable(tree)

        let delegate = DelegateSpy()
        controller.delegate = delegate
        try controller.validateAuthoritativeTree(tree)
        XCTAssertTrue(try controller.applyAuthoritativeTree(tree))

        XCTAssertEqual(controller.allPaneIds, [thirdPane, originalPane, secondPane])
        XCTAssertEqual(controller.tabs(inPane: thirdPane).map(\.id), [gamma])
        XCTAssertEqual(controller.tabs(inPane: originalPane).map(\.id), [beta, welcome])
        XCTAssertEqual(controller.tabs(inPane: secondPane).map(\.id), [alpha])
        XCTAssertEqual(controller.paneId(containing: alpha), secondPane)
        XCTAssertEqual(controller.selectedTabId(inPane: originalPane), beta)
        XCTAssertEqual(controller.selectedTabId(inPane: secondPane), alpha)
        XCTAssertEqual(controller.focusedPaneId, thirdPane)
        XCTAssertEqual(controller.zoomedPaneId, secondPane)
        XCTAssertTrue(controller.isFullWidthTabMode(inPane: originalPane))
        XCTAssertTrue(controller.isFullWidthTabMode(inPane: secondPane))
        XCTAssertEqual(controller.tab(alpha)?.title, "Alpha metadata")
        XCTAssertEqual(controller.tab(alpha)?.isDirty, true)
        XCTAssertEqual(controller.tab(alpha)?.isPinned, true)
        XCTAssertEqual(delegate.geometryNotifications, 1)
        XCTAssertEqual(delegate.mutationCallbacks, [])

        guard case .split(let root) = controller.internalController.rootNode,
              case .split(let nested) = root.second else {
            return XCTFail("expected nested authoritative split tree")
        }
        XCTAssertEqual(root.id, rootSplit)
        XCTAssertEqual(root.orientation, .vertical)
        XCTAssertEqual(root.dividerPosition, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(nested.id, nestedSplit)
        XCTAssertEqual(nested.orientation, .horizontal)
        XCTAssertEqual(nested.dividerPosition, 0.3, accuracy: 0.000_001)

        let rootIdentity = root
        let nestedIdentity = nested
        let originalPaneIdentity = try XCTUnwrap(
            controller.internalController.paneState(for: originalPane)
        )
        XCTAssertFalse(try controller.applyAuthoritativeTree(tree))
        guard case .split(let unchangedRoot) = controller.internalController.rootNode,
              case .split(let unchangedNested) = unchangedRoot.second else {
            return XCTFail("expected unchanged nested split tree")
        }
        XCTAssertTrue(rootIdentity === unchangedRoot)
        XCTAssertTrue(nestedIdentity === unchangedNested)
        XCTAssertTrue(
            originalPaneIdentity === controller.internalController.paneState(for: originalPane)
        )
        XCTAssertEqual(delegate.geometryNotifications, 1)
        XCTAssertEqual(delegate.mutationCallbacks, [])
    }

    @MainActor
    func testValidationFailureIsAtomic() throws {
        let controller = BonsplitController()
        let pane = try XCTUnwrap(controller.focusedPaneId)
        let tab = try XCTUnwrap(controller.tabs(inPane: pane).first?.id)
        let rootBefore = controller.internalController.rootNode
        let paneBefore = try XCTUnwrap(controller.internalController.paneState(for: pane))
        let focusBefore = controller.focusedPaneId
        let selectionBefore = controller.selectedTabId(inPane: pane)
        let delegate = DelegateSpy()
        controller.delegate = delegate

        let invalid = BonsplitAuthoritativeTree(
            root: .split(.init(
                id: UUID(),
                orientation: .horizontal,
                ratio: .nan,
                first: .pane(.init(id: pane, tabs: [tab])),
                second: .pane(.init(id: PaneID(), tabs: [tab]))
            ))
        )

        XCTAssertThrowsError(try controller.validateAuthoritativeTree(invalid))
        XCTAssertThrowsError(try controller.applyAuthoritativeTree(invalid))
        XCTAssertTrue(sameRootIdentity(rootBefore, controller.internalController.rootNode))
        XCTAssertTrue(paneBefore === controller.internalController.paneState(for: pane))
        XCTAssertEqual(controller.allPaneIds, [pane])
        XCTAssertEqual(controller.allTabIds, [tab])
        XCTAssertEqual(controller.focusedPaneId, focusBefore)
        XCTAssertEqual(controller.selectedTabId(inPane: pane), selectionBefore)
        XCTAssertEqual(delegate.geometryNotifications, 0)
        XCTAssertEqual(delegate.mutationCallbacks, [])
    }

    @MainActor
    func testValidatorRejectsEveryReferenceAndIdentityInvariant() throws {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let pane = try XCTUnwrap(controller.focusedPaneId)
        let first = try XCTUnwrap(controller.tabs(inPane: pane).first?.id)
        let second = try XCTUnwrap(controller.createTab(title: "Second"))
        let third = try XCTUnwrap(controller.createTab(title: "Third"))
        let currentTabs: Set<TabID> = [first, second, third]
        let otherPane = PaneID()

        assertValidationError(
            .paneHasNoTabs(pane),
            controller: controller,
            tree: .init(root: .pane(.init(id: pane, tabs: []))),
            exactTabIDs: []
        )
        assertValidationError(
            .duplicatePane(pane),
            controller: controller,
            tree: .init(root: .split(.init(
                id: UUID(),
                orientation: .horizontal,
                ratio: 0.5,
                first: .pane(.init(id: pane, tabs: [first])),
                second: .pane(.init(id: pane, tabs: [second, third]))
            ))),
            exactTabIDs: currentTabs
        )
        assertValidationError(
            .duplicateTab(first),
            controller: controller,
            tree: .init(root: .split(.init(
                id: UUID(),
                orientation: .horizontal,
                ratio: 0.5,
                first: .pane(.init(id: pane, tabs: [first, second])),
                second: .pane(.init(id: otherPane, tabs: [first, third]))
            ))),
            exactTabIDs: currentTabs
        )

        let duplicateSplit = UUID()
        assertValidationError(
            .duplicateSplit(duplicateSplit),
            controller: controller,
            tree: .init(root: .split(.init(
                id: duplicateSplit,
                orientation: .horizontal,
                ratio: 0.5,
                first: .pane(.init(id: pane, tabs: [first])),
                second: .split(.init(
                    id: duplicateSplit,
                    orientation: .vertical,
                    ratio: 0.5,
                    first: .pane(.init(id: otherPane, tabs: [second])),
                    second: .pane(.init(id: PaneID(), tabs: [third]))
                ))
            ))),
            exactTabIDs: currentTabs
        )

        let invalidRatioSplit = UUID()
        assertValidationError(
            .invalidSplitRatio(split: invalidRatioSplit, ratio: 1),
            controller: controller,
            tree: .init(root: .split(.init(
                id: invalidRatioSplit,
                orientation: .horizontal,
                ratio: 1,
                first: .pane(.init(id: pane, tabs: [first])),
                second: .pane(.init(id: otherPane, tabs: [second, third]))
            ))),
            exactTabIDs: currentTabs
        )
        let outOfConfigurationRangeSplit = UUID()
        assertValidationError(
            .invalidSplitRatio(split: outOfConfigurationRangeSplit, ratio: 0.05),
            controller: controller,
            tree: .init(root: .split(.init(
                id: outOfConfigurationRangeSplit,
                orientation: .horizontal,
                ratio: 0.05,
                first: .pane(.init(id: pane, tabs: [first])),
                second: .pane(.init(id: otherPane, tabs: [second, third]))
            ))),
            exactTabIDs: currentTabs
        )

        let absentTab = TabID()
        assertValidationError(
            .invalidSelectedTab(pane: pane, tab: absentTab),
            controller: controller,
            tree: .init(root: .pane(.init(
                id: pane,
                tabs: [first, second, third],
                selection: .tab(absentTab)
            ))),
            exactTabIDs: currentTabs
        )

        let absentPane = PaneID()
        assertValidationError(
            .invalidFocusedPane(absentPane),
            controller: controller,
            tree: .init(
                root: .pane(.init(id: pane, tabs: [first, second, third])),
                focusedPane: .pane(absentPane)
            ),
            exactTabIDs: currentTabs
        )
        assertValidationError(
            .invalidZoomedPane(absentPane),
            controller: controller,
            tree: .init(
                root: .pane(.init(id: pane, tabs: [first, second, third])),
                zoomedPane: .pane(absentPane)
            ),
            exactTabIDs: currentTabs
        )
        assertValidationError(
            .zoomRequiresMultiplePanes(pane),
            controller: controller,
            tree: .init(
                root: .pane(.init(id: pane, tabs: [first, second, third])),
                zoomedPane: .pane(pane)
            ),
            exactTabIDs: currentTabs
        )

        let unexpected = TabID()
        assertValidationError(
            .tabSetMismatch(missing: [third], unexpected: [unexpected]),
            controller: controller,
            tree: .init(root: .pane(.init(id: pane, tabs: [first, second, unexpected]))),
            exactTabIDs: currentTabs
        )
    }

    @MainActor
    func testExpectedTabSetOverloadSupportsPretransferValidation() throws {
        let controller = BonsplitController()
        let pane = try XCTUnwrap(controller.focusedPaneId)
        let current = try XCTUnwrap(controller.tabs(inPane: pane).first?.id)
        let incoming = TabID()
        let destination = BonsplitAuthoritativeTree(
            root: .pane(.init(id: pane, tabs: [current, incoming]))
        )

        XCTAssertNoThrow(try controller.validateAuthoritativeTree(
            destination,
            exactTabIDs: [current, incoming]
        ))
        XCTAssertThrowsError(try controller.validateAuthoritativeTree(destination))
        XCTAssertThrowsError(try controller.applyAuthoritativeTree(destination))
        XCTAssertEqual(controller.tabs(inPane: pane).map(\.id), [current])
    }

    @MainActor
    func testDefaultPoliciesPreserveSurvivingPresentationStateAcrossRebuild() throws {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let firstPane = try XCTUnwrap(controller.focusedPaneId)
        let welcome = try XCTUnwrap(controller.tabs(inPane: firstPane).first?.id)
        let selected = try XCTUnwrap(controller.createTab(title: "Selected"))
        let secondTab = Tab(title: "Second pane")
        let secondPane = try XCTUnwrap(controller.splitPane(
            firstPane,
            orientation: .horizontal,
            withTab: secondTab
        ))
        controller.selectTab(selected)
        XCTAssertTrue(controller.setFullWidthTabMode(true, inPane: firstPane))
        controller.focusPane(secondPane)
        XCTAssertTrue(controller.togglePaneZoom(inPane: secondPane))

        let replacement = BonsplitAuthoritativeTree(root: .split(.init(
            id: UUID(),
            orientation: .vertical,
            ratio: 0.4,
            first: .pane(.init(id: secondPane, tabs: [secondTab.id])),
            second: .pane(.init(id: firstPane, tabs: [selected, welcome]))
        )))

        XCTAssertTrue(try controller.applyAuthoritativeTree(replacement))
        XCTAssertEqual(controller.tabs(inPane: firstPane).map(\.id), [selected, welcome])
        XCTAssertEqual(controller.selectedTabId(inPane: firstPane), selected)
        XCTAssertTrue(controller.isFullWidthTabMode(inPane: firstPane))
        XCTAssertEqual(controller.focusedPaneId, secondPane)
        XCTAssertEqual(controller.zoomedPaneId, secondPane)
    }

    @MainActor
    func testValidatorRejectsEmptyAndCrossKindNodeIdentities() throws {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(newTabPosition: .end)
        )
        let pane = try XCTUnwrap(controller.focusedPaneId)
        let first = try XCTUnwrap(controller.tabs(inPane: pane).first?.id)
        let second = try XCTUnwrap(controller.createTab(title: "Second"))
        let currentTabs: Set<TabID> = [first, second]
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

        assertValidationError(
            .emptyPaneID,
            controller: controller,
            tree: .init(root: .pane(.init(
                id: PaneID(id: zero),
                tabs: [first, second]
            ))),
            exactTabIDs: currentTabs
        )
        assertValidationError(
            .emptyTabID,
            controller: controller,
            tree: .init(root: .pane(.init(
                id: pane,
                tabs: [TabID(uuid: zero)]
            ))),
            exactTabIDs: [TabID(uuid: zero)]
        )
        assertValidationError(
            .emptySplitID,
            controller: controller,
            tree: .init(root: .split(.init(
                id: zero,
                orientation: .horizontal,
                ratio: 0.5,
                first: .pane(.init(id: pane, tabs: [first])),
                second: .pane(.init(id: PaneID(), tabs: [second]))
            ))),
            exactTabIDs: currentTabs
        )

        let collidingPane = PaneID()
        assertValidationError(
            .duplicateNodeIdentity(collidingPane.id),
            controller: controller,
            tree: .init(root: .split(.init(
                id: collidingPane.id,
                orientation: .horizontal,
                ratio: 0.5,
                first: .pane(.init(id: collidingPane, tabs: [first])),
                second: .pane(.init(id: PaneID(), tabs: [second]))
            ))),
            exactTabIDs: currentTabs
        )
    }

    @MainActor
    private func assertValidationError(
        _ expected: BonsplitAuthoritativeTreeError,
        controller: BonsplitController,
        tree: BonsplitAuthoritativeTree,
        exactTabIDs: Set<TabID>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try controller.validateAuthoritativeTree(tree, exactTabIDs: exactTabIDs),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? BonsplitAuthoritativeTreeError,
                expected,
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func sameRootIdentity(_ first: SplitNode, _ second: SplitNode) -> Bool {
        switch (first, second) {
        case (.pane(let lhs), .pane(let rhs)):
            return lhs === rhs
        case (.split(let lhs), .split(let rhs)):
            return lhs === rhs
        default:
            return false
        }
    }

    private func requiresSendable<T: Sendable>(_ value: T) {}
}
