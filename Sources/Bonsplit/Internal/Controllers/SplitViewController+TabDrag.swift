import AppKit
import Foundation
import UniformTypeIdentifiers

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
        pasteboardItem: NSPasteboardItem,
        sourceView: NSView,
        event: NSEvent,
        draggingFrame: NSRect,
        dragImage: NSImage
    ) -> Bool {
#if DEBUG
        NSLog("[Bonsplit Drag] begin native session for tab: \(tab.title)")
#endif
        let generation = beginTabDrag(tab, from: paneId)
        let source = TabDragSessionSource(generation: generation, controller: self)
        nativeTabDragSources[generation] = source

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(draggingFrame, contents: dragImage)
        sourceView.beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: source
        )
        return true
    }

    func makeTabDragPasteboardItem(for tab: TabItem, from paneId: PaneID) -> NSPasteboardItem? {
        let transfer = TabTransferData(tab: tab, sourcePaneId: paneId.id)
        guard let data = try? JSONEncoder().encode(transfer) else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: NSPasteboard.PasteboardType(UTType.tabTransfer.identifier))
        return item
    }

    func nativeTabDragSessionDidEnd(generation: Int) {
        nativeTabDragSources[generation] = nil
        cancelTabDragIfGenerationMatches(generation)
    }
}
