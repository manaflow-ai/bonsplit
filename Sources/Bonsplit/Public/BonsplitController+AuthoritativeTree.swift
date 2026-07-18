import Foundation

private struct ValidatedAuthoritativeTree {
    let paneIDs: Set<PaneID>
    let paneOrder: [PaneID]
}

private struct AuthoritativeTreeValidationAccumulator {
    var paneIDs: Set<PaneID> = []
    var paneOrder: [PaneID] = []
    var splitIDs: Set<UUID> = []
    var nodeIDs: Set<UUID> = []
    var tabIDs: Set<TabID> = []
}

public extension BonsplitController {
    /// Validate an authoritative tree against the controller's exact current
    /// tab set without mutating any Bonsplit state.
    func validateAuthoritativeTree(_ tree: BonsplitAuthoritativeTree) throws {
        let currentTabs = try currentAuthoritativeTabs()
        _ = try validatedAuthoritativeTree(
            tree,
            exactTabIDs: Set(currentTabs.keys.map(TabID.init(id:)))
        )
    }

    /// Validate an authoritative tree against a caller-supplied exact tab set.
    ///
    /// This overload lets a host validate every destination tree before it
    /// transfers tabs between controllers. `applyAuthoritativeTree(_:)` still
    /// requires the destination controller to own exactly this set at apply
    /// time.
    func validateAuthoritativeTree(
        _ tree: BonsplitAuthoritativeTree,
        exactTabIDs: Set<TabID>
    ) throws {
        _ = try validatedAuthoritativeTree(tree, exactTabIDs: exactTabIDs)
    }

    /// Atomically replace the split topology using tabs already owned by this
    /// controller.
    ///
    /// Validation and construction complete before live state changes. A
    /// successful structural or presentation-state change emits exactly one
    /// geometry notification and no create, close, move, split, selection, or
    /// focus delegate callbacks. An exact no-op preserves node identity,
    /// returns `false`, and emits nothing.
    @discardableResult
    func applyAuthoritativeTree(_ tree: BonsplitAuthoritativeTree) throws -> Bool {
        let currentTabs = try currentAuthoritativeTabs()
        let validation = try validatedAuthoritativeTree(
            tree,
            exactTabIDs: Set(currentTabs.keys.map(TabID.init(id:)))
        )

        let root = buildAuthoritativeNode(tree.root, currentTabs: currentTabs)
        let focusedPaneID = resolveAuthoritativeFocus(
            tree.focusedPane,
            paneIDs: validation.paneIDs,
            firstPaneID: validation.paneOrder.first
        )
        let zoomedPaneID = resolveAuthoritativeZoom(
            tree.zoomedPane,
            paneIDs: validation.paneIDs
        )

        if sameNodeIdentity(root, internalController.rootNode),
           focusedPaneID == internalController.focusedPaneId,
           zoomedPaneID == internalController.zoomedPaneId {
            return false
        }

        internalController.installAuthoritativeTree(
            root,
            focusedPaneId: focusedPaneID,
            zoomedPaneId: zoomedPaneID
        )
        notifyGeometryChange(force: true)
        return true
    }

    private func validatedAuthoritativeTree(
        _ tree: BonsplitAuthoritativeTree,
        exactTabIDs: Set<TabID>
    ) throws -> ValidatedAuthoritativeTree {
        var accumulator = AuthoritativeTreeValidationAccumulator()
        try validateAuthoritativeNode(tree.root, accumulator: &accumulator)

        let missing = exactTabIDs.subtracting(accumulator.tabIDs).sortedByUUID
        let unexpected = accumulator.tabIDs.subtracting(exactTabIDs).sortedByUUID
        if !missing.isEmpty || !unexpected.isEmpty {
            throw BonsplitAuthoritativeTreeError.tabSetMismatch(
                missing: missing,
                unexpected: unexpected
            )
        }

        switch tree.focusedPane {
        case .preserve, .none:
            break
        case .pane(let pane) where !accumulator.paneIDs.contains(pane):
            throw BonsplitAuthoritativeTreeError.invalidFocusedPane(pane)
        case .pane:
            break
        }

        switch tree.zoomedPane {
        case .preserve, .none:
            break
        case .pane(let pane) where !accumulator.paneIDs.contains(pane):
            throw BonsplitAuthoritativeTreeError.invalidZoomedPane(pane)
        case .pane(let pane) where accumulator.paneIDs.count < 2:
            throw BonsplitAuthoritativeTreeError.zoomRequiresMultiplePanes(pane)
        case .pane:
            break
        }

        return ValidatedAuthoritativeTree(
            paneIDs: accumulator.paneIDs,
            paneOrder: accumulator.paneOrder
        )
    }

