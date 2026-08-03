import Foundation

extension SplitViewController {
    @discardableResult
    func beginTabDrag(_ tab: TabItem, from paneId: PaneID) -> Int {
#if DEBUG
        dlog("tab.dragStart pane=\(paneId.id.uuidString.prefix(5)) tab=\(tab.id.uuidString.prefix(5)) title=\"\(tab.title)\"")
#endif
        dragGeneration += 1
        draggingTab = tab
        dragSourcePaneId = paneId
        activeDragTab = tab
        activeDragSourcePaneId = paneId
        return dragGeneration
    }

    func clearTabDragState() {
        draggingTab = nil
        dragSourcePaneId = nil
        activeDragTab = nil
        activeDragSourcePaneId = nil
    }

    func cancelTabDragIfGenerationMatches(_ generation: Int) {
        guard dragGeneration == generation else { return }
        if draggingTab != nil || activeDragTab != nil {
#if DEBUG
            dlog("tab.dragCancel (stale draggingTab cleared)")
#endif
            clearTabDragState()
        }
    }

}
