import Foundation

/// A complete, host-owned split-tree description.
///
/// Applying this value only rearranges tabs that already exist in the
/// controller. Tab metadata remains owned by Bonsplit and is preserved across
/// the replacement. Presentation-local state defaults to `.preserve` so a
/// canonical topology update does not unexpectedly change the user's focus,
/// selection, zoom, or full-width-tab mode.
public struct BonsplitAuthoritativeTree: Sendable, Equatable {
    public let root: Node
    public let focusedPane: PaneReference
    public let zoomedPane: PaneReference

    public init(
        root: Node,
        focusedPane: PaneReference = .preserve,
        zoomedPane: PaneReference = .preserve
    ) {
        self.root = root
        self.focusedPane = focusedPane
        self.zoomedPane = zoomedPane
    }

    /// One node in the authoritative binary split tree.
    public indirect enum Node: Sendable, Equatable {
        case pane(Pane)
        case split(Split)
    }

    /// A pane and the exact order of the tabs it owns.
    public struct Pane: Sendable, Equatable {
        public let id: PaneID
        public let tabs: [TabID]
        public let selection: TabSelection
        public let fullWidthTabMode: BooleanState

        public init(
            id: PaneID,
            tabs: [TabID],
            selection: TabSelection = .preserve,
            fullWidthTabMode: BooleanState = .preserve
        ) {
            self.id = id
            self.tabs = tabs
            self.selection = selection
            self.fullWidthTabMode = fullWidthTabMode
        }
    }

    /// A branch in the authoritative binary split tree.
    public struct Split: Sendable, Equatable {
        public let id: UUID
        public let orientation: SplitOrientation
        public let ratio: Double
        public let first: Node
        public let second: Node

        public init(
            id: UUID,
            orientation: SplitOrientation,
            ratio: Double,
            first: Node,
            second: Node
        ) {
            self.id = id
            self.orientation = orientation
            self.ratio = ratio
            self.first = first
            self.second = second
        }
    }

    /// How an authoritative apply resolves a pane reference.
    public enum PaneReference: Sendable, Equatable {
        /// Keep the current reference when that pane survives. Focus falls
        /// back to the first pane; zoom clears when its pane disappears.
        case preserve
        /// Clear the reference.
        case none
        /// Set the reference to a pane in the new tree.
        case pane(PaneID)
    }

    /// How an authoritative apply resolves one pane's selected tab.
    public enum TabSelection: Sendable, Equatable {
        /// Keep the current selection when that tab remains in this pane,
        /// otherwise select the pane's first tab.
        case preserve
        /// Select a tab that belongs to this pane in the new tree.
        case tab(TabID)
    }

    /// How an authoritative apply resolves one pane's Boolean view state.
    public enum BooleanState: Sendable, Equatable {
        case preserve
        case value(Bool)
    }
}

/// Validation failures produced before an authoritative tree can mutate a
/// controller. Every failure leaves the existing tree and presentation state
/// untouched.
public enum BonsplitAuthoritativeTreeError: Error, Sendable, Equatable {
    case emptyPaneID
    case emptySplitID
    case emptyTabID
    case paneHasNoTabs(PaneID)
    case duplicatePane(PaneID)
    case duplicateSplit(UUID)
    case duplicateTab(TabID)
    case duplicateCurrentTab(TabID)
    case duplicateNodeIdentity(UUID)
    case invalidSplitRatio(split: UUID, ratio: Double)
    case invalidSelectedTab(pane: PaneID, tab: TabID)
    case invalidFocusedPane(PaneID)
    case invalidZoomedPane(PaneID)
    case zoomRequiresMultiplePanes(PaneID)
    case tabSetMismatch(missing: [TabID], unexpected: [TabID])
}

extension BonsplitAuthoritativeTreeError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyPaneID:
            return "authoritative pane IDs must be nonzero"
        case .emptySplitID:
            return "authoritative split IDs must be nonzero"
        case .emptyTabID:
            return "authoritative tab IDs must be nonzero"
        case .paneHasNoTabs(let pane):
            return "authoritative pane \(pane) has no tabs"
        case .duplicatePane(let pane):
            return "authoritative pane \(pane) appears more than once"
        case .duplicateSplit(let split):
            return "authoritative split \(split) appears more than once"
        case .duplicateTab(let tab):
            return "authoritative tab \(tab.uuid) appears more than once"
        case .duplicateCurrentTab(let tab):
            return "current tab \(tab.uuid) appears more than once"
        case .duplicateNodeIdentity(let id):
            return "authoritative pane and split share node identity \(id)"
        case .invalidSplitRatio(let split, let ratio):
            return "authoritative split \(split) has invalid ratio \(ratio)"
        case .invalidSelectedTab(let pane, let tab):
            return "authoritative selected tab \(tab.uuid) is outside pane \(pane)"
        case .invalidFocusedPane(let pane):
            return "authoritative focused pane \(pane) is absent"
        case .invalidZoomedPane(let pane):
            return "authoritative zoomed pane \(pane) is absent"
        case .zoomRequiresMultiplePanes(let pane):
            return "authoritative zoomed pane \(pane) requires a multi-pane tree"
        case .tabSetMismatch(let missing, let unexpected):
            let missingIDs = missing.map { $0.uuid.uuidString }.joined(separator: ",")
            let unexpectedIDs = unexpected.map { $0.uuid.uuidString }.joined(separator: ",")
            return "authoritative tab set mismatch (missing: [\(missingIDs)], unexpected: [\(unexpectedIDs)])"
        }
    }
}
