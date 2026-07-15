import AppKit
import Testing
@testable import Bonsplit

@Suite("Tab context menu grouping")
@MainActor
struct TabContextMenuGroupingTests {
    @Test func groupsActionsByIntent() throws {
        let target = TabContextMenuActionTarget()
        let state = TabContextMenuState(
            isPinned: false,
            isUnread: false,
            isBrowser: false,
            isAudioMuted: false,
            isTerminal: true,
            hasCustomTitle: true,
            canCloseCurrent: true,
            canCloseToLeft: true,
            canCloseToRight: true,
            canCloseOthers: true,
            canMoveToNewWorkspace: true,
            canMoveToLeftPane: true,
            canMoveToRightPane: true,
            forkConversationDefaultAction: .forkConversationRight,
            isZoomed: false,
            hasSplits: true,
            shortcuts: [:],
            canDisconnectRemote: true
        )
        let menu = TabContextMenuBuilder.makeMenu(
            snapshot: TabContextMenuSnapshot(
                tabId: UUID(),
                state: state,
                moveDestinationsProvider: { [] },
                forkConversationAvailabilityProvider: { .available }
            ),
            target: target
        )

        #expect(sectionTitles(in: menu) == [
            ["Rename Tab…", "Remove Custom Tab Name", "Close Tab"],
            ["New Terminal Tab to Right", "New Browser Tab to Right"],
            [
                "Move Tab",
                "Move to Left Pane",
                "Move to Right Pane",
                "Close Tabs to Left",
                "Close Tabs to Right",
                "Close Other Tabs",
            ],
            ["Fork Conversation to the Right", "Fork Conversation To", "Disconnect SSH"],
            ["Zoom Pane", "Full Width Tab", "Pin Tab", "Mark Tab as Unread"],
            ["Copy IDs"],
        ])
    }

    @Test func closeItemUsesSharedCloseRequest() throws {
        let controller = BonsplitController()
        let paneId = try #require(controller.focusedPaneId)
        let tabId = try #require(controller.createTab(title: "Close me", inPane: paneId))
        var closeSource: TabCloseRequestSource?
        controller.onTabCloseRequest = { closedTabId, closedPaneId, source in
            #expect(closedTabId == tabId)
            #expect(closedPaneId == paneId)
            closeSource = source
        }

        controller.requestTabContextAction(.close, for: tabId, inPane: paneId)

        #expect(closeSource == .contextMenu)
        #expect(controller.tab(tabId) == nil)
    }

    private func sectionTitles(in menu: NSMenu) -> [[String]] {
        menu.items.reduce(into: [[]]) { sections, item in
            if item.isSeparatorItem {
                sections.append([])
            } else {
                sections[sections.count - 1].append(item.title)
            }
        }
    }
}
