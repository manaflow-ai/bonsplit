import AppKit
import SwiftUI

/// Laid-out AppKit views a host can anchor a popover to, per tab: the tab
/// item itself and, when shown, its presence accessory.
///
/// Views register while they are in a window and drop out when they leave or
/// deallocate, so a lookup never returns a view from a torn-down strip.
@MainActor
enum TabPopoverAnchorRegistry {
    enum Kind {
        case tabItem
        case presenceAccessory
    }

    private static let tabItems = NSMapTable<NSUUID, NSView>.strongToWeakObjects()
    private static let accessories = NSMapTable<NSUUID, NSView>.strongToWeakObjects()

    private static func table(_ kind: Kind) -> NSMapTable<NSUUID, NSView> {
        switch kind {
        case .tabItem: tabItems
        case .presenceAccessory: accessories
        }
    }

    static func register(_ view: NSView, tabId: UUID, kind: Kind) {
        table(kind).setObject(view, forKey: tabId as NSUUID)
    }

    static func unregister(_ view: NSView, tabId: UUID, kind: Kind) {
        let table = table(kind)
        guard table.object(forKey: tabId as NSUUID) === view else { return }
        table.removeObject(forKey: tabId as NSUUID)
    }

    /// The accessory when it is on screen, else the tab item, else nil.
    static func anchorView(for tabId: UUID) -> NSView? {
        for kind in [Kind.presenceAccessory, .tabItem] {
            if let view = table(kind).object(forKey: tabId as NSUUID), isOnScreen(view) {
                return view
            }
        }
        return nil
    }

    private static func isOnScreen(_ view: NSView) -> Bool {
        guard view.window != nil, !view.bounds.isEmpty, !view.visibleRect.isEmpty else { return false }
        var current: NSView? = view
        while let candidate = current {
            guard !candidate.isHidden, candidate.alphaValue > 0 else { return false }
            current = candidate.superview
        }
        return true
    }
}

/// A zero-behavior AppKit view that registers itself as a tab's popover anchor.
struct TabPopoverAnchorView: NSViewRepresentable {
    let tabId: UUID
    let kind: TabPopoverAnchorRegistry.Kind

    func makeNSView(context: Context) -> AnchorNSView {
        let view = AnchorNSView()
        view.configure(tabId: tabId, kind: kind)
        return view
    }

    func updateNSView(_ nsView: AnchorNSView, context: Context) {
        nsView.configure(tabId: tabId, kind: kind)
    }

    final class AnchorNSView: NSView {
        private var tabId: UUID?
        private var kind: TabPopoverAnchorRegistry.Kind = .tabItem

        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func isAccessibilityElement() -> Bool { false }

        func configure(tabId: UUID, kind: TabPopoverAnchorRegistry.Kind) {
            if self.tabId != tabId || self.kind != kind {
                unregister()
                self.tabId = tabId
                self.kind = kind
            }
            registerIfInWindow()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { unregister() } else { registerIfInWindow() }
        }

        private func registerIfInWindow() {
            guard window != nil, let tabId else { return }
            TabPopoverAnchorRegistry.register(self, tabId: tabId, kind: kind)
        }

        private func unregister() {
            guard let tabId else { return }
            TabPopoverAnchorRegistry.unregister(self, tabId: tabId, kind: kind)
        }
    }
}

extension BonsplitController {
    /// The view a popover about this tab should point at: the presence
    /// accessory when it is shown, else the tab item. Nil when the tab is not
    /// laid out in a window (hidden tab bar, scrolled out of the strip).
    ///
    /// - Parameter tabId: The tab.
    /// - Returns: A view in the tab strip, or nil.
    @MainActor
    public func popoverAnchorView(for tabId: TabID) -> NSView? {
        TabPopoverAnchorRegistry.anchorView(for: tabId.id)
    }
}
