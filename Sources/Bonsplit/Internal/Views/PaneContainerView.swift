import SwiftUI
import UniformTypeIdentifiers

/// Drop zone positions for creating splits
enum DropZone: Equatable {
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

/// Drop lifecycle state to prevent dropUpdated from re-setting state after performDrop
enum PaneDropLifecycle {
    case idle
    case hovering
}

/// Container for a single pane with its tab bar and content area
struct PaneContainerView<Content: View, EmptyContent: View>: View {
    @Environment(BonsplitController.self) private var bonsplitController

    @Bindable var pane: PaneState
    let controller: SplitViewController
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    @State private var activeDropZone: DropZone?
    @State private var dropLifecycle: PaneDropLifecycle = .idle

    private var isFocused: Bool {
        controller.focusedPaneId == pane.id
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
        .background(Color(nsColor: .textBackgroundColor))
        // Clear drop state when drag ends elsewhere (cancelled, dropped in another pane, etc.)
        .onChange(of: controller.draggingTab) { _, newValue in
            if newValue == nil {
                activeDropZone = nil
                dropLifecycle = .idle
            }
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
                    if let selectedTab = pane.selectedTab {
                        contentBuilder(selectedTab, pane.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // Tab selection is often driven by `withAnimation` in the tab bar;
                            // don't crossfade the content when switching tabs.
                            .transition(.identity)
                            .transaction { tx in
                                tx.animation = nil
                            }
                    }

                case .keepAllAlive:
                    // macOS-like behavior: keep all tab views in hierarchy
                    ZStack {
                        ForEach(pane.tabs) { tab in
                            contentBuilder(tab, pane.id)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(tab.id == pane.selectedTabId ? 1 : 0)
                                .allowsHitTesting(tab.id == pane.selectedTabId)
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
    }

    // MARK: - Drop Zones Layer

    @ViewBuilder
    private func dropZonesLayer(size: CGSize) -> some View {
        // Single unified drop zone that determines zone based on position
        Color.clear
            .onTapGesture {
                controller.focusPane(pane.id)
            }
            .onDrop(of: [.text], delegate: UnifiedPaneDropDelegate(
                size: size,
                pane: pane,
                controller: controller,
                bonsplitController: bonsplitController,
                activeDropZone: $activeDropZone,
                dropLifecycle: $dropLifecycle
            ))
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
        let zone = zoneForLocation(info.location)

        // Clear visual state immediately to prevent lingering blue indicator.
        // Must happen synchronously before returning, not in async callback.
        // Setting dropLifecycle to idle prevents dropUpdated from re-setting activeDropZone.
        dropLifecycle = .idle
        activeDropZone = nil
        controller.draggingTab = nil
        controller.dragSourcePaneId = nil

        guard let provider = info.itemProviders(for: [.text]).first else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            DispatchQueue.main.async {

                // Handle both Data and String representations
                let string: String?
                if let data = item as? Data {
                    string = String(data: data, encoding: .utf8)
                } else if let nsString = item as? NSString {
                    string = nsString as String
                } else if let str = item as? String {
                    string = str
                } else {
                    string = nil
                }

                guard let string, let transfer = decodeTransfer(from: string) else {
                    return
                }

                // Find source pane
                guard let sourcePaneId = controller.rootNode.allPaneIds.first(where: { $0.id == transfer.sourcePaneId }) else {
                    return
                }

                if zone == .center {
                    // Drop in center - move tab to this pane
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                        controller.moveTab(transfer.tab, from: sourcePaneId, to: pane.id, atIndex: nil)
                    }
                } else if let orientation = zone.orientation {
                    // Drop on edge - create a split by moving the tab into the new pane.
                    //
                    // Important: this must not "close the source pane if empty" when the source
                    // pane is also the split target (drag-to-edge within the same pane), or we
                    // can end up closing the pane we're trying to split.
                    _ = bonsplitController.splitPane(
                        pane.id,
                        orientation: orientation,
                        movingTab: TabID(id: transfer.tab.id),
                        insertFirst: zone.insertsFirst
                    )
                }
            }
        }

        return true
    }

    func dropEntered(info: DropInfo) {
        dropLifecycle = .hovering
        activeDropZone = zoneForLocation(info.location)
    }

    func dropExited(info: DropInfo) {
        dropLifecycle = .idle
        activeDropZone = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Guard against dropUpdated firing after performDrop/dropExited
        guard dropLifecycle == .hovering else {
            return DropProposal(operation: .move)
        }
        activeDropZone = zoneForLocation(info.location)
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    private func decodeTransfer(from string: String) -> TabTransferData? {
        guard let data = string.data(using: .utf8),
              let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data) else {
            return nil
        }
        return transfer
    }
}
