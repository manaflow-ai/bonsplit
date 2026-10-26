import AppKit
@testable import Bonsplit
import SwiftUI
import XCTest

/// Rendering the tab strip must not run work that only an open context menu
/// needs. Hosts back the context-menu providers with their own state (cmux
/// reads user defaults there), and the strip re-renders every tab on focus,
/// resize and hint changes, so per-render host calls multiply into main-thread
/// hangs (Sentry CMUXTERM-MACOS-41NN, -2QV2, -2QAN).
@MainActor
final class TabBarRenderWorkTests: XCTestCase {
    func testRenderingTabsDoesNotQueryContextMenuProviders() throws {
        let size = NSSize(width: 900, height: TabBarMetrics.barHeight)
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(appearance: .init(enableAnimations: false))
        )
        var forkDefaultActionQueries = 0
        var disconnectRemoteQueries = 0
        controller.tabContextForkConversationDefaultActionProvider = { _, _ in
            forkDefaultActionQueries += 1
            return .defaultForkConversationDestination
        }
        controller.tabContextDisconnectRemoteAvailabilityProvider = { _, _ in
            disconnectRemoteQueries += 1
            return false
        }
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        let tabs = (0..<6).map { TabItem(title: "Terminal \($0)", icon: "terminal.fill", kind: "terminal") }
        pane.tabs = tabs
        pane.selectedTabId = tabs[0].id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: false)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try XCTUnwrap(window.contentView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)
        settleLayout(in: window, hostingView: hostingView)

        // Re-render every tab the way selection and title updates do.
        for index in 1..<tabs.count {
            pane.selectedTabId = tabs[index].id
            tabs[index].title = "Renamed \(index)"
            settleLayout(in: window, hostingView: hostingView, passes: 2)
        }

        XCTAssertEqual(forkDefaultActionQueries, 0, "Rendering tabs must not ask the host for the fork default action")
        XCTAssertEqual(disconnectRemoteQueries, 0, "Rendering tabs must not ask the host for remote disconnect availability")
    }

    func testMenuBuildEvaluatesTabStateOnce() {
        var stateEvaluations = 0
        let snapshot = TabContextMenuSnapshot(
            tabId: UUID(),
            stateProvider: {
                stateEvaluations += 1
                return TabContextMenuState(
                    isPinned: false,
                    isUnread: false,
                    isBrowser: false,
                    isAudioMuted: false,
                    isTerminal: true,
                    hasCustomTitle: false,
                    canCloseToLeft: true,
                    canCloseToRight: true,
                    canCloseOthers: true,
                    canMoveToNewWorkspace: true,
                    canMoveToLeftPane: false,
                    canMoveToRightPane: true,
                    forkConversationDefaultAction: .forkConversationRight,
                    isZoomed: false,
                    hasSplits: true,
                    shortcuts: [:]
                )
            },
            moveDestinationsProvider: { [] },
            forkConversationAvailabilityProvider: { .hidden }
        )
        XCTAssertEqual(stateEvaluations, 0, "Creating a snapshot must not compute the menu state")

        let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: TabContextMenuActionTarget())
        XCTAssertFalse(menu.items.isEmpty)
        XCTAssertEqual(stateEvaluations, 1, "One menu build reads one state value")
    }

    func testSustainedTabBarRendersEmitOneDiagnostic() throws {
        let controller = BonsplitController()
        let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
        var diagnostics: [TabBarRenderDiagnostic] = []
        controller.onTabBarRenderDiagnostic = { diagnostics.append($0) }

        for index in 0..<31 {
            controller.internalController.recordTabBarRender(
                paneId: pane.id,
                tabCount: pane.tabs.count,
                now: 100 + Double(index) * (0.5 / 31)
            )
        }
        XCTAssertTrue(diagnostics.isEmpty)

        controller.internalController.recordTabBarRender(
            paneId: pane.id,
            tabCount: pane.tabs.count,
            now: 100.5
        )
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics[0].renderCount, 32)
        XCTAssertEqual(diagnostics[0].paneCount, 1)

        controller.internalController.recordTabBarRender(
            paneId: pane.id,
            tabCount: pane.tabs.count,
            now: 100.6
        )
        XCTAssertEqual(diagnostics.count, 1)
    }

    private func settleLayout(in window: NSWindow, hostingView: NSView, passes: Int = 6) {
        for _ in 0..<passes {
            window.contentView?.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.01))
        }
    }
}
