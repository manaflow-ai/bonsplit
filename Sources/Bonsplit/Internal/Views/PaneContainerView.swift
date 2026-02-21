import SwiftUI
import UniformTypeIdentifiers

/// Drop zone positions for creating splits
public enum DropZone: Equatable {
    case center
    case left
    case right
    case top
    case bottom

    var orientation: SplitOrientation? {
        switch self {
        case .left, .right: return .horizontal
        case .top, .bottom: return .vertical
        case .center: return nil
        }
    }

    var insertsFirst: Bool {
        switch self {
        case .left, .top: return true
        default: return false
        }
    }
}

// MARK: - Environment key for portal-hosted views

/// Environment key so portal-hosted content (e.g. terminal surfaces rendered
/// above SwiftUI via an AppKit portal) can read the active drop zone and show
/// their own overlay, since the SwiftUI placeholder is hidden behind the portal.
private struct ActiveDropZoneKey: EnvironmentKey {
    static let defaultValue: DropZone? = nil
}

public extension EnvironmentValues {
    var paneDropZone: DropZone? {
        get { self[ActiveDropZoneKey.self] }
        set { self[ActiveDropZoneKey.self] = newValue }
    }
}

/// Drop lifecycle state to prevent dropUpdated from re-setting state after performDrop
enum PaneDropLifecycle {
    case idle
    case hovering
}

/// Container for a single pane with its tab bar and content area
struct PaneContainerView<Content: View, EmptyContent: View>: View {
    @Environment(BonsplitController.self) private var bonsplitController

    @Bindable var pane: PaneState
    @Bindable var controller: SplitViewController
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    @State private var activeDropZone: DropZone?
    @State private var dropLifecycle: PaneDropLifecycle = .idle

    private var isFocused: Bool {
        controller.focusedPaneId == pane.id
    }

    private var appearance: BonsplitConfiguration.Appearance {
        bonsplitController.configuration.appearance
    }

