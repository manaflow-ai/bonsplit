import AppKit

/// AppKit bridge that keeps one authoritative pointer-to-index calculation per strip.
@MainActor
final class TabBarDropDestinationNSView: NSView {
    weak var pane: PaneState?
    weak var bonsplitController: BonsplitController?
    weak var splitViewController: SplitViewController?
    weak var geometryRegistry: TabBarItemGeometryRegistry?
    var onIndicatorIndexChanged: ((Int?) -> Void)?

    private let dropIndexResolver: TabDropIndexResolver
    private var presentedIndicatorIndex: Int?

    override init(frame frameRect: NSRect) {
        dropIndexResolver = TabDropIndexResolver()
        super.init(frame: frameRect)
        registerForDraggedTypes([
            TabBarDropHandler.tabTransferPasteboardType,
            .fileURL,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) === self else { return nil }
        let dragPasteboard = NSPasteboard(name: .drag)
        let handler = makeHandler()
        guard Self.shouldCaptureHitTest(
            eventType: NSApp.currentEvent?.type,
            pasteboardTypes: dragPasteboard.types,
            hasLocalTabDrag: handler?.hasLiveTabDrag == true
        ), handler?.operation(for: dragPasteboard) != [] else {
            return nil
        }
        return self
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        clearDropState()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        updateDrag(sender) != []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { clearDropState() }
        guard let handler = makeHandler(),
              let targetIndex = insertionIndex(for: sender) else {
            return false
        }
        return handler.performDrop(from: sender.draggingPasteboard, at: targetIndex)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        clearDropState()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        clearDropState()
    }

    static func shouldCaptureHitTest(
        eventType: NSEvent.EventType?,
        pasteboardTypes: [NSPasteboard.PasteboardType]?,
        hasLocalTabDrag: Bool = false
    ) -> Bool {
        let hasSupportedPasteboardType = pasteboardTypes?.contains(
            TabBarDropHandler.tabTransferPasteboardType
        ) == true || pasteboardTypes?.contains(.fileURL) == true
        guard hasLocalTabDrag || hasSupportedPasteboardType else {
            return false
        }
        guard let eventType else { return true }
        switch eventType {
        case .leftMouseUp:
            // The drag pasteboard retains types after a drag ends. A normal click's
            // mouse-up may only be captured while the controller owns a live session.
            return hasLocalTabDrag
        case .leftMouseDragged,
             .mouseMoved,
             .cursorUpdate,
             .periodic,
             .appKitDefined,
             .applicationDefined,
             .systemDefined:
            return true
        default:
            return false
        }
    }

    private func updateDrag(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let handler = makeHandler(),
              let targetIndex = insertionIndex(for: sender) else {
            clearDropState()
            return []
        }
        let operation = handler.operation(for: sender.draggingPasteboard)
        guard operation != [] else {
            clearDropState()
            return []
        }
        presentIndicator(at: handler.indicatorIndex(for: targetIndex))
        return operation
    }

    private func insertionIndex(for sender: any NSDraggingInfo) -> Int? {
        guard let pane, let geometryRegistry else { return nil }
        let indexedFrames = pane.tabs.enumerated().compactMap { index, tab -> TabDropIndexResolver.IndexedFrame? in
            guard let frame = geometryRegistry.frame(for: tab.id, in: self) else { return nil }
            return TabDropIndexResolver.IndexedFrame(index: index, frame: frame)
        }
        return dropIndexResolver.insertionIndex(
            at: convert(sender.draggingLocation, from: nil),
            in: bounds,
            indexedTabFrames: indexedFrames,
            tabCount: pane.tabs.count
        )
    }

    private func makeHandler() -> TabBarDropHandler? {
        guard let pane, let bonsplitController, let splitViewController else { return nil }
        return TabBarDropHandler(
            pane: pane,
            bonsplitController: bonsplitController,
            splitViewController: splitViewController
        )
    }

    private func presentIndicator(at index: Int?) {
        guard presentedIndicatorIndex != index else { return }
        presentedIndicatorIndex = index
        onIndicatorIndexChanged?(index)
    }

    private func clearDropState() {
        presentIndicator(at: nil)
    }
}
