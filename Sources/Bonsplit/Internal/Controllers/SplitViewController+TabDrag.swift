import AppKit
import Foundation
import UniformTypeIdentifiers

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

    func makeTabDragItemProvider(
        for tab: TabItem,
        from paneId: PaneID,
        clearDropState: () -> Void
    ) -> NSItemProvider {
#if DEBUG
        NSLog("[Bonsplit Drag] createItemProvider for tab: \(tab.title)")
#endif
        clearDropState()
        let dragGeneration = beginTabDrag(tab, from: paneId)
        installCancelledTabDragCleanup(forGeneration: dragGeneration)

        let transfer = TabTransferData(tab: tab, sourcePaneId: paneId.id)
        if let data = try? JSONEncoder().encode(transfer) {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.tabTransfer.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(data, nil)
                return nil
            }
#if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                let types = NSPasteboard(name: .drag).types?.map(\.rawValue).joined(separator: ",") ?? "-"
                dlog("tab.dragPasteboard types=\(types)")
            }
#endif
            return provider
        }
        return NSItemProvider()
    }

    private func installCancelledTabDragCleanup(forGeneration generation: Int) {
        var monitorRef: Any?
        monitorRef = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            // One-shot: remove ourselves AND nil the capture box, or the cycle
            // monitor -> closure -> box -> monitor leaks one monitor per drag.
            if let m = monitorRef {
                NSEvent.removeMonitor(m)
                monitorRef = nil
            }
            DispatchQueue.main.async {
                self?.cancelTabDragIfGenerationMatches(generation)
            }
            return event
        }
    }
}
