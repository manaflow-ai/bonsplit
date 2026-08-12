import AppKit
import SwiftUI

/// Applies tab-strip drops through the controller's shared tab mutation APIs.
@MainActor
struct TabBarDropHandler {
    static let tabTransferPasteboardType = TabDragTransferRegistry.pasteboardType

    let pane: PaneState
    let bonsplitController: BonsplitController
    let splitViewController: SplitViewController

    var hasLiveTabDrag: Bool {
        splitViewController.tabDragSession != nil
    }

    func operation(for pasteboard: NSPasteboard) -> NSDragOperation {
        guard splitViewController.isInteractive else { return [] }

        let types = pasteboard.types ?? []
        let hasTabTransfer = types.contains(Self.tabTransferPasteboardType)
        let hasFileURL = types.contains(.fileURL)

        // A file-only pasteboard is authoritative even if a cancelled local tab
        // drag has not finished clearing its in-memory state.
        if hasFileURL, !hasTabTransfer {
            guard bonsplitController.onExternalFileDrop != nil || splitViewController.onFileDrop != nil,
                  UnifiedPaneDropDelegate.hasReadableFileURLs(from: pasteboard) else {
                return []
            }
            return .copy
        }

        // Item-provider publication can trail the start of a local SwiftUI drag.
        // The controller's synchronous drag state is authoritative in that window.
        if let sourcePaneId = liveDragSourcePaneId {
            return permitsTabMove(from: sourcePaneId) ? .move : []
        }

        if hasTabTransfer {
            guard let transfer = splitViewController.tabDragTransferRegistry.resolve(from: pasteboard) else {
                return []
            }
            let sourcePaneId = transfer.sourcePaneId
            guard sourcePaneId != pane.id,
                  bonsplitController.configuration.allowCrossPaneTabMove,
                  bonsplitController.onExternalTabDrop != nil else {
                return []
            }
            return .move
        }

        return []
    }

    func indicatorIndex(for targetIndex: Int) -> Int? {
        guard let sourceIndex = liveSamePaneSourceIndex else { return targetIndex }
        return Self.isNoopSamePaneTarget(sourceIndex: sourceIndex, targetIndex: targetIndex)
            ? nil
            : targetIndex
    }

    func performDrop(from pasteboard: NSPasteboard, at targetIndex: Int) -> Bool {
        guard operation(for: pasteboard) != [] else { return false }
        let hasTabTransfer = pasteboard.types?.contains(Self.tabTransferPasteboardType) == true
        let hasFileURL = pasteboard.types?.contains(.fileURL) == true

        if hasFileURL, !hasTabTransfer {
            return performFileDrop(from: pasteboard, at: targetIndex)
        }
        if hasLiveTabDrag || hasTabTransfer {
            let handled = performTabDrop(from: pasteboard, at: targetIndex)
            if handled {
                splitViewController.tabDragTransferRegistry.finish(from: pasteboard)
            }
            return handled
        }
        return false
    }

    static func isNoopSamePaneTarget(sourceIndex: Int, targetIndex: Int) -> Bool {
        // Insertion indices use the original array's coordinates. Removing the source
        // makes its own slot and the slot immediately after it equivalent no-ops.
        targetIndex == sourceIndex || targetIndex == sourceIndex + 1
    }

    private static func externalFallbackRequest(
        transfer: TabDragTransfer,
        targetPane: PaneID,
        targetIndex: Int,
        allowCrossPaneTabMove: Bool
    ) -> BonsplitController.ExternalTabDropRequest? {
        let sourcePaneId = transfer.sourcePaneId
        guard sourcePaneId != targetPane, allowCrossPaneTabMove else { return nil }
        return BonsplitController.ExternalTabDropRequest(
            tabId: transfer.tab.id,
            sourcePaneId: sourcePaneId,
            destination: .insert(targetPane: targetPane, targetIndex: targetIndex)
        )
    }

    private var liveDragSourcePaneId: PaneID? {
        splitViewController.tabDragSession?.sourcePaneId
    }

    private var liveSamePaneSourceIndex: Int? {
        guard let dragSession = splitViewController.tabDragSession,
              dragSession.sourcePaneId == pane.id else {
            return nil
        }
        return pane.tabs.firstIndex(where: { $0.id == dragSession.tab.id })
    }

    private func permitsTabMove(from sourcePaneId: PaneID) -> Bool {
        sourcePaneId == pane.id
            ? bonsplitController.configuration.allowTabReordering
            : bonsplitController.configuration.allowCrossPaneTabMove
    }

    private func performTabDrop(from pasteboard: NSPasteboard, at targetIndex: Int) -> Bool {
        if let dragSession = splitViewController.tabDragSession {
            defer { splitViewController.clearTabDragState() }

            let draggedTab = dragSession.tab
            let sourcePaneId = dragSession.sourcePaneId
            if sourcePaneId == pane.id,
               let sourceIndex = pane.tabs.firstIndex(where: { $0.id == draggedTab.id }),
               Self.isNoopSamePaneTarget(sourceIndex: sourceIndex, targetIndex: targetIndex) {
                return true
            }

            var handled = false
            withTransaction(Transaction(animation: nil)) {
                if sourcePaneId == pane.id {
                    handled = bonsplitController.reorderTab(TabID(id: draggedTab.id), toIndex: targetIndex)
                } else {
                    handled = bonsplitController.moveTab(
                        TabID(id: draggedTab.id),
                        toPane: pane.id,
                        atIndex: targetIndex
                    )
                }
            }
            return handled
        }

        guard let transfer = splitViewController.tabDragTransferRegistry.resolve(from: pasteboard),
              let request = Self.externalFallbackRequest(
                  transfer: transfer,
                  targetPane: pane.id,
                  targetIndex: targetIndex,
                  allowCrossPaneTabMove: bonsplitController.configuration.allowCrossPaneTabMove
              ) else {
            return false
        }
        let handled = bonsplitController.onExternalTabDrop?(request) ?? false
        if handled {
            splitViewController.clearTabDragState()
        }
        return handled
    }

    private func performFileDrop(from pasteboard: NSPasteboard, at targetIndex: Int) -> Bool {
        let urls = UnifiedPaneDropDelegate.fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }

        let destination: BonsplitController.ExternalTabDropRequest.Destination = .insert(
            targetPane: pane.id,
            targetIndex: targetIndex
        )
        if let handler = bonsplitController.onExternalFileDrop {
            return handler(BonsplitController.ExternalFileDropRequest(urls: urls, destination: destination))
        }
        return splitViewController.onFileDrop?(urls, pane.id) ?? false
    }

}
