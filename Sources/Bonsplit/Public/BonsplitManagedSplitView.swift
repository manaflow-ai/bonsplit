import AppKit

/// Identity of an `NSSplitView` managed by a Bonsplit split container.
///
/// Hosts that coordinate external divider drags (e.g. a two-axis corner drag
/// that moves two split views at once) resolve the owning controller and
/// split id from the AppKit view, then write positions through
/// `BonsplitController.setDividerPosition(_:forSplit:)` so the model stays
/// the source of truth and never snaps the view back.
public protocol BonsplitManagedSplitView: AnyObject {
    var bonsplitController: BonsplitController? { get }
    var bonsplitSplitId: UUID? { get }
}
