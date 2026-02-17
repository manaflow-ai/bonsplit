import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Tab bar view with scrollable tabs, drag/drop support, and split buttons
struct TabBarView: View {
    @Environment(BonsplitController.self) private var controller
    @Environment(SplitViewController.self) private var splitViewController
    
    @Bindable var pane: PaneState
    let isFocused: Bool
    var showSplitButtons: Bool = true

    @State private var dropTargetIndex: Int?
    @State private var dropLifecycle: TabDropLifecycle = .idle
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @StateObject private var controlKeyMonitor = TabControlShortcutKeyMonitor()

    private var canScrollLeft: Bool {
        scrollOffset > 1
    }

    private var canScrollRight: Bool {
        contentWidth > containerWidth && scrollOffset < contentWidth - containerWidth - 1
    }

    /// Whether this tab bar should show full saturation (focused or drag source)
    private var shouldShowFullSaturation: Bool {
        isFocused || splitViewController.dragSourcePaneId == pane.id
    }

    private var tabBarSaturation: Double {
        shouldShowFullSaturation ? 1.0 : 0.0
    }

    private var showsControlShortcutHints: Bool {
        isFocused && controlKeyMonitor.isShortcutHintVisible
    }

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tabs with fade overlays
            GeometryReader { containerGeo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TabBarMetrics.tabSpacing) {
                            ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { index, tab in
                                tabItem(for: tab, at: index)
                                    .id(tab.id)
                            }

                            // Unified drop zone after the last tab. This is at least a small hit
                            // target (so the user can always drop "after the last tab") and it
                            // supports dropping after the last tab.
                            dropZoneAfterTabs
                        }
                        .padding(.horizontal, TabBarMetrics.barPadding)
                        // Keep tab insert/remove/reorder instant without suppressing unrelated
                        // subtree animations (for example, shortcut-hint fades).
                        .animation(nil, value: pane.tabs.map(\.id))
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear
                                    .onChange(of: contentGeo.frame(in: .named("tabScroll"))) { _, newFrame in
                                        scrollOffset = -newFrame.minX
                                        contentWidth = newFrame.width
                                    }
                                    .onAppear {
                                        let frame = contentGeo.frame(in: .named("tabScroll"))
                                        scrollOffset = -frame.minX
                                        contentWidth = frame.width
                                    }
                            }
                        )
                    }
                    // When the tab strip is shorter than the visible area, allow dropping in the
                    // empty trailing space without forcing tabs to stretch.
                    .overlay(alignment: .trailing) {
                        let trailing = max(0, containerGeo.size.width - contentWidth)
                        if trailing >= 1 {
                            Color.clear
                                .frame(width: trailing, height: TabBarMetrics.tabHeight)
                                .contentShape(Rectangle())
                                .onDrop(of: [.text], delegate: TabDropDelegate(
                                    targetIndex: pane.tabs.count,
                                    pane: pane,
                                    controller: splitViewController,
                                    dropTargetIndex: $dropTargetIndex,
                                    dropLifecycle: $dropLifecycle
                                ))
                        }
                    }
                    .coordinateSpace(name: "tabScroll")
                    .onAppear {
                        containerWidth = containerGeo.size.width
                        if let tabId = pane.selectedTabId {
                            proxy.scrollTo(tabId, anchor: .center)
                        }
                    }
                    .onChange(of: containerGeo.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
                    .onChange(of: pane.selectedTabId) { _, newTabId in
                        if let tabId = newTabId {
                            // Keep tab selection changes instant; scrolling to the focused tab should
                            // not animate (avoids feeling like tabs "linger" during drag/drop).
                            withTransaction(Transaction(animation: nil)) {
                                proxy.scrollTo(tabId, anchor: .center)
                            }
                        }
                    }
                }
                .frame(height: TabBarMetrics.barHeight)
                .overlay(fadeOverlays)
            }

            // Split buttons
            if showSplitButtons {
                splitButtons
                    .saturation(tabBarSaturation)
            }
        }
        .frame(height: TabBarMetrics.barHeight)
        .contentShape(Rectangle())
        .background(tabBarBackground)
        // Clear drop state when drag ends elsewhere (cancelled, dropped in another pane, etc.)
        .onChange(of: splitViewController.draggingTab) { _, newValue in
            if newValue == nil {
                dropTargetIndex = nil
                dropLifecycle = .idle
            }
        }
        .onAppear {
            controlKeyMonitor.start()
        }
        .onDisappear {
            controlKeyMonitor.stop()
        }
    }

    // MARK: - Tab Item

    @ViewBuilder
    private func tabItem(for tab: TabItem, at index: Int) -> some View {
        TabItemView(
            tab: tab,
            isSelected: pane.selectedTabId == tab.id,
            saturation: tabBarSaturation,
            controlShortcutDigit: tabControlShortcutDigit(for: index, tabCount: pane.tabs.count),
            showsControlShortcutHint: showsControlShortcutHints,
            shortcutModifierSymbol: controlKeyMonitor.shortcutModifierSymbol,
            onSelect: {
                // Tab selection must be instant. Animating this transaction causes the pane
                // content (often swapped via opacity) to crossfade, which is undesirable for
                // terminal/browser surfaces.
#if DEBUG
                dlog("tab.select pane=\(pane.id.id.uuidString.prefix(5)) tab=\(tab.id.uuidString.prefix(5)) title=\"\(tab.title)\"")
#endif
                withTransaction(Transaction(animation: nil)) {
                    pane.selectTab(tab.id)
                    controller.focusPane(pane.id)
                }
            },
            onClose: {
                // Close should be instant (no fade-out/removal animation).
#if DEBUG
                dlog("tab.close pane=\(pane.id.id.uuidString.prefix(5)) tab=\(tab.id.uuidString.prefix(5)) title=\"\(tab.title)\"")
#endif
                withTransaction(Transaction(animation: nil)) {
                    _ = controller.closeTab(TabID(id: tab.id), inPane: pane.id)
                }
            }
        )
        .onDrag {
            createItemProvider(for: tab)
        } preview: {
            TabDragPreview(tab: tab)
        }
        .onDrop(of: [.text], delegate: TabDropDelegate(
            targetIndex: index,
            pane: pane,
            controller: splitViewController,
            dropTargetIndex: $dropTargetIndex,
            dropLifecycle: $dropLifecycle
        ))
        .overlay(alignment: .leading) {
            if dropTargetIndex == index {
                dropIndicator
                    .saturation(tabBarSaturation)
            }
        }
    }

    // MARK: - Item Provider

    private func createItemProvider(for tab: TabItem) -> NSItemProvider {
        #if DEBUG
        NSLog("[Bonsplit Drag] createItemProvider for tab: \(tab.title)")
        #endif
#if DEBUG
        dlog("tab.dragStart pane=\(pane.id.id.uuidString.prefix(5)) tab=\(tab.id.uuidString.prefix(5)) title=\"\(tab.title)\"")
#endif
        // Clear any stale drop indicator from previous incomplete drag
        dropTargetIndex = nil
        dropLifecycle = .idle

        // Set drag source for visual feedback
        splitViewController.draggingTab = tab
        splitViewController.dragSourcePaneId = pane.id

        // Install a one-shot mouse-up monitor to clear stale drag state if the drag is
        // cancelled (dropped outside any valid target). SwiftUI's onDrag doesn't provide
        // a drag-cancelled callback, so performDrop never fires and draggingTab stays set,
        // which disables hit testing on all content views.
        let controller = splitViewController
        var monitorRef: Any?
        monitorRef = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            // One-shot: remove ourselves, then clean up stale drag state.
            if let m = monitorRef {
                NSEvent.removeMonitor(m)
                monitorRef = nil
            }
            // Use async to avoid mutating @Observable state during event dispatch.
            DispatchQueue.main.async {
                if controller.draggingTab != nil {
#if DEBUG
                    dlog("tab.dragCancel (stale draggingTab cleared)")
#endif
                    controller.draggingTab = nil
                    controller.dragSourcePaneId = nil
                }
            }
            return event
        }

        let transfer = TabTransferData(tab: tab, sourcePaneId: pane.id.id)
        if let data = try? JSONEncoder().encode(transfer),
           let string = String(data: data, encoding: .utf8) {
            return NSItemProvider(object: string as NSString)
        }
        return NSItemProvider()
    }

    private func tabControlShortcutDigit(for index: Int, tabCount: Int) -> Int? {
        for digit in 1...9 {
            if tabIndexForControlShortcutDigit(digit, tabCount: tabCount) == index {
                return digit
            }
        }
        return nil
    }

    private func tabIndexForControlShortcutDigit(_ digit: Int, tabCount: Int) -> Int? {
        guard tabCount > 0, digit >= 1, digit <= 9 else { return nil }
        if digit == 9 {
            return tabCount - 1
        }
        let index = digit - 1
        return index < tabCount ? index : nil
    }

    // MARK: - Drop Zone at End

    @ViewBuilder
    private var dropZoneAfterTabs: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 30, height: TabBarMetrics.tabHeight)
            .contentShape(Rectangle())
            .onDrop(of: [.text], delegate: TabDropDelegate(
                targetIndex: pane.tabs.count,
                pane: pane,
                controller: splitViewController,
                dropTargetIndex: $dropTargetIndex,
                dropLifecycle: $dropLifecycle
            ))
            .overlay(alignment: .leading) {
                if dropTargetIndex == pane.tabs.count {
                    dropIndicator
                        .saturation(tabBarSaturation)
                }
            }
    }

    // MARK: - Drop Indicator

    @ViewBuilder
    private var dropIndicator: some View {
        Capsule()
            .fill(TabBarColors.dropIndicator)
            .frame(width: TabBarMetrics.dropIndicatorWidth, height: TabBarMetrics.dropIndicatorHeight)
            .offset(x: -1)
    }

    // MARK: - Split Buttons

    @ViewBuilder
    private var splitButtons: some View {
        HStack(spacing: 4) {
            Button {
                // 120fps animation handled by SplitAnimator
                controller.splitPane(pane.id, orientation: .horizontal)
            } label: {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Split Right")

            Button {
                // 120fps animation handled by SplitAnimator
                controller.splitPane(pane.id, orientation: .vertical)
            } label: {
                Image(systemName: "square.split.1x2")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Split Down")
        }
        .padding(.trailing, 8)
    }

    // MARK: - Fade Overlays

    @ViewBuilder
    private var fadeOverlays: some View {
        let fadeWidth: CGFloat = 24

        HStack(spacing: 0) {
            // Left fade
            LinearGradient(
                colors: [TabBarColors.barBackground, TabBarColors.barBackground.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
            .opacity(canScrollLeft ? 1 : 0)
            .allowsHitTesting(false)

            Spacer()

            // Right fade
            LinearGradient(
                colors: [TabBarColors.barBackground.opacity(0), TabBarColors.barBackground],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
            .opacity(canScrollRight ? 1 : 0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var tabBarBackground: some View {
        Rectangle()
            .fill(isFocused ? TabBarColors.barBackground : TabBarColors.barBackground.opacity(0.95))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TabBarColors.separator)
                    .frame(height: 1)
            }
    }
}

private enum TabControlShortcutModifier: Equatable {
    case control
    case command

    var symbol: String {
        switch self {
        case .control:
            return "⌃"
        case .command:
            // Command-hold can reveal pane hints, but pane navigation itself is control-based.
            return "⌃"
        }
    }
}

private enum TabControlShortcutHintPolicy {
    static let intentionalHoldDelay: TimeInterval = 0.30

    static func hintModifier(for modifierFlags: NSEvent.ModifierFlags) -> TabControlShortcutModifier? {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.control] { return .control }
        if flags == [.command] { return .command }
        return nil
    }
}

@MainActor
private final class TabControlShortcutKeyMonitor: ObservableObject {
    @Published private(set) var isShortcutHintVisible = false
    @Published private(set) var shortcutModifierSymbol = "⌃"

    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var pendingShowWorkItem: DispatchWorkItem?
    private var pendingModifier: TabControlShortcutModifier?

    func start() {
        guard flagsMonitor == nil else {
            update(from: NSEvent.modifierFlags)
            return
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.update(from: event.modifierFlags)
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.cancelPendingHintShow(resetVisible: true)
            return event
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelPendingHintShow(resetVisible: true)
            }
        }

        update(from: NSEvent.modifierFlags)
    }

    func stop() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        cancelPendingHintShow(resetVisible: true)
    }

    private func update(from modifierFlags: NSEvent.ModifierFlags) {
        guard let modifier = TabControlShortcutHintPolicy.hintModifier(for: modifierFlags) else {
            cancelPendingHintShow(resetVisible: true)
            return
        }

        if isShortcutHintVisible {
            shortcutModifierSymbol = modifier.symbol
            return
        }

        queueHintShow(for: modifier)
    }

    private func queueHintShow(for modifier: TabControlShortcutModifier) {
        if pendingModifier == modifier, pendingShowWorkItem != nil {
            return
        }

        pendingShowWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShowWorkItem = nil
            self.pendingModifier = nil
            guard let currentModifier = TabControlShortcutHintPolicy.hintModifier(for: NSEvent.modifierFlags) else { return }
            self.shortcutModifierSymbol = currentModifier.symbol
            withAnimation(.easeInOut(duration: 0.14)) {
                self.isShortcutHintVisible = true
            }
        }

        pendingModifier = modifier
        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + TabControlShortcutHintPolicy.intentionalHoldDelay, execute: workItem)
    }

    private func cancelPendingHintShow(resetVisible: Bool) {
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        pendingModifier = nil
        if resetVisible {
            withAnimation(.easeInOut(duration: 0.14)) {
                isShortcutHintVisible = false
            }
        }
    }
}


