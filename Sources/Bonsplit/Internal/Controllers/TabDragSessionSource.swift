import AppKit

/// Retained AppKit source whose terminal callback owns tab-drag cancellation.
@MainActor
final class TabDragSessionSource: NSObject, NSDraggingSource {
    private let generation: Int
    private let transferRegistration: TabDragTransferRegistration
    private let transferRegistry: TabDragTransferRegistry
    private weak var controller: SplitViewController?
    private var didFinish = false
    // Keep the source view owned until `endedAt`; AppKit owns the session and
    // retains this source while its native drag is active.
    // AppKit's drag manager may outlive the SwiftUI tab view that initiated the
    // drag; releasing either object during an accepted drop can strand the
    // WindowManager drag connection.
    private var sourceView: NSView?

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
    }

    /// Retains the source view until AppKit delivers this source's `endedAt` callback.
    func bind(sourceView: NSView) {
        guard !didFinish else { return }
        self.sourceView = sourceView
    }

    /// Completes a superseded source after a later native pointer boundary
    /// proves that AppKit has left this source's drag loop.
    func finishAfterNativeBoundary() {
        finishDrag()
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
        // The system drag pasteboard advertises this session's transfer type
        // until another drag replaces it, which keeps host drop-capture
        // hit-testing armed forever and blocks the next tab drag from starting.
        transferRegistration.clearResidualCapability(from: session.draggingPasteboard)
    }

    func finishDrag() {
        guard !didFinish else { return }
        didFinish = true
        transferRegistry.end(transferRegistration)
        controller?.nativeTabDragSessionDidEnd(generation: generation)
        sourceView = nil
    }
}
