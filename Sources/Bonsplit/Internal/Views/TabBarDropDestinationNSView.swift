import AppKit

/// AppKit bridge that keeps one authoritative pointer-to-index calculation per strip.
@MainActor
final class TabBarDropDestinationNSView: NSView {
    weak var pane: PaneState?
    weak var bonsplitController: BonsplitController?
    weak var splitViewController: SplitViewController?
    weak var geometryRegistry: TabBarItemGeometryRegistry?
    var onIndicatorIndexChanged: ((Int?) -> Void)?
    /// Whether a drop lands at once instead of settling (tests set it).
    var reducesMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

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
        // Read from the strip before the move reflows it.
        let before = settleSnapshot(for: sender)
        guard handler.performDrop(from: sender.draggingPasteboard, at: targetIndex) else { return false }
        if let before, let slot = settleSlot(after: before) {
            // AppKit slides the drag image into the slot; the tab shows there
            // when the session ends (SplitViewController.beginTabSettle).
            sender.animatesToDestination = true
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                item.draggingFrame = slot
            }
            splitViewController?.beginTabSettle(before.tabId)
        }
        return true
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        clearDropState()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        clearDropState()
    }

    /// The strip as a drop found it: the dragged tab, where it was, its
    /// width, and every tab's frame and on-screen part here.
    private struct SettleSnapshot {
        let tabId: UUID
        let source: Int
        let width: CGFloat
        let frames: [CGRect?]
        let visible: [CGRect?]
        /// The strip's viewport outside the trailing button lane, where the
        /// unpinned tabs scroll (pinned tabs sit before it, always shown).
        let viewport: CGRect?
        let pinned: [Bool]
    }

    /// Nil when the drop lands at once: Reduce Motion, not a tab dragged
    /// within this strip (a tab from another pane changes the layout it
    /// lands in: its pane may close, fill-width tabs narrow), a strip whose
    /// tabs have no frames.
    private func settleSnapshot(for sender: any NSDraggingInfo) -> SettleSnapshot? {
        guard !reducesMotion(), let pane, let geometryRegistry,
              sender.draggingPasteboard.types?.contains(TabBarDropHandler.tabTransferPasteboardType) == true,
              let session = splitViewController?.tabDragSession, session.sourcePaneId == pane.id,
              let source = pane.tabs.firstIndex(where: { $0.id == session.tab.id }) else { return nil }
        let ids = pane.tabs.map(\.id)
        let frames = ids.map { geometryRegistry.frame(for: $0, in: self) }
        let visible = geometryRegistry.visibleFrames(for: ids, in: self)
        guard let width = frames[source]?.width, width > 0 else { return nil }
        return SettleSnapshot(tabId: session.tab.id, source: source, width: width, frames: frames,
                              visible: ids.map { visible[$0] },
                              viewport: geometryRegistry.unobscuredViewport(in: self),
                              pinned: pane.tabs.map(\.isPinned))
    }

    /// The slot, in this view, of the tab's place after the drop (as the
    /// pane placed it, pinned tabs first), measured on the strip before the
    /// drop. Nil unless every tab it passes is fully on screen, outside the
    /// trailing button lane: a slot partly hidden makes the strip scroll.
    private func settleSlot(after before: SettleSnapshot) -> NSRect? {
        guard let pane, let landed = pane.tabs.firstIndex(where: { $0.id == before.tabId }) else { return nil }
        let span = min(landed, before.source)...max(landed, before.source)
        for index in span {
            guard let frame = before.frames[index], let shown = before.visible[index],
                  abs(shown.width - frame.width) < 0.5,
                  before.pinned[index]
                      || before.viewport.map({ frame.minX >= $0.minX - 0.5 && frame.maxX <= $0.maxX + 0.5 }) ?? true
            else { return nil }
        }
        guard let row = before.frames[landed] else { return nil }
        // Moving right, the tabs between move left by its width.
        let minX = landed > before.source ? row.maxX - before.width : row.minX
        return NSRect(x: minX, y: row.minY, width: before.width, height: row.height)
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
        // NSPasteboard(name: .drag) retains its advertised types after a drag
        // ends. A passive hit test must therefore be owned by the live local
        // tab-drag session; otherwise stale file/tab types can cover the tab
        // hit regions and swallow ordinary hover/cursor events.
        guard let eventType else { return hasLocalTabDrag }
        switch eventType {
        case .leftMouseDragged:
            // External Finder and cross-process tab drags arrive through the
            // AppKit drag event even though they have no local tab state.
            return true
        case .leftMouseUp,
             .mouseMoved,
             .cursorUpdate,
             .periodic,
             .appKitDefined,
             .applicationDefined,
             .systemDefined:
            return hasLocalTabDrag
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