/// Drop lifecycle state to prevent dropUpdated from re-setting state after performDrop
enum TabDropLifecycle {
    case idle
    case hovering
}

// MARK: - Tab Drop Delegate

struct TabDropDelegate: DropDelegate {
    let targetIndex: Int
    let pane: PaneState
    let controller: SplitViewController
    @Binding var dropTargetIndex: Int?
    @Binding var dropLifecycle: TabDropLifecycle

    func performDrop(info: DropInfo) -> Bool {
        #if DEBUG
        NSLog("[Bonsplit Drag] performDrop called, targetIndex: \(targetIndex)")
        #endif
#if DEBUG
        dlog("tab.drop pane=\(pane.id.id.uuidString.prefix(5)) targetIndex=\(targetIndex)")
#endif

        // Ensure all drag/drop side-effects run on the main actor. SwiftUI can call these
        // callbacks off-main, and SplitViewController is @MainActor.
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                performDrop(info: info)
            }
        }

        // Capture the drag source synchronously. Relying on NSItemProvider.loadItem introduces
        // a noticeable delay (often ~100-300ms) before the dragged tab disappears from its
        // source pane, which feels laggy. Since we only accept Bonsplit-originated drags in
        // validateDrop(), we can move immediately using the in-memory drag state.
        guard let draggedTab = controller.draggingTab,
              let sourcePaneId = controller.dragSourcePaneId else {
            return false
        }

        // Execute synchronously when possible so the dragged tab disappears immediately.
        let applyMove = {
            // Ensure the move itself doesn't animate.
            withTransaction(Transaction(animation: nil)) {
                if sourcePaneId == pane.id {
                    guard let sourceIndex = pane.tabs.firstIndex(where: { $0.id == draggedTab.id }) else { return }
                    // Same-pane no-op: don't mutate the model (and don't show an indicator).
                    if targetIndex == sourceIndex || targetIndex == sourceIndex + 1 {
                        return
                    }
                    pane.moveTab(from: sourceIndex, to: targetIndex)
                } else {
                    controller.moveTab(draggedTab, from: sourcePaneId, to: pane.id, atIndex: targetIndex)
                }
            }
        }

        applyMove()

        // Clear visual state immediately to prevent lingering indicators.
        // Must happen synchronously before returning, not in async callback.
        // Setting dropLifecycle to idle prevents dropUpdated from re-setting dropTargetIndex.
        dropLifecycle = .idle
        dropTargetIndex = nil
        controller.draggingTab = nil
        controller.dragSourcePaneId = nil

        return true
    }

    func dropEntered(info: DropInfo) {
        #if DEBUG
        NSLog("[Bonsplit Drag] dropEntered at index: \(targetIndex)")
        #endif
        dropLifecycle = .hovering
        if shouldSuppressIndicatorForNoopSamePaneDrop() {
            dropTargetIndex = nil
        } else {
            dropTargetIndex = targetIndex
        }
    }

    func dropExited(info: DropInfo) {
        #if DEBUG
        NSLog("[Bonsplit Drag] dropExited from index: \(targetIndex)")
        #endif
        dropLifecycle = .idle
        if dropTargetIndex == targetIndex {
            dropTargetIndex = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Guard against dropUpdated firing after performDrop/dropExited
        // This is the key fix for the lingering indicator bug
        guard dropLifecycle == .hovering else {
            return DropProposal(operation: .move)
        }
        // Only update if this is the active target, and suppress same-pane no-op indicators.
        if shouldSuppressIndicatorForNoopSamePaneDrop() {
            if dropTargetIndex == targetIndex {
                dropTargetIndex = nil
            }
        } else if dropTargetIndex != targetIndex {
            dropTargetIndex = targetIndex
        }
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        // Only accept drops originating from Bonsplit tab drags.
        guard controller.draggingTab != nil else { return false }
        return info.hasItemsConforming(to: [.text])
    }

    private func shouldSuppressIndicatorForNoopSamePaneDrop() -> Bool {
        guard let draggedTab = controller.draggingTab,
              controller.dragSourcePaneId == pane.id,
              let sourceIndex = pane.tabs.firstIndex(where: { $0.id == draggedTab.id }) else {
            return false
        }
        // Insertion indices are expressed in "original array" coordinates; after removal,
        // inserting at `sourceIndex` or `sourceIndex + 1` results in no change.
        return targetIndex == sourceIndex || targetIndex == sourceIndex + 1
    }

    private func decodeTransfer(from string: String) -> TabTransferData? {
        guard let data = string.data(using: .utf8),
              let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) else {
            return nil
        }
        return transfer
    }
}
