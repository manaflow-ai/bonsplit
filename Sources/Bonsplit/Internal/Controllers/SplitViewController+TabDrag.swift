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
        let monitor = TabDragLifecycleMonitor(generation: session.generation) { [weak self] generation in
            self?.cancelTabDragIfGenerationMatches(generation)
        }
        tabDragLifecycleMonitor = monitor
        monitor.start()
        return dragGeneration
    }

    func clearTabDragState() {
        tabDragLifecycleMonitor?.stop()
        tabDragLifecycleMonitor = nil
        tabDragSession = nil
    }

    func cancelTabDragIfGenerationMatches(_ generation: Int) {
        guard tabDragSession?.generation == generation else { return }
#if DEBUG
        dlog("tab.dragCancel (stale tabDragSession cleared)")
#endif
        clearTabDragState()
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
        _ = beginTabDrag(tab, from: paneId)

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

}