    private var isTabDragActive: Bool {
        controller.draggingTab != nil || controller.activeDragTab != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            TabBarView(
                pane: pane,
                isFocused: isFocused,
                showSplitButtons: showSplitButtons
            )

            // Content area with drop zones
            contentAreaWithDropZones
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TabBarColors.paneBackground(for: appearance))
        // Clear drop state when drag ends elsewhere (cancelled, dropped in another pane, etc.)
        .onChange(of: controller.draggingTab) { _, newValue in
#if DEBUG
            dlog(
                "pane.dragState pane=\(pane.id.id.uuidString.prefix(5)) " +
                "draggingTab=\(newValue != nil ? 1 : 0) " +
                "activeDragTab=\(controller.activeDragTab != nil ? 1 : 0) " +
                "dropHit=\(isTabDragActive ? 1 : 0)"
            )
#endif
            if newValue == nil {
                activeDropZone = nil
                dropLifecycle = .idle
            }
        }
        .onChange(of: activeDropZone) { oldValue, newValue in
#if DEBUG
            let oldZone = oldValue.map { String(describing: $0) } ?? "none"
            let newZone = newValue.map { String(describing: $0) } ?? "none"
            let selected = pane.selectedTab ?? pane.tabs.first
            let icon = selected?.icon ?? "nil"
            dlog(
                "pane.overlayZone pane=\(pane.id.id.uuidString.prefix(5)) " +
                "old=\(oldZone) new=\(newZone) selectedIcon=\(icon)"
            )
#endif
        }
    }

    // MARK: - Content Area with Drop Zones

    @ViewBuilder
    private var contentAreaWithDropZones: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                // Main content
                contentArea

                // Drop zones layer (above content, receives drops and taps)
                dropZonesLayer(size: size)

                // Visual placeholder (non-interactive)
                dropPlaceholder(for: activeDropZone, in: size)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
        }
        .clipped()
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        Group {
            if pane.tabs.isEmpty {
                emptyPaneView
            } else {
                switch contentViewLifecycle {
                case .recreateOnSwitch:
                    // Original behavior: only render selected tab
                    //
                    // `selectedTabId` can be transiently nil (or point at a tab that is being moved/closed)
                    // during rapid split/tab mutations. Rendering nothing for a single SwiftUI update causes
                    // a visible blank flash. If we have tabs, always render a stable fallback.
                    if let selectedTab = pane.selectedTab ?? pane.tabs.first {
                        contentBuilder(selectedTab, pane.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // When the content is an NSViewRepresentable (e.g. WKWebView), it can
                            // sit above SwiftUI overlays and swallow drop events. During tab drags,
                            // disable hit testing for the content so our dropZonesLayer reliably
                            // receives the drag/drop interaction.
                            .allowsHitTesting(!isTabDragActive)
                            // Tab selection is often driven by `withAnimation` in the tab bar;
                            // don't crossfade the content when switching tabs.
                            .transition(.identity)
                            .transaction { tx in
                                tx.animation = nil
                            }
                    }

                case .keepAllAlive:
                    // macOS-like behavior: keep all tab views in hierarchy
                    let effectiveSelectedTabId = pane.selectedTabId ?? pane.tabs.first?.id
                    ZStack {
                        ForEach(pane.tabs) { tab in
                            contentBuilder(tab, pane.id)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(tab.id == effectiveSelectedTabId ? 1 : 0)
                                .allowsHitTesting(!isTabDragActive && tab.id == effectiveSelectedTabId)
                        }
                    }
                    // Prevent SwiftUI from animating Metal-backed views during tab moves.
                    // This avoids blank content when GhosttyKit terminals are snapshotted.
                    .transaction { tx in
                        tx.disablesAnimations = true
                    }
                }
            }
        }
        // Ensure a tab switch doesn't implicitly animate other animatable properties in this subtree.
        .animation(nil, value: pane.selectedTabId)
        // Expose the active drop zone to portal-hosted content so it can render
        // its own overlay above the AppKit surface.
        .environment(\.paneDropZone, activeDropZone)
    }

    // MARK: - Drop Zones Layer

    @ViewBuilder
    private func dropZonesLayer(size: CGSize) -> some View {
        // Keep tap-to-focus and drag-drop routing as separate layers.
        //
        // Why: SwiftUI state propagation for `isTabDragActive` can lag behind the
        // actual AppKit drag lifecycle (especially over portal-hosted terminals),
        // causing a drag to start while this view is still non-hit-testable.
        // The drop layer therefore stays always available for `.tabTransfer`.
        ZStack {
            Color.clear
                .onTapGesture {
#if DEBUG
                    dlog("pane.focus pane=\(pane.id.id.uuidString.prefix(5))")
#endif
                    controller.focusPane(pane.id)
                }
                .allowsHitTesting(!isTabDragActive)

            Color.clear
                .onDrop(of: [.tabTransfer], delegate: UnifiedPaneDropDelegate(
                    size: size,
                    pane: pane,
                    controller: controller,
                    bonsplitController: bonsplitController,
                    activeDropZone: $activeDropZone,
                    dropLifecycle: $dropLifecycle
                ))
        }
    }

    // MARK: - Drop Placeholder

    @ViewBuilder
    private func dropPlaceholder(for zone: DropZone?, in size: CGSize) -> some View {
        let placeholderColor = Color.accentColor.opacity(0.25)
        let borderColor = Color.accentColor
        let padding: CGFloat = 4

        // Calculate frame based on zone
        let frame: CGRect = {
            switch zone {
            case .center, .none:
                return CGRect(x: padding, y: padding, width: size.width - padding * 2, height: size.height - padding * 2)
            case .left:
                return CGRect(x: padding, y: padding, width: size.width / 2 - padding, height: size.height - padding * 2)
            case .right:
                return CGRect(x: size.width / 2, y: padding, width: size.width / 2 - padding, height: size.height - padding * 2)
            case .top:
                return CGRect(x: padding, y: padding, width: size.width - padding * 2, height: size.height / 2 - padding)
            case .bottom:
                return CGRect(x: padding, y: size.height / 2, width: size.width - padding * 2, height: size.height / 2 - padding)
            }
        }()

        RoundedRectangle(cornerRadius: 8)
            .fill(placeholderColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 2)
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .opacity(zone != nil ? 1 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.15), value: zone)
    }

    // MARK: - Empty Pane View

    @ViewBuilder
    private var emptyPaneView: some View {
        emptyPaneBuilder(pane.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unified Pane Drop Delegate

struct UnifiedPaneDropDelegate: DropDelegate {
    let size: CGSize
    let pane: PaneState
    let controller: SplitViewController
    let bonsplitController: BonsplitController
    @Binding var activeDropZone: DropZone?
    @Binding var dropLifecycle: PaneDropLifecycle

    // Calculate zone based on position within the view
    private func zoneForLocation(_ location: CGPoint) -> DropZone {
        let edgeRatio: CGFloat = 0.25
        let horizontalEdge = max(80, size.width * edgeRatio)
        let verticalEdge = max(80, size.height * edgeRatio)

        // Check edges first (left/right take priority at corners)
        if location.x < horizontalEdge {
            return .left
        } else if location.x > size.width - horizontalEdge {
            return .right
        } else if location.y < verticalEdge {
            return .top
        } else if location.y > size.height - verticalEdge {
            return .bottom
        } else {
            return .center
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                performDrop(info: info)
            }
        }

        let zone = zoneForLocation(info.location)
#if DEBUG
        dlog(
            "pane.drop pane=\(pane.id.id.uuidString.prefix(5)) zone=\(zone) " +
            "source=\(controller.dragSourcePaneId?.id.uuidString.prefix(5) ?? "nil") " +
            "hasDrag=\(controller.draggingTab != nil ? 1 : 0) " +
            "hasActive=\(controller.activeDragTab != nil ? 1 : 0)"
        )
#endif

        // Read from non-observable drag state — @Observable writes from createItemProvider
        // may not have propagated yet when performDrop runs.
        guard let draggedTab = controller.activeDragTab ?? controller.draggingTab,
              let sourcePaneId = controller.activeDragSourcePaneId ?? controller.dragSourcePaneId else {
            return false
        }

        // Clear both observable and non-observable drag state.
        dropLifecycle = .idle
        activeDropZone = nil
        controller.draggingTab = nil
        controller.dragSourcePaneId = nil
        controller.activeDragTab = nil
        controller.activeDragSourcePaneId = nil

        if zone == .center {
            if sourcePaneId != pane.id {
                withTransaction(Transaction(animation: nil)) {
                    controller.moveTab(draggedTab, from: sourcePaneId, to: pane.id, atIndex: nil)
                }
            }
        } else if let orientation = zone.orientation {
#if DEBUG
            dlog(
                "pane.drop.splitRequest targetPane=\(pane.id.id.uuidString.prefix(5)) " +
                "sourcePane=\(sourcePaneId.id.uuidString.prefix(5)) zone=\(zone) " +
                "orientation=\(orientation) insertFirst=\(zone.insertsFirst ? 1 : 0) " +
                "draggedTab=\(draggedTab.id.uuidString.prefix(5))"
            )
#endif
            let newPaneId = bonsplitController.splitPane(
                pane.id,
                orientation: orientation,
                movingTab: TabID(id: draggedTab.id),
                insertFirst: zone.insertsFirst
            )
#if DEBUG
            dlog(
                "pane.drop.splitResult targetPane=\(pane.id.id.uuidString.prefix(5)) " +
                "newPane=\(newPaneId?.id.uuidString.prefix(5) ?? "nil")"
            )
#endif
        }

        return true
    }

    func dropEntered(info: DropInfo) {
        dropLifecycle = .hovering
        let zone = zoneForLocation(info.location)
        activeDropZone = zone
#if DEBUG
        dlog(
            "pane.dropEntered pane=\(pane.id.id.uuidString.prefix(5)) zone=\(zone) " +
            "hasDrag=\(controller.draggingTab != nil ? 1 : 0) " +
            "hasActive=\(controller.activeDragTab != nil ? 1 : 0)"
        )
#endif
    }

    func dropExited(info: DropInfo) {
        dropLifecycle = .idle
        activeDropZone = nil
#if DEBUG
        dlog("pane.dropExited pane=\(pane.id.id.uuidString.prefix(5))")
#endif
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Guard against dropUpdated firing after performDrop/dropExited
        guard dropLifecycle == .hovering else {
#if DEBUG
            dlog("pane.dropUpdated.skip pane=\(pane.id.id.uuidString.prefix(5)) reason=lifecycle_idle")
#endif
            return DropProposal(operation: .move)
        }
        let zone = zoneForLocation(info.location)
        activeDropZone = zone
#if DEBUG
        dlog("pane.dropUpdated pane=\(pane.id.id.uuidString.prefix(5)) zone=\(zone)")
#endif
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        // Reject drops on inactive workspaces whose views are kept alive in a ZStack.
        guard controller.isInteractive else {
#if DEBUG
            dlog("pane.validateDrop pane=\(pane.id.id.uuidString.prefix(5)) allowed=0 reason=inactive")
#endif
            return false
        }
        // The custom UTType alone is sufficient — only Bonsplit tab drags produce it.
        // Do NOT gate on draggingTab != nil: @Observable changes from createItemProvider
        // may not have propagated to the drop delegate yet, causing false rejections.
        let hasType = info.hasItemsConforming(to: [.tabTransfer])
#if DEBUG
        let hasDrag = controller.draggingTab != nil
        let hasActive = controller.activeDragTab != nil
        dlog(
            "pane.validateDrop pane=\(pane.id.id.uuidString.prefix(5)) " +
            "allowed=\(hasType ? 1 : 0) hasDrag=\(hasDrag ? 1 : 0) hasActive=\(hasActive ? 1 : 0)"
        )
#endif
        return hasType
    }

    private func decodeTransfer(from string: String) -> TabTransferData? {
        guard let data = string.data(using: .utf8),
              let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) else {
            return nil
        }
        return transfer
    }
}
