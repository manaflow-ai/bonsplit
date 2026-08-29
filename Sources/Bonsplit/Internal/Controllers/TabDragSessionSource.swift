import AppKit

/// Retained AppKit source whose terminal callback owns tab-drag cancellation.
@MainActor
final class TabDragSessionSource: NSObject, NSDraggingSource {
    private let generation: Int
    private let transferRegistration: TabDragTransferRegistration
    private let transferRegistry: TabDragTransferRegistry
    private weak var controller: SplitViewController?
    private var didFinish = false
    // Keep the exact AppKit session and source view owned until `endedAt`.
    // AppKit's drag manager may outlive the SwiftUI tab view that initiated the
    // drag; releasing either object during an accepted drop can strand the
    // WindowManager drag connection.
    private var nativeSession: NSDraggingSession?
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

    func bind(nativeSession: NSDraggingSession, sourceView: NSView) {
        guard !didFinish else { return }
        self.nativeSession = nativeSession
        self.sourceView = sourceView
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
        nativeSession = nil
        sourceView = nil
    }
}
