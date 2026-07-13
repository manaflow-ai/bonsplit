import Foundation

/// Protocol for receiving callbacks about tab bar events
@MainActor
public protocol BonsplitDelegate: AnyObject {
    // MARK: - Tab Lifecycle (Veto Operations)

    /// Called when a new tab is about to be created.
    /// Return `false` to prevent creation.
    func splitTabBar(_ controller: BonsplitController, shouldCreateTab tab: Tab, inPane pane: PaneID) -> Bool

    /// Called when a tab is about to be closed.
    /// Return `false` to prevent closing (e.g., prompt to save unsaved changes).
    func splitTabBar(_ controller: BonsplitController, shouldCloseTab tab: Tab, inPane pane: PaneID) -> Bool

    // MARK: - Tab Lifecycle (Notifications)

    /// Called after a tab has been created.
    func splitTabBar(_ controller: BonsplitController, didCreateTab tab: Tab, inPane pane: PaneID)

    /// Called after a tab has been closed.
    func splitTabBar(_ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID)

    /// Called when a tab is selected.
    func splitTabBar(_ controller: BonsplitController, didSelectTab tab: Tab, inPane pane: PaneID)

    /// Called when a tab is moved between panes.
    func splitTabBar(_ controller: BonsplitController, didMoveTab tab: Tab, fromPane source: PaneID, toPane destination: PaneID)

    /// Called after the user reorders tabs within a single pane (drag-reorder).
    /// `orderedTabIds` is the new full order of that pane's tabs.
    func splitTabBar(_ controller: BonsplitController, didReorderTabsInPane pane: PaneID, orderedTabIds: [TabID])

    // MARK: - Split Lifecycle (Veto Operations)

    /// Called when a split is about to be created.
    /// Return `false` to prevent the split.
    func splitTabBar(_ controller: BonsplitController, shouldSplitPane pane: PaneID, orientation: SplitOrientation) -> Bool

    /// Called when a pane is about to be closed.
    /// Return `false` to prevent closing.
    func splitTabBar(_ controller: BonsplitController, shouldClosePane pane: PaneID) -> Bool

    // MARK: - Split Lifecycle (Notifications)

    /// Called after a split has been created.
    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation)

    /// Called after a pane has been closed.
    func splitTabBar(_ controller: BonsplitController, didClosePane paneId: PaneID)

    // MARK: - Focus

    /// Called when focus changes to a different pane.
    func splitTabBar(_ controller: BonsplitController, didFocusPane pane: PaneID)

    // MARK: - New Tab Request

    /// Called when the user clicks a "new tab" action in the tab bar.
    /// The `kind` string identifies the type of tab (e.g. "terminal", "browser").
    func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID)

    /// Called when the user clicks a host-defined action in the tab bar.
    func splitTabBar(_ controller: BonsplitController, didRequestCustomAction identifier: String, inPane pane: PaneID)

    /// Called when the user triggers an action from a tab's context menu.
    func splitTabBar(_ controller: BonsplitController, didRequestTabContextAction action: TabContextAction, for tab: Tab, inPane pane: PaneID)

    /// Called when the user chooses a host-provided destination from the tab move submenu.
    func splitTabBar(_ controller: BonsplitController, didRequestTabMoveToDestination destinationId: String, for tab: Tab, inPane pane: PaneID)

    // MARK: - Geometry

    /// Called when any pane geometry changes (resize, split, close)
    func splitTabBar(_ controller: BonsplitController, didChangeGeometry snapshot: LayoutSnapshot)

    /// Called to check if notifications should be sent during divider drag (opt-in for real-time sync)
    func splitTabBar(_ controller: BonsplitController, shouldNotifyDuringDrag: Bool) -> Bool

    /// A divider drag session started: the mouse went down on a divider and
    /// AppKit's tracking loop is running. Until the matching end, the drag
    /// owns divider geometry — hosts that impose extents should defer.
    func splitTabBarDividerDragDidBegin(_ controller: BonsplitController)

    /// The divider drag session ended (mouse released). Delivered from the
    /// tracking lifecycle itself, so it fires even when no resize callback
    /// coincides with the release; the final geometry has already been
    /// reported through `didChangeGeometry`.
    func splitTabBarDividerDragDidEnd(_ controller: BonsplitController)
}

// MARK: - Default Implementations (all methods optional)

public extension BonsplitDelegate {
    func splitTabBar(_ controller: BonsplitController, shouldCreateTab tab: Tab, inPane pane: PaneID) -> Bool { true }
    func splitTabBar(_ controller: BonsplitController, shouldCloseTab tab: Tab, inPane pane: PaneID) -> Bool { true }
    func splitTabBar(_ controller: BonsplitController, didCreateTab tab: Tab, inPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didCloseTab tabId: TabID, fromPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didSelectTab tab: Tab, inPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didMoveTab tab: Tab, fromPane source: PaneID, toPane destination: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didReorderTabsInPane pane: PaneID, orderedTabIds: [TabID]) {}
    func splitTabBar(_ controller: BonsplitController, shouldSplitPane pane: PaneID, orientation: SplitOrientation) -> Bool { true }
    func splitTabBar(_ controller: BonsplitController, shouldClosePane pane: PaneID) -> Bool { true }
    func splitTabBar(_ controller: BonsplitController, didSplitPane originalPane: PaneID, newPane: PaneID, orientation: SplitOrientation) {}
    func splitTabBar(_ controller: BonsplitController, didClosePane paneId: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didFocusPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didRequestCustomAction identifier: String, inPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didRequestTabContextAction action: TabContextAction, for tab: Tab, inPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didRequestTabMoveToDestination destinationId: String, for tab: Tab, inPane pane: PaneID) {}
    func splitTabBar(_ controller: BonsplitController, didChangeGeometry snapshot: LayoutSnapshot) {}
    func splitTabBar(_ controller: BonsplitController, shouldNotifyDuringDrag: Bool) -> Bool { false }
    func splitTabBarDividerDragDidBegin(_ controller: BonsplitController) {}
    func splitTabBarDividerDragDidEnd(_ controller: BonsplitController) {}
}
