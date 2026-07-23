import XCTest
@testable import Bonsplit

@MainActor
final class EmbeddedConfigurationTests: XCTestCase {
    func testEmbeddedBehaviorControlsAreOptIn() {
        let configuration = BonsplitConfiguration()

        XCTAssertTrue(configuration.allowsTabContextMenu)
        XCTAssertEqual(configuration.dividerPositionRange, 0.1...0.9)
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

    func testManualTabReorderFallbackInstallsForMinimalModeOrExplicitHostRequest() {
        XCTAssertFalse(TabBarManualReorderPolicy.shouldInstall(
            allowsTabReordering: true,
            isMinimalMode: false,
            hostRequestsFallback: false
        ))
        XCTAssertTrue(TabBarManualReorderPolicy.shouldInstall(
            allowsTabReordering: true,
            isMinimalMode: true,
            hostRequestsFallback: false
        ))
        XCTAssertTrue(TabBarManualReorderPolicy.shouldInstall(
            allowsTabReordering: true,
            isMinimalMode: false,
            hostRequestsFallback: true
        ))
        XCTAssertFalse(TabBarManualReorderPolicy.shouldInstall(
            allowsTabReordering: false,
            isMinimalMode: true,
            hostRequestsFallback: true
        ))
    }

    func testManualTabReorderFallbackYieldsToMatchingItemProviderDrag() {
        let sourceTabId = UUID()
        XCTAssertTrue(TabBarManualReorderPolicy.shouldApplyFallback(
            sourceTabId: sourceTabId,
            activeDragTabId: nil,
            draggingTabId: nil
        ))
        XCTAssertFalse(TabBarManualReorderPolicy.shouldApplyFallback(
            sourceTabId: sourceTabId,
            activeDragTabId: sourceTabId,
            draggingTabId: nil
        ))
        XCTAssertFalse(TabBarManualReorderPolicy.shouldApplyFallback(
            sourceTabId: sourceTabId,
            activeDragTabId: nil,
            draggingTabId: sourceTabId
        ))
    }

    func testDeferredManualFallbackOnlyAppliesToAnUnchangedSourcePane() {
        let sourceTabId = UUID()
        let siblingTabId = UUID()
        let originalOrder = [siblingTabId, sourceTabId]

        XCTAssertTrue(TabBarManualReorderPolicy.shouldApplyDeferredFallback(
            sourceTabId: sourceTabId,
            originalTabIds: originalOrder,
            currentTabIds: originalOrder
        ))
        XCTAssertFalse(TabBarManualReorderPolicy.shouldApplyDeferredFallback(
            sourceTabId: sourceTabId,
            originalTabIds: originalOrder,
            currentTabIds: [sourceTabId, siblingTabId]
        ))
        XCTAssertFalse(TabBarManualReorderPolicy.shouldApplyDeferredFallback(
            sourceTabId: sourceTabId,
            originalTabIds: originalOrder,
            currentTabIds: [siblingTabId]
        ))
    }
}
