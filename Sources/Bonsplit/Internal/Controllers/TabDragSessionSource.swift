import AppKit

/// Retained AppKit source whose terminal callback owns tab-drag cancellation.
@MainActor
final class TabDragSessionSource: NSObject, NSDraggingSource {
    private let generation: Int
    private let transferRegistration: TabDragTransferRegistration
    private let transferRegistry: TabDragTransferRegistry
    private weak var controller: SplitViewController?
    private var didFinish = false

    init(
        generation: Int,
        transferRegistration: TabDragTransferRegistration,
        transferRegistry: TabDragTransferRegistry,
        controller: SplitViewController
    ) {
        self.generation = generation
        self.transferRegistration = transferRegistration
        self.transferRegistry = transferRegistry
        self.controller = controller
        super.init()
        transferRegistry.attachSourceCompletion(to: transferRegistration) { [weak self] in
            self?.finishDrag()
        }
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
        guard !didFinish else { return }
        didFinish = true
        transferRegistry.end(transferRegistration)
        controller?.nativeTabDragSessionDidEnd(generation: generation)
    }
}
