import Foundation
import SwiftUI

/// Central controller managing the entire split view state (internal implementation)
@Observable
@MainActor
final class SplitViewController {
    /// The public wrapper that owns this controller, for identity lookups
    /// from managed AppKit views (see `BonsplitManagedSplitView`).
    weak var publicController: BonsplitController?

    /// The root node of the split tree
    private(set) var rootNode: SplitNode

    /// Live indexes for host queries that must not walk the split tree.
    @ObservationIgnored private var paneStatesById: [PaneID: PaneState]
    @ObservationIgnored private var paneIdsByTabId: [UUID: PaneID]

    /// Focus memory: the sequence number of each pane's latest focus. A pane
    /// that has never been focused has no entry and ranks oldest.
    @ObservationIgnored private var paneFocusSequence: [PaneID: UInt64] = [:]
    @ObservationIgnored private var nextPaneFocusSequence: UInt64 = 1

    /// Creation order, which auto layout uses to place panes the way Zellij
    /// does. Panes of a host-supplied tree take their layout order.
    @ObservationIgnored private var paneCreationOrdinal: [PaneID: UInt64] = [:]
    @ObservationIgnored private var nextPaneCreationOrdinal: UInt64 = 0

    /// Currently zoomed pane. When set, rendering should only show this pane.
    var zoomedPaneId: PaneID?

    /// Currently focused pane ID. Every change of pane records focus memory,
    /// so directional navigation and close can return to where the user was.
    var focusedPaneId: PaneID? {
        didSet {
            guard let focusedPaneId, focusedPaneId != oldValue else { return }
            recordFocus(focusedPaneId)
        }
    }

    /// The only tab-drag state. SwiftUI observes this for visual feedback and
    /// hit-testing while drop delegates read the same value synchronously.
    var tabDragSession: TabDragSession?

    /// Monotonic counter incremented on each drag start. The current value is
    /// copied into ``tabDragSession`` to invalidate stale lifecycle callbacks.
    var dragGeneration: Int = 0

    /// Native sources stay alive independently of SwiftUI tab/view teardown.
    @ObservationIgnored var nativeTabDragSources: [Int: TabDragSessionSource] = [:]

    /// Process-local capability store shared by tab-drag sources and destinations.
    @ObservationIgnored let tabDragTransferRegistry: TabDragTransferRegistry

    /// When false, drop delegates reject all drags and NSViews are hidden.
    /// Mirrors BonsplitController.isInteractive. Must be observable so
    /// updateNSView is called to toggle isHidden on the AppKit containers.
    var isInteractive: Bool = true

    /// When false, pane tab shortcut hints stay hidden even if this pane is
    /// selected. The host app owns this because keyboard focus can move outside
    /// Bonsplit while the selected pane remains unchanged.
    var tabShortcutHintsEnabled: Bool = true

    /// Handler for file/URL drops from external apps (e.g. Finder).
    /// Receives the dropped URLs and the pane ID where the drop occurred.
    @ObservationIgnored var onFileDrop: ((_ urls: [URL], _ paneId: PaneID) -> Bool)?

    /// During drop, SwiftUI may keep the source tab view alive briefly (default removal animation)
    /// even after we've updated the model. Hide it explicitly so it disappears immediately.
    var dragHiddenSourceTabId: UUID?
    var dragHiddenSourcePaneId: PaneID?

    /// Current frame of the entire split view container
    var containerFrame: CGRect = .zero

    /// Flag to prevent notification loops during external updates
    var isExternalUpdateInProgress: Bool = false

    /// Timestamp of last geometry notification for debouncing
    var lastGeometryNotificationTime: TimeInterval = 0

    /// Callback for geometry changes
    var onGeometryChange: (() -> Void)?

    /// Live divider drag sessions across every split in this tree (0 or 1 in
    /// practice — AppKit tracks one divider at a time). Sessions bracket the
    /// divider's mouse-tracking lifecycle, so external sizing can consult
    /// this before writing geometry: mid-drag the user owns the divider.
    @ObservationIgnored private(set) var activeDividerDragSessions = 0
    @ObservationIgnored var onDividerDragSessionChange: ((Bool) -> Void)?

