/// The single in-memory identity of a tab drag owned by a split controller.
/// Keeping the tab, source pane, and generation together prevents observable
/// and drop-routing state from getting out of phase.
struct TabDragSession {
    let tab: TabItem
    let sourcePaneId: PaneID
    let generation: Int
}
