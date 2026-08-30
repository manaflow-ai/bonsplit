import AppKit
import Foundation

extension SplitViewController {
    @discardableResult
    func beginTabDrag(_ tab: TabItem, from paneId: PaneID) -> Int {
#if DEBUG
        dlog("tab.dragStart pane=\(paneId.id.uuidString.prefix(5)) tab=\(tab.id.uuidString.prefix(5)) title=\"\(tab.title)\"")
#endif
        clearTabDragState()
        dragGeneration += 1
        let session = TabDragSession(tab: tab, sourcePaneId: paneId, generation: dragGeneration)
        tabDragSession = session
        return dragGeneration
    }

    func clearTabDragState() {
        tabDragSession = nil
    }

    func cancelTabDragIfGenerationMatches(_ generation: Int) {
        guard tabDragSession?.generation == generation else { return }
#if DEBUG
        dlog("tab.dragCancel (stale tabDragSession cleared)")
#endif
        clearTabDragState()
    }

    @discardableResult
    func beginNativeTabDrag(
        _ tab: TabItem,
        from paneId: PaneID,
        sourceView: NSView,
        event: NSEvent,
        draggingFrame: NSRect,
        dragImage: NSImage
    ) -> Bool {
#if DEBUG
        NSLog("[Bonsplit Drag] begin native session for tab: \(tab.title)")
#endif
        let transfer = TabDragTransfer(tab: Tab(from: tab), sourcePaneId: paneId)
        guard let registration = tabDragTransferRegistry.register(transfer) else {
            return false
        }
        let generation = beginTabDrag(tab, from: paneId)
        let source = TabDragSessionSource(
            generation: generation,
            transferRegistration: registration,
            transferRegistry: tabDragTransferRegistry,
            controller: self
        )
        nativeTabDragSources[generation] = source

        let draggingItem = NSDraggingItem(pasteboardWriter: registration.pasteboardItem)
        draggingItem.setDraggingFrame(draggingFrame, contents: dragImage)
        let session = sourceView.beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: source
        )
        source.bind(sourceView: sourceView)
        // A tab drag is owned by the source lifecycle. Avoid AppKit's return
        // animation delaying (or suppressing) `endedAt` when the pointer is
        // released without a valid destination, so transfer state is revoked
        // immediately and the next tab press can arm normally.
        session.animatesToStartingPositionsOnCancelOrFail = false
        return true
    }

    func nativeTabDragSessionDidEnd(generation: Int) {
        nativeTabDragSources[generation] = nil
        cancelTabDragIfGenerationMatches(generation)
    }
}