    func noteDividerDragSession(_ active: Bool) {
        // Notify only when the count crosses zero: with overlapping sessions
        // (a host-bracketed custom drag alongside the built-in tracking),
        // ending one must not announce "drag over" while the other still
        // owns the divider — a host would resume imposing under the pointer.
        let wasActive = activeDividerDragSessions > 0
        activeDividerDragSessions = max(0, activeDividerDragSessions + (active ? 1 : -1))
        let isActive = activeDividerDragSessions > 0
        if wasActive != isActive {
            onDividerDragSessionChange?(isActive)
            if !isActive {
                // Imposed applies refuse while a session is live and stay
                // armed. Give every still-imposed split one deferred apply
                // now that the drag released the divider — no epoch bump, so
                // a split already at its target just refreshes its memos.
                // The split that was dragged cleared its imposition when the
                // gesture took ownership, so it skips itself here.
                for split in allSplits where split.imposedFirstExtent != nil {
                    split.syncDividerNow?()
                }
            }
        }
    }

    convenience init(rootNode: SplitNode? = nil) {
        self.init(
            rootNode: rootNode,
            tabDragTransferRegistry: TabDragTransferRegistry()
        )
    }

    init(rootNode: SplitNode? = nil, tabDragTransferRegistry: TabDragTransferRegistry) {
        self.tabDragTransferRegistry = tabDragTransferRegistry
        let resolvedRoot: SplitNode
        let initialFocusedPaneId: PaneID?
        if let rootNode {
            resolvedRoot = rootNode
            initialFocusedPaneId = nil
        } else {
            // Initialize with a single pane containing a welcome tab
            let welcomeTab = TabItem(title: "Welcome", icon: "star")
            let initialPane = PaneState(tabs: [welcomeTab])
            resolvedRoot = .pane(initialPane)
            initialFocusedPaneId = initialPane.id
        }

        let indexes = Self.makeIndexes(for: resolvedRoot)
        self.rootNode = resolvedRoot
        self.paneStatesById = indexes.panes
        self.paneIdsByTabId = indexes.tabOwners
        self.focusedPaneId = initialFocusedPaneId
        for paneId in resolvedRoot.allPaneIds {
            assignCreationOrdinal(paneId)
        }
        if let initialFocusedPaneId {
            recordFocus(initialFocusedPaneId)
        }
    }

    // MARK: - Indexed State

    func paneState(for paneId: PaneID) -> PaneState? {
        paneStatesById[paneId]
    }

    func paneId(containing tabId: UUID) -> PaneID? {
        paneIdsByTabId[tabId]
    }

    func selectedTabId(inPane paneId: PaneID) -> UUID? {
        paneStatesById[paneId]?.selectedTabId
    }

    var paneCount: Int {
        paneStatesById.count
    }

    private static func makeIndexes(
        for rootNode: SplitNode
    ) -> (panes: [PaneID: PaneState], tabOwners: [UUID: PaneID]) {
        var panes: [PaneID: PaneState] = [:]
        var tabOwners: [UUID: PaneID] = [:]
        var pendingNodes = [rootNode]

        while let node = pendingNodes.popLast() {
            switch node {
            case .pane(let pane):
                panes[pane.id] = pane
                for tab in pane.tabs {
                    tabOwners[tab.id] = pane.id
                }
            case .split(let split):
                pendingNodes.append(split.second)
                pendingNodes.append(split.first)
            }
        }

        return (panes, tabOwners)
    }

    private func registerPane(_ pane: PaneState) {
        if let replacedPane = paneStatesById.updateValue(pane, forKey: pane.id) {
            for tab in replacedPane.tabs where paneIdsByTabId[tab.id] == pane.id {
                paneIdsByTabId.removeValue(forKey: tab.id)
            }
        }
        for tab in pane.tabs {
            paneIdsByTabId[tab.id] = pane.id
        }
        assignCreationOrdinal(pane.id)
    }

