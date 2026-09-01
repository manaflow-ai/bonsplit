import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Bonsplit

@Suite("Hot-path caching")
struct HotPathCachingTests {
    @MainActor
    @Test("split action symbol validation runs at most once per name")
    func splitActionSystemImageLookupIsCached() {
        let activity = BonsplitDebugCounters.measureHotPathActivity {
            _ = TabBarStyling.splitActionSystemImage(for: "bonsplit.missing.test.symbol")
            _ = TabBarStyling.splitActionSystemImage(for: "bonsplit.missing.test.symbol")
        }

        #expect(activity.splitActionSystemImageLookupCount <= 1)
    }

    @Test("custom drag types are constructed at most once")
    func customDragTypesAreStableValues() {
        let activity = BonsplitDebugCounters.measureHotPathActivity {
            _ = UTType.tabItem
            _ = UTType.tabItem
            _ = UTType.tabTransfer
            _ = UTType.tabTransfer
        }

        #expect(activity.tabItemTypeConstructionCount <= 1)
        #expect(activity.tabTransferTypeConstructionCount <= 1)
    }

    @MainActor
    @Test("tab body projection does not decode favicon data")
    func tabBodyProjectionDoesNotDecodeFaviconData() throws {
        let faviconData = try #require(makeFaviconData())
        let view = makeTabItemView(faviconData: faviconData)

        let activity = BonsplitDebugCounters.measureHotPathActivity {
            _ = view.body
            _ = view.body
        }

        #expect(activity.faviconImageDecodeCount == 0)
    }

    @MainActor
    private func makeFaviconData() -> Data? {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()
        return image.tiffRepresentation
    }

    @MainActor
    private func makeTabItemView(faviconData: Data) -> TabItemView {
        TabItemView(
            tab: TabItem(title: "Browser", icon: "globe", iconImageData: faviconData),
            isSelected: true,
            showsZoomIndicator: false,
            appearance: .default,
            fillsWidth: false,
            saturation: 1,
            trailingSeparatorBottomInset: 0,
            controlShortcutDigit: nil,
            tabShortcutHintsEnabled: false,
            isFocused: true,
            showsControlShortcutHint: false,
            shortcutModifierSymbol: "⌃",
            allowsClose: true,
            allowsContextMenu: false,
            contextMenuState: TabContextMenuState(
                isPinned: false,
                isUnread: false,
                isBrowser: true,
                isAudioMuted: false,
                isTerminal: false,
                hasCustomTitle: false,
                canCloseToLeft: false,
                canCloseToRight: false,
                canCloseOthers: false,
                canMoveToNewWorkspace: false,
                canMoveToLeftPane: false,
                canMoveToRightPane: false,
                forkConversationDefaultAction: .forkConversationRight,
                isZoomed: false,
                hasSplits: false,
                shortcuts: [:]
            ),
            moveDestinationsProvider: { [] },
            forkConversationAvailabilityProvider: { .hidden },
            forkConversationAvailabilityRefreshHandler: {},
            onSelect: {},
            onClose: { _ in },
            onZoomToggle: {},
            onContextAction: { _ in },
            onMoveDestination: { _ in }
        )
    }
}
