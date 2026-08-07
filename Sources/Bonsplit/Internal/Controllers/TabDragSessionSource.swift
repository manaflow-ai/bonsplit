import AppKit

/// Retained AppKit source whose terminal callback owns tab-drag cancellation.
@MainActor
final class TabDragSessionSource: NSObject, NSDraggingSource {
    private let generation: Int
    private let transferToken: UUID
    private let transferRegistry: TabDragTransferRegistry
    private weak var controller: SplitViewController?

    init(
        generation: Int,
        transferToken: UUID,
        transferRegistry: TabDragTransferRegistry,
        controller: SplitViewController
    ) {
        self.generation = generation
        self.transferToken = transferToken
        self.transferRegistry = transferRegistry
        self.controller = controller
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        finishDrag()
    }

    func finishDrag() {
        transferRegistry.end(token: transferToken)
        controller?.nativeTabDragSessionDidEnd(generation: generation)
    }
}