    private func unregisterPane(_ paneId: PaneID) {
        paneFocusSequence.removeValue(forKey: paneId)
        paneCreationOrdinal.removeValue(forKey: paneId)
        guard let pane = paneStatesById.removeValue(forKey: paneId) else { return }
        for tab in pane.tabs where paneIdsByTabId[tab.id] == paneId {
            paneIdsByTabId.removeValue(forKey: tab.id)
        }
    }

    private func assignCreationOrdinal(_ paneId: PaneID) {
        guard paneCreationOrdinal[paneId] == nil else { return }
        paneCreationOrdinal[paneId] = nextPaneCreationOrdinal
        nextPaneCreationOrdinal += 1
    }

    // MARK: - Focus Memory

    private func recordFocus(_ paneId: PaneID) {
        paneFocusSequence[paneId] = nextPaneFocusSequence
        nextPaneFocusSequence += 1
    }

    /// Focus recency of a pane. Larger is more recent; 0 means never focused.
    func focusRecency(of paneId: PaneID) -> UInt64 {
        paneFocusSequence[paneId] ?? 0
    }

    /// The most recently focused pane among `paneIds`, or the first of them
    /// when none has been focused.
    func mostRecentlyFocusedPane(among paneIds: [PaneID]) -> PaneID? {
        var best: (paneId: PaneID, recency: UInt64)?
        for paneId in paneIds {
            let recency = focusRecency(of: paneId)
            if best == nil || recency > best!.recency {
                best = (paneId, recency)
            }
        }
        return best?.paneId
    }

    // MARK: - Focus Management

    /// Set focus to a specific pane
    func focusPane(_ paneId: PaneID) {
        guard paneStatesById[paneId] != nil else { return }
#if DEBUG
        dlog("focus.bonsplit pane=\(paneId.id.uuidString.prefix(5))")
#endif
        focusedPaneId = paneId
    }

    /// Get the currently focused pane state
    var focusedPane: PaneState? {
        guard let focusedPaneId else { return nil }
        return paneStatesById[focusedPaneId]
    }

    var zoomedNode: SplitNode? {
        guard let zoomedPaneId, let pane = paneStatesById[zoomedPaneId] else { return nil }
        return .pane(pane)
    }

    @discardableResult
    func clearPaneZoom() -> Bool {
        guard zoomedPaneId != nil else { return false }
        zoomedPaneId = nil
        return true
    }

    @discardableResult
    func togglePaneZoom(_ paneId: PaneID) -> Bool {
        guard paneStatesById[paneId] != nil else { return false }

        if zoomedPaneId == paneId {
            zoomedPaneId = nil
            return true
        }

        // Match Ghostty behavior: a single-pane layout can't be zoomed.
        guard paneStatesById.count > 1 else { return false }
        zoomedPaneId = paneId
        focusedPaneId = paneId
        return true
    }

    // MARK: - Split Operations

    /// Inserts a new pane beside the entire existing tree.
    ///
    /// Unlike `splitPane`, this operation does not descend into a leaf. The
    /// existing root remains intact as one child of the new root split.
    @discardableResult
    func splitRootWithTab(
        orientation: SplitOrientation,
        tab: TabItem,
        insertFirst: Bool,
        initialDividerPosition: CGFloat?
    ) -> PaneID {
        clearPaneZoom()
        let newPane = PaneState(tabs: [tab])
        let existingRoot = rootNode
        let splitState: SplitState
        if insertFirst {
            splitState = SplitState(
                orientation: orientation,
                first: .pane(newPane),
                second: existingRoot,
                dividerPosition: normalizedInitialDividerPosition(initialDividerPosition),
                animationOrigin: .fromFirst
            )
        } else {
            splitState = SplitState(
                orientation: orientation,
                first: existingRoot,
                second: .pane(newPane),
                dividerPosition: normalizedInitialDividerPosition(initialDividerPosition),
                animationOrigin: .fromSecond
            )
        }
        rootNode = .split(splitState)
        registerPane(newPane)
        focusedPaneId = newPane.id
        return newPane.id
    }

