import XCTest
@testable import Bonsplit
import AppKit
import SwiftUI

final class TabPresenceTests: XCTestCase {
    private func samplePresence(mode: TabPresence.SizeMode = .priority, canDisconnect: Bool = false, alone: Bool = false) -> TabPresence {
        TabPresence(
            participants: alone ? [] : [
                .init(id: "user:u_maya", initials: "MO", isOwner: true, accessibilityName: "Maya Ortiz"),
                .init(id: "device:iphone", initials: "", symbolName: "iphone", isOwner: false, accessibilityName: "iPhone"),
            ],
            sizeMode: mode,
            canDisconnectOthers: canDisconnect,
            accessibilityLabel: "Size set by Maya's Mac · 118×38"
        )
    }

    /// Overlapping avatars clipped the first letter of every later one
    /// ("MC" read ".C"). Three avatars must sit side by side, so the accessory
    /// is at least three avatars plus its padding wide.
    @MainActor
    func testAccessoryAvatarsDoNotOverlap() {
        let presence = TabPresence(
            participants: [
                .init(id: "user:u_li", initials: "LC", isOwner: false, accessibilityName: "Li"),
                .init(id: "user:u_mc", initials: "MC", isOwner: false, accessibilityName: "Mo"),
                .init(id: "user:u_ww", initials: "WW", isOwner: false, accessibilityName: "Wu"),
            ],
            sizeMode: .smallest,
            canDisconnectOthers: false,
            accessibilityLabel: "Size"
        )
        let appearance = BonsplitConfiguration.Appearance(chromeColors: .init(backgroundHex: "#ffffff"))
        let host = NSHostingView(rootView: TabPresenceAccessoryView(
            presence: presence,
            colors: TabBarColors.presenceColors(for: appearance, isSelected: true),
            isHovered: false,
            hoverBackground: .clear
        ))
        let avatars = CGFloat(TabPresenceAccessoryView.maxAvatars) * TabPresenceAccessoryView.avatarSize
        XCTAssertGreaterThanOrEqual(host.fittingSize.width, avatars + 2 * TabPresenceAccessoryView.horizontalPadding)
    }

    func testAccessoryShowsOnlyWithParticipants() {
        XCTAssertTrue(samplePresence().showsAccessory)
        XCTAssertFalse(samplePresence(alone: true).showsAccessory)
    }

    func testTabItemCodableRoundTripsPresence() throws {
        let presence = samplePresence()
        let item = TabItem(title: "zsh", presence: presence)
        let decoded = try JSONDecoder().decode(TabItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.presence, presence)

        let legacy = try JSONDecoder().decode(TabItem.self, from: JSONEncoder().encode(TabItem(title: "zsh")))
        XCTAssertNil(legacy.presence)
    }

    @MainActor
    func testUpdateTabSetsKeepsAndClearsPresence() throws {
        let controller = BonsplitController()
        let tabId = try XCTUnwrap(controller.createTab(title: "zsh"))
        XCTAssertNil(controller.tab(tabId)?.presence)

        let presence = samplePresence()
        controller.updateTab(tabId, presence: .some(presence))
        XCTAssertEqual(controller.tab(tabId)?.presence, presence)

        controller.updateTab(tabId, title: "renamed")
        XCTAssertEqual(controller.tab(tabId)?.presence, presence)

        controller.updateTab(tabId, presence: .some(nil))
        XCTAssertNil(controller.tab(tabId)?.presence)
    }

    func testSizeModeActionsRoundTrip() {
        for mode in TabPresence.SizeMode.allCases {
            XCTAssertEqual(TabContextAction.sizeMode(mode).sizeMode, mode)
        }
        XCTAssertNil(TabContextAction.toggleSizePanel.sizeMode)
    }

    @MainActor
    func testContextMenuAddsTerminalSizeSectionOnlyWithPresence() throws {
        let target = TabContextMenuActionTarget()
        var selected: TabContextAction?
        target.onContextAction = { selected = $0 }

        func menu(presence: TabPresence?) -> NSMenu {
            let state = TabContextMenuState(
                isPinned: false, isUnread: false, isBrowser: false, isAudioMuted: false,
                isTerminal: true, hasCustomTitle: false, canCloseToLeft: false,
                canCloseToRight: false, canCloseOthers: false, canMoveToNewWorkspace: false,
                canMoveToLeftPane: false, canMoveToRightPane: false,
                forkConversationDefaultAction: .forkConversationRight, isZoomed: false,
                hasSplits: false, shortcuts: [:], presence: presence
            )
            let snapshot = TabContextMenuSnapshot(
                tabId: UUID(), state: state,
                moveDestinationsProvider: { [] },
                forkConversationAvailabilityProvider: { .hidden }
            )
            return TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: target)
        }

        XCTAssertFalse(menu(presence: nil).items.contains { $0.title == "Size to My Window" })

        let alone = menu(presence: samplePresence(mode: .priority, canDisconnect: false, alone: true))
        let titles = alone.items.map(\.title)
        XCTAssertTrue(titles.contains("Size to My Window"))
        XCTAssertFalse(titles.contains("Disconnect Others…"))
        for removed in ["Don't Resize from This Mac", "Show Size Panel…"] {
            XCTAssertFalse(titles.contains(removed), "unexpected \(removed)")
        }
        let sizeMenu = try XCTUnwrap(alone.items.first { $0.title == "Terminal Size" }?.submenu)
        XCTAssertEqual(
            sizeMenu.items.map(\.title),
            ["Follow Latest", "Fit Everyone", "Largest Window", "Priority List…", "Fixed Size…"]
        )
        XCTAssertEqual(sizeMenu.items.first { $0.title == "Priority List…" }?.state, .on)
        XCTAssertEqual(sizeMenu.items.first { $0.title == "Follow Latest" }?.state, .off)

        let shared = menu(presence: samplePresence(mode: .latest, canDisconnect: true))
        XCTAssertTrue(shared.items.contains { $0.title == "Disconnect Others…" })

        let largest = try XCTUnwrap(sizeMenu.items.first { $0.title == "Largest Window" })
        target.performContextAction(largest)
        XCTAssertEqual(selected, .sizeModeLargest)
    }

    @MainActor
    func testPopoverAnchorPrefersVisibleAccessoryOverTabItem() {
        let controller = BonsplitController()
        let tabId = TabID()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [], backing: .buffered, defer: true)
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content

        let item = TabPopoverAnchorView.AnchorNSView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        content.addSubview(item)
        item.configure(tabId: tabId.id, kind: .tabItem)
        XCTAssertTrue(controller.popoverAnchorView(for: tabId) === item)

        let accessory = TabPopoverAnchorView.AnchorNSView(frame: NSRect(x: 80, y: 5, width: 30, height: 18))
        content.addSubview(accessory)
        accessory.configure(tabId: tabId.id, kind: .presenceAccessory)
        XCTAssertTrue(controller.popoverAnchorView(for: tabId) === accessory)

        accessory.removeFromSuperview()
        XCTAssertTrue(controller.popoverAnchorView(for: tabId) === item)
        item.isHidden = true
        XCTAssertNil(controller.popoverAnchorView(for: tabId))
    }

    func testParticipantDecodesPayloadWithoutSymbolName() throws {
        let json = ##"{"id":"c3","initials":"MO","colorHex":"#3CC2B0","isOwner":true,"accessibilityName":"Maya"}"##
        let decoded = try JSONDecoder().decode(TabPresence.Participant.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.initials, "MO")
        XCTAssertNil(decoded.symbolName)
        XCTAssertTrue(decoded.isOwner)
    }
}