    private func validateAuthoritativeNode(
        _ node: BonsplitAuthoritativeTree.Node,
        accumulator: inout AuthoritativeTreeValidationAccumulator
    ) throws {
        switch node {
        case .pane(let pane):
            guard pane.id.id != Self.zeroAuthoritativeUUID else {
                throw BonsplitAuthoritativeTreeError.emptyPaneID
            }
            guard accumulator.paneIDs.insert(pane.id).inserted else {
                throw BonsplitAuthoritativeTreeError.duplicatePane(pane.id)
            }
            guard accumulator.nodeIDs.insert(pane.id.id).inserted else {
                throw BonsplitAuthoritativeTreeError.duplicateNodeIdentity(pane.id.id)
            }
            guard !pane.tabs.isEmpty else {
                throw BonsplitAuthoritativeTreeError.paneHasNoTabs(pane.id)
            }
            accumulator.paneOrder.append(pane.id)
            var paneTabs: Set<TabID> = []
            for tab in pane.tabs {
                guard tab.uuid != Self.zeroAuthoritativeUUID else {
                    throw BonsplitAuthoritativeTreeError.emptyTabID
                }
                guard paneTabs.insert(tab).inserted,
                      accumulator.tabIDs.insert(tab).inserted else {
                    throw BonsplitAuthoritativeTreeError.duplicateTab(tab)
                }
            }
            if case .tab(let selected) = pane.selection,
               !paneTabs.contains(selected) {
                throw BonsplitAuthoritativeTreeError.invalidSelectedTab(
                    pane: pane.id,
                    tab: selected
                )
            }

        case .split(let split):
            guard split.id != Self.zeroAuthoritativeUUID else {
                throw BonsplitAuthoritativeTreeError.emptySplitID
            }
            guard accumulator.splitIDs.insert(split.id).inserted else {
                throw BonsplitAuthoritativeTreeError.duplicateSplit(split.id)
            }
            guard accumulator.nodeIDs.insert(split.id).inserted else {
                throw BonsplitAuthoritativeTreeError.duplicateNodeIdentity(split.id)
            }
            guard split.ratio.isFinite,
                  split.ratio > 0,
                  split.ratio < 1 else {
                throw BonsplitAuthoritativeTreeError.invalidSplitRatio(
                    split: split.id,
                    ratio: split.ratio
                )
            }
            try validateAuthoritativeNode(split.first, accumulator: &accumulator)
            try validateAuthoritativeNode(split.second, accumulator: &accumulator)
        }
    }

    private func currentAuthoritativeTabs() throws -> [UUID: TabItem] {
        var tabs: [UUID: TabItem] = [:]
        for pane in internalController.rootNode.allPanes {
            for tab in pane.tabs {
                if tabs.updateValue(tab, forKey: tab.id) != nil {
                    throw BonsplitAuthoritativeTreeError.duplicateCurrentTab(TabID(id: tab.id))
                }
            }
        }
        return tabs
    }

    private func buildAuthoritativeNode(
        _ node: BonsplitAuthoritativeTree.Node,
        currentTabs: [UUID: TabItem]
    ) -> SplitNode {
        switch node {
        case .pane(let requested):
            let existing = internalController.paneState(for: requested.id)
            let tabs = requested.tabs.map { currentTabs[$0.id]! }
            let tabIDs = Set(requested.tabs.map(\.id))
            let selectedTabID: UUID
            switch requested.selection {
            case .preserve:
                selectedTabID = existing?.selectedTabId.flatMap { tabIDs.contains($0) ? $0 : nil }
                    ?? tabs[0].id
            case .tab(let selected):
                selectedTabID = selected.id
            }
            let isFullWidthTabMode: Bool
            switch requested.fullWidthTabMode {
            case .preserve:
                isFullWidthTabMode = existing?.isFullWidthTabMode ?? false
            case .value(let value):
                isFullWidthTabMode = value
            }

            if let existing,
               existing.tabs.map(\.id) == tabs.map(\.id),
               existing.selectedTabId == selectedTabID,
               existing.isFullWidthTabMode == isFullWidthTabMode {
                return .pane(existing)
            }
            return .pane(PaneState(
                id: requested.id,
                tabs: tabs,
                selectedTabId: selectedTabID,
                isFullWidthTabMode: isFullWidthTabMode
            ))

        case .split(let requested):
            let first = buildAuthoritativeNode(requested.first, currentTabs: currentTabs)
            let second = buildAuthoritativeNode(requested.second, currentTabs: currentTabs)
            if let existing = internalController.findSplit(requested.id),
               existing.orientation == requested.orientation,
               Double(existing.dividerPosition) == requested.ratio,
               sameNodeIdentity(existing.first, first),
               sameNodeIdentity(existing.second, second) {
                return .split(existing)
            }
            return .split(SplitState(
                id: requested.id,
                orientation: requested.orientation,
                first: first,
                second: second,
                dividerPosition: CGFloat(requested.ratio)
            ))
        }
    }

    private func resolveAuthoritativeFocus(
        _ reference: BonsplitAuthoritativeTree.PaneReference,
        paneIDs: Set<PaneID>,
        firstPaneID: PaneID?
    ) -> PaneID? {
        switch reference {
        case .preserve:
            if let focused = internalController.focusedPaneId,
               paneIDs.contains(focused) {
                return focused
            }
            return firstPaneID
        case .none:
            return nil
        case .pane(let pane):
            return pane
        }
    }

    private func resolveAuthoritativeZoom(
        _ reference: BonsplitAuthoritativeTree.PaneReference,
        paneIDs: Set<PaneID>
    ) -> PaneID? {
        switch reference {
        case .preserve:
            guard paneIDs.count > 1,
                  let zoomed = internalController.zoomedPaneId,
                  paneIDs.contains(zoomed) else { return nil }
            return zoomed
        case .none:
            return nil
        case .pane(let pane):
            return pane
        }
    }

    private func sameNodeIdentity(_ first: SplitNode, _ second: SplitNode) -> Bool {
        switch (first, second) {
        case (.pane(let lhs), .pane(let rhs)):
            return lhs === rhs
        case (.split(let lhs), .split(let rhs)):
            return lhs === rhs
        default:
            return false
        }
    }

    private static let zeroAuthoritativeUUID = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))
}

private extension Set where Element == TabID {
    var sortedByUUID: [TabID] {
        sorted { $0.uuid.uuidString < $1.uuid.uuidString }
    }
}