    /// Split the specified pane in the given orientation
    func splitPane(
        _ paneId: PaneID,
        orientation: SplitOrientation,
        with newTab: TabItem? = nil,
        initialDividerPosition: CGFloat? = nil
    ) {
        guard paneStatesById[paneId] != nil else { return }
        clearPaneZoom()
        var createdPane: PaneState?
        rootNode = splitNodeRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            newTab: newTab,
            initialDividerPosition: initialDividerPosition,
            createdPane: &createdPane
        )
        if let createdPane {
            registerPane(createdPane)
        }
    }

    private func splitNodeRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        newTab: TabItem?,
        initialDividerPosition: CGFloat?,
        createdPane: inout PaneState?
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                // Create new pane - empty if no tab provided (gives developer full control)
                let newPane: PaneState
                if let tab = newTab {
                    newPane = PaneState(tabs: [tab])
                } else {
                    newPane = PaneState(tabs: [])
                }

                // Start with divider at the edge so there's no flash before animation
                let splitState = SplitState(
                    orientation: orientation,
                    first: .pane(paneState),
                    second: .pane(newPane),
                    // Keep the model at its steady-state ratio. The view layer can still animate
                    // from an edge via animationOrigin, but the model should never represent a
                    // fully-collapsed pane (which can get stuck under view reparenting timing).
                    dividerPosition: normalizedInitialDividerPosition(initialDividerPosition),
                    animationOrigin: .fromSecond  // New pane slides in from right/bottom
                )

                // Focus the new pane
                focusedPaneId = newPane.id
                createdPane = newPane

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            splitState.first = splitNodeRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                newTab: newTab,
                initialDividerPosition: initialDividerPosition,
                createdPane: &createdPane
            )
            if createdPane == nil {
                splitState.second = splitNodeRecursively(
                    node: splitState.second,
                    targetPaneId: targetPaneId,
                    orientation: orientation,
                    newTab: newTab,
                    initialDividerPosition: initialDividerPosition,
                    createdPane: &createdPane
                )
            }
            return .split(splitState)
        }
    }

    /// Split a pane with a specific tab, optionally inserting the new pane first
    func splitPaneWithTab(
        _ paneId: PaneID,
        orientation: SplitOrientation,
        tab: TabItem,
        insertFirst: Bool,
        initialDividerPosition: CGFloat? = nil
    ) {
        guard paneStatesById[paneId] != nil else { return }
        clearPaneZoom()
        var createdPane: PaneState?
        rootNode = splitNodeWithTabRecursively(
            node: rootNode,
            targetPaneId: paneId,
            orientation: orientation,
            tab: tab,
            insertFirst: insertFirst,
            initialDividerPosition: initialDividerPosition,
            createdPane: &createdPane
        )
        if let createdPane {
            registerPane(createdPane)
        }
    }

    private func splitNodeWithTabRecursively(
        node: SplitNode,
        targetPaneId: PaneID,
        orientation: SplitOrientation,
        tab: TabItem,
        insertFirst: Bool,
        initialDividerPosition: CGFloat?,
        createdPane: inout PaneState?
    ) -> SplitNode {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                // Create new pane with the tab
                let newPane = PaneState(tabs: [tab])

                // Start with divider at the edge so there's no flash before animation
                let splitState: SplitState
                if insertFirst {
                    // New pane goes first (left or top).
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(newPane),
                        second: .pane(paneState),
                        dividerPosition: normalizedInitialDividerPosition(initialDividerPosition),
                        animationOrigin: .fromFirst
                    )
                } else {
                    // New pane goes second (right or bottom).
                    splitState = SplitState(
                        orientation: orientation,
                        first: .pane(paneState),
                        second: .pane(newPane),
                        dividerPosition: normalizedInitialDividerPosition(initialDividerPosition),
                        animationOrigin: .fromSecond
                    )
                }

                // Focus the new pane
                focusedPaneId = newPane.id
                createdPane = newPane

                return .split(splitState)
            }
            return node

        case .split(let splitState):
            splitState.first = splitNodeWithTabRecursively(
                node: splitState.first,
                targetPaneId: targetPaneId,
                orientation: orientation,
                tab: tab,
                insertFirst: insertFirst,
                initialDividerPosition: initialDividerPosition,
                createdPane: &createdPane
            )
            if createdPane == nil {
                splitState.second = splitNodeWithTabRecursively(
                    node: splitState.second,
                    targetPaneId: targetPaneId,
                    orientation: orientation,
                    tab: tab,
                    insertFirst: insertFirst,
                    initialDividerPosition: initialDividerPosition,
                    createdPane: &createdPane
                )
            }
            return .split(splitState)
        }
    }

    // MARK: - Auto Layout

    /// Adds a pane holding `tab` and arranges every pane in Zellij's default
    /// tiled swap layout, the layout cmux-tui's Alt-n reproduces. Panes keep
    /// their identity and tabs; only the split structure is rebuilt, so
    /// manual divider positions are replaced by equal sizes.
    @discardableResult
    func insertPaneWithAutoLayout(tab: TabItem) -> PaneID {
        clearPaneZoom()
        let newPane = PaneState(tabs: [tab])
        let existingPanes = rootNode.allPanes.enumerated().sorted { a, b in
            let aOrdinal = paneCreationOrdinal[a.element.id] ?? UInt64(a.offset)
            let bOrdinal = paneCreationOrdinal[b.element.id] ?? UInt64(b.offset)
            return aOrdinal < bOrdinal
        }.map(\.element)
        registerPane(newPane)
        rootNode = Self.autoLayoutRoot(for: existingPanes + [newPane])
        focusedPaneId = newPane.id
        return newPane.id
    }

    /// Column sizes of Zellij's default `vertical` swap layout for `count`
    /// panes in creation order. Up to five panes, the first pane keeps the
    /// left column and the rest share a column. Beyond that, columns hold
    /// four panes and the first column takes the remainder, so every new
    /// pane fills the right column before another column opens.
    static func autoLayoutColumnSizes(paneCount count: Int) -> [Int] {
        guard count > 1 else { return count == 1 ? [1] : [] }
        if count <= 5 { return [1, count - 1] }
        let remainder = count % 4
        let first = remainder == 0 ? 4 : remainder
        return [first] + Array(repeating: 4, count: (count - first) / 4)
    }

    private static func autoLayoutRoot(for panes: [PaneState]) -> SplitNode {
        var columns: [SplitNode] = []
        var start = 0
        for size in autoLayoutColumnSizes(paneCount: panes.count) {
            let column = panes[start..<(start + size)].map { SplitNode.pane($0) }
            columns.append(equalSplit(column, orientation: .vertical))
            start += size
        }
        return equalSplit(columns, orientation: .horizontal)
    }

    /// Chains `nodes` into splits whose divider positions give every node the
    /// same share of the axis.
    private static func equalSplit(_ nodes: [SplitNode], orientation: SplitOrientation) -> SplitNode {
        guard nodes.count > 1 else { return nodes[0] }
        return .split(SplitState(
            orientation: orientation,
            first: nodes[0],
            second: equalSplit(Array(nodes.dropFirst()), orientation: orientation),
            dividerPosition: 1 / CGFloat(nodes.count)
        ))
    }

    private func normalizedInitialDividerPosition(_ position: CGFloat?) -> CGFloat {
        guard let position else { return 0.5 }
        return min(max(position, 0), 1)
    }

    /// Moves an existing pane leaf to an edge of the complete split tree.
    @discardableResult
    func movePane(
        _ paneId: PaneID,
        toRootEdge edge: RootSplitEdge,
        dividerPosition: CGFloat
    ) -> Bool {
        guard paneStatesById.count > 1,
              let pane = paneStatesById[paneId],
              !isPaneDirectRootChild(paneId, on: edge),
              let remainder = removingPane(paneId, from: rootNode) else {
            return false
        }

        clearPaneZoom()
        let movedPane = SplitNode.pane(pane)
        let splitState = SplitState(
            orientation: edge.orientation,
            first: edge.insertsFirst ? movedPane : remainder,
            second: edge.insertsFirst ? remainder : movedPane,
            dividerPosition: normalizedInitialDividerPosition(dividerPosition)
        )
        rootNode = .split(splitState)
        focusedPaneId = paneId
        return true
    }

    private func isPaneDirectRootChild(
        _ paneId: PaneID,
        on edge: RootSplitEdge
    ) -> Bool {
        guard case .split(let rootSplit) = rootNode,
              rootSplit.orientation == edge.orientation else {
            return false
        }

        let edgeNode = edge.insertsFirst ? rootSplit.first : rootSplit.second
        guard case .pane(let pane) = edgeNode else { return false }
        return pane.id == paneId
    }

    private func removingPane(
        _ paneId: PaneID,
        from node: SplitNode
    ) -> SplitNode? {
        switch node {
        case .pane(let pane):
            return pane.id == paneId ? nil : node

        case .split(let split):
            let first = removingPane(paneId, from: split.first)
            let second = removingPane(paneId, from: split.second)

            switch (first, second) {
            case (nil, nil):
                return nil
            case (nil, let second?):
                return second
            case (let first?, nil):
                return first
            case (let first?, let second?):
                let rebuilt = SplitState(
                    id: split.id,
                    orientation: split.orientation,
                    first: first,
                    second: second,
                    dividerPosition: split.dividerPosition,
                    animationOrigin: split.animationOrigin
                )
                rebuilt.imposedFirstExtent = split.imposedFirstExtent
                rebuilt.imposedEpoch = split.imposedEpoch
                return .split(rebuilt)
            }
        }
    }

    /// Close a pane and collapse the split
    func closePane(_ paneId: PaneID) {
        // Don't close the last pane
        guard paneStatesById.count > 1, paneStatesById[paneId] != nil else { return }
        let shouldFocusSibling = focusedPaneId == paneId || focusedPaneId == nil

        let (newRoot, siblingPaneId) = closePaneRecursively(node: rootNode, targetPaneId: paneId)

        if let newRoot {
            rootNode = newRoot
        }
        unregisterPane(paneId)

        // Only the pane that owned focus may transfer it to its sibling. Repair a
        // stale focus independently so an unrelated close cannot choose its target.
        // Closing the focused pane returns to the pane the user used last, as
        // Zellij and tmux do. The sibling that absorbs the space is only the
        // fallback for a tree whose remaining panes were never focused.
        if shouldFocusSibling {
            let remaining = rootNode.allPaneIds
            if remaining.contains(where: { focusRecency(of: $0) > 0 }) {
                focusedPaneId = mostRecentlyFocusedPane(among: remaining)
            } else {
                focusedPaneId = siblingPaneId ?? remaining.first
            }
        } else if focusedPane == nil {
            focusedPaneId = rootNode.allPaneIds.first
        }

        if let zoomedPaneId, paneStatesById[zoomedPaneId] == nil {
            self.zoomedPaneId = nil
        }
    }

    private func closePaneRecursively(
        node: SplitNode,
        targetPaneId: PaneID
    ) -> (SplitNode?, PaneID?) {
        switch node {
        case .pane(let paneState):
            if paneState.id == targetPaneId {
                return (nil, nil)
            }
            return (node, nil)

        case .split(let splitState):
            // Check if either direct child is the target
            if case .pane(let firstPane) = splitState.first, firstPane.id == targetPaneId {
                let focusTarget = splitState.second.allPaneIds.first
                return (splitState.second, focusTarget)
            }

            if case .pane(let secondPane) = splitState.second, secondPane.id == targetPaneId {
                let focusTarget = splitState.first.allPaneIds.first
                return (splitState.first, focusTarget)
            }

            // Recursively check children
            let (newFirst, focusFromFirst) = closePaneRecursively(node: splitState.first, targetPaneId: targetPaneId)
            if newFirst == nil {
                return (splitState.second, splitState.second.allPaneIds.first)
            }

            let (newSecond, focusFromSecond) = closePaneRecursively(node: splitState.second, targetPaneId: targetPaneId)
            if newSecond == nil {
                return (splitState.first, splitState.first.allPaneIds.first)
            }

            if let newFirst { splitState.first = newFirst }
            if let newSecond { splitState.second = newSecond }

            return (.split(splitState), focusFromFirst ?? focusFromSecond)
        }
    }

    // MARK: - Tab Operations

    /// Add a tab to the focused pane (or specified pane)
    func addTab(_ tab: TabItem, toPane paneId: PaneID? = nil, atIndex index: Int? = nil) {
        let targetPaneId = paneId ?? focusedPaneId
        guard let targetPaneId,
              let pane = paneStatesById[targetPaneId] else { return }

        if let index {
            pane.insertTab(tab, at: index)
        } else {
            pane.addTab(tab)
        }
        paneIdsByTabId[tab.id] = targetPaneId
    }

    /// Move a tab from one pane to another
    func moveTab(_ tab: TabItem, from sourcePaneId: PaneID, to targetPaneId: PaneID, atIndex index: Int? = nil) {
        guard let sourcePane = paneStatesById[sourcePaneId],
              let targetPane = paneStatesById[targetPaneId] else { return }

        if sourcePaneId == targetPaneId {
            guard let sourceIndex = sourcePane.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
            sourcePane.moveTab(
                from: sourceIndex,
                to: index.map { min(max(0, $0), sourcePane.tabs.count) } ?? sourcePane.tabs.count
            )
            sourcePane.selectTab(tab.id)
            focusPane(sourcePaneId)
            return
        }

        guard removeTab(tab.id, fromPane: sourcePaneId) != nil else { return }

        if let index {
            targetPane.insertTab(tab, at: index)
        } else {
            targetPane.addTab(tab)
        }
        paneIdsByTabId[tab.id] = targetPaneId

        // Focus target pane
        focusPane(targetPaneId)

        // If source pane is now empty and not the only pane, close it
        if sourcePane.tabs.isEmpty && paneStatesById.count > 1 {
            closePane(sourcePaneId)
        }
    }

    /// Remove a tab while keeping its pane in the tree.
    /// Callers that leave an empty pane decide whether to close or refill it.
    @discardableResult
    func removeTab(_ tabId: UUID, fromPane paneId: PaneID) -> TabItem? {
        guard let pane = paneStatesById[paneId],
              let removedTab = pane.removeTab(tabId) else { return nil }
        if paneIdsByTabId[tabId] == paneId {
            paneIdsByTabId.removeValue(forKey: tabId)
        }
        return removedTab
    }

    /// Close a tab in a specific pane
    func closeTab(_ tabId: UUID, inPane paneId: PaneID) {
        guard let pane = paneStatesById[paneId],
              removeTab(tabId, fromPane: paneId) != nil else { return }

        // If pane is now empty and not the only pane, close it
        if pane.tabs.isEmpty && paneStatesById.count > 1 {
            closePane(paneId)
        }
    }

    // MARK: - Keyboard Navigation

    /// Navigate focus to an adjacent pane based on spatial position
    func navigateFocus(direction: NavigationDirection) {
        guard let currentPaneId = focusedPaneId,
              let targetPaneId = adjacentPane(to: currentPaneId, direction: direction) else {
            // No neighbor found = at edge, do nothing
            return
        }
        focusPane(targetPaneId)
    }

    /// The pane that directional navigation from `paneId` reaches.
    ///
    /// Among the panes that share the requested edge, the most recently
    /// focused one wins, the rule Zellij uses. Moving right and then left
    /// therefore returns to the pane you came from, even when a column holds
    /// several panes. Panes never focused rank by edge overlap, then layout
    /// order, so a fresh layout lands on the pane most directly across.
    func adjacentPane(to paneId: PaneID, direction: NavigationDirection) -> PaneID? {
        let allPaneBounds = rootNode.computePaneBounds()
        guard let currentBounds = allPaneBounds.first(where: { $0.paneId == paneId })?.bounds else {
            return nil
        }
        let neighbors = Self.directionalNeighbors(
            from: currentBounds,
            currentPaneId: paneId,
            direction: direction,
            allPaneBounds: allPaneBounds
        )
        return neighbors.max { a, b in
            let aRecency = focusRecency(of: a.paneId)
            let bRecency = focusRecency(of: b.paneId)
            if aRecency != bRecency { return aRecency < bRecency }
            if abs(a.overlap - b.overlap) > Self.navigationEpsilon { return a.overlap < b.overlap }
            return a.layoutOrder > b.layoutOrder
        }?.paneId
    }

    private static let navigationEpsilon: CGFloat = 0.001

    private struct DirectionalNeighbor {
        let paneId: PaneID
        let overlap: CGFloat
        let layoutOrder: Int
    }

    /// Panes that touch `currentBounds` on the requested edge with a
    /// positive perpendicular overlap. A split tree tiles its rect, so any
    /// pane that is not on the outer edge has at least one.
    private static func directionalNeighbors(
        from currentBounds: CGRect,
        currentPaneId: PaneID,
        direction: NavigationDirection,
        allPaneBounds: [PaneBounds]
    ) -> [DirectionalNeighbor] {
        let epsilon = navigationEpsilon
        return allPaneBounds.enumerated().compactMap { order, candidate in
            let b = candidate.bounds
            guard candidate.paneId != currentPaneId, b.width > epsilon, b.height > epsilon else {
                return nil
            }
            let gap: CGFloat
            let overlap: CGFloat
            switch direction {
            case .left:
                gap = currentBounds.minX - b.maxX
                overlap = min(currentBounds.maxY, b.maxY) - max(currentBounds.minY, b.minY)
            case .right:
                gap = b.minX - currentBounds.maxX
                overlap = min(currentBounds.maxY, b.maxY) - max(currentBounds.minY, b.minY)
            case .up:
                gap = currentBounds.minY - b.maxY
                overlap = min(currentBounds.maxX, b.maxX) - max(currentBounds.minX, b.minX)
            case .down:
                gap = b.minY - currentBounds.maxY
                overlap = min(currentBounds.maxX, b.maxX) - max(currentBounds.minX, b.minX)
            }
            guard abs(gap) <= epsilon, overlap > epsilon else { return nil }
            return DirectionalNeighbor(paneId: candidate.paneId, overlap: overlap, layoutOrder: order)
        }
    }

    /// Create a new tab in the focused pane
    func createNewTab() {
        guard let pane = focusedPane else { return }
        let count = pane.tabs.count + 1
        let newTab = TabItem(title: "Untitled \(count)", icon: "doc")
        addTab(newTab, toPane: pane.id)
    }

    /// Close the currently selected tab in the focused pane
    func closeSelectedTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId else { return }
        closeTab(selectedTabId, inPane: pane.id)
    }

    /// Select the previous tab in the focused pane
    func selectPreviousTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex > 0 ? currentIndex - 1 : pane.tabs.count - 1
        pane.selectTab(pane.tabs[newIndex].id)
    }

    /// Select the next tab in the focused pane
    func selectNextTab() {
        guard let pane = focusedPane,
              let selectedTabId = pane.selectedTabId,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == selectedTabId }),
              !pane.tabs.isEmpty else { return }

        let newIndex = currentIndex < pane.tabs.count - 1 ? currentIndex + 1 : 0
        pane.selectTab(pane.tabs[newIndex].id)
    }

    // MARK: - Split State Access

    /// Find a split state by its UUID
    func findSplit(_ splitId: UUID) -> SplitState? {
        return findSplitRecursively(in: rootNode, id: splitId)
    }

    private func findSplitRecursively(in node: SplitNode, id: UUID) -> SplitState? {
        switch node {
        case .pane:
            return nil
        case .split(let splitState):
            if splitState.id == id {
                return splitState
            }
            if let found = findSplitRecursively(in: splitState.first, id: id) {
                return found
            }
            return findSplitRecursively(in: splitState.second, id: id)
        }
    }

    /// Get all split states in the tree
    var allSplits: [SplitState] {
        return collectSplits(from: rootNode)
    }

    private func collectSplits(from node: SplitNode) -> [SplitState] {
        switch node {
        case .pane:
            return []
        case .split(let splitState):
            return [splitState] + collectSplits(from: splitState.first) + collectSplits(from: splitState.second)
        }
    }
}
