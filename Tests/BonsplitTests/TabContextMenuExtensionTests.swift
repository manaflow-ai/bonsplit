import AppKit
import Testing
@testable import Bonsplit

@MainActor
@Suite struct TabContextMenuExtensionTests {
    @Test func evaluatesHostItemsOnlyWhenMenuOpens() throws {
        var requests = 0
        let item = NSMenuItem(title: "Host Action", action: nil, keyEquivalent: "")
        item.isEnabled = false
        let snapshot = TabContextMenuSnapshot(
            tabId: UUID(),
            state: TabContextMenuState(
                isPinned: false, isUnread: false, isBrowser: false, isAudioMuted: false,
                isTerminal: true, hasCustomTitle: false,
                canCloseToLeft: false, canCloseToRight: false, canCloseOthers: false,
                canMoveToNewWorkspace: false, canMoveToLeftPane: false, canMoveToRightPane: false,
                forkConversationDefaultAction: .forkConversationRight,
                isZoomed: false, hasSplits: false, shortcuts: [:]
            ),
            additionalMenuItemsProvider: { requests += 1; return [item] },
            moveDestinationsProvider: { [] },
            forkConversationAvailabilityProvider: { .hidden }
        )
        #expect(requests == 0)
        let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: TabContextMenuActionTarget())
        #expect(requests == 1)
        #expect(menu.items.contains { $0 === item })
        #expect(!item.isEnabled)
    }
}
