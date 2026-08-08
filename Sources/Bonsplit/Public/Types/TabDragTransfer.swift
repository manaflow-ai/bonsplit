/// Metadata carried by a live, process-local tab drag capability.
public struct TabDragTransfer: Equatable, Sendable {
    /// The dragged tab snapshot.
    public let tab: Tab

    /// The pane that owned the tab when the drag began.
    public let sourcePaneId: PaneID

    /// Creates metadata for a host or Bonsplit tab drag source.
    ///
    /// - Parameters:
    ///   - tab: The dragged tab snapshot.
    ///   - sourcePaneId: The pane that owned the tab when the drag began.
    public init(tab: Tab, sourcePaneId: PaneID) {
        self.tab = tab
        self.sourcePaneId = sourcePaneId
    }
}
