import SwiftUI

/// Main container view that renders the entire split tree (internal implementation)
struct SplitViewContainer<Content: View, EmptyContent: View>: View {
    @Environment(SplitViewController.self) private var controller

    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    let appearance: BonsplitConfiguration.Appearance
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?
    var enableAnimations: Bool = true
    var animationDuration: Double = 0.15

    var body: some View {
        GeometryReader { geometry in
            splitNodeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable()
                .focusEffectDisabled()
                .onChange(of: geometry.size) { _, newSize in
                    updateContainerFrame(geometry: geometry)
                }
                .onAppear {
                    updateContainerFrame(geometry: geometry)
                }
        }
    }

    private func updateContainerFrame(geometry: GeometryProxy) {
        // Get frame in global coordinate space
        let frame = geometry.frame(in: .global)
        controller.containerFrame = frame
        onGeometryChange?(false)  // Container resize is not a drag
    }

    @ViewBuilder
    private var splitNodeContent: some View {
        if let zoomedPaneId = controller.zoomedPaneId,
           let zoomedPane = controller.rootNode.findPane(zoomedPaneId) {
            // Keep the full split tree mounted so existing pane views can receive
            // visibility updates (important for portal-hosted native surfaces),
            // then overlay a fullscreen render of the zoomed pane.
            ZStack {
                SplitNodeView(
                    node: controller.rootNode,
                    contentBuilder: contentBuilder,
                    emptyPaneBuilder: emptyPaneBuilder,
                    appearance: appearance,
                    excludedPaneID: zoomedPaneId,
                    showSplitButtons: showSplitButtons,
                    contentViewLifecycle: contentViewLifecycle,
                    onGeometryChange: onGeometryChange,
                    enableAnimations: enableAnimations,
                    animationDuration: animationDuration
                )
                // Keep split content mounted for state propagation, but visually transparent.
                // This preserves pane update callbacks needed by portal-hosted surfaces.
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                SinglePaneWrapper(
                    pane: zoomedPane,
                    contentBuilder: contentBuilder,
                    emptyPaneBuilder: emptyPaneBuilder,
                    showSplitButtons: showSplitButtons,
                    contentViewLifecycle: contentViewLifecycle
                )
            }
        } else {
            SplitNodeView(
                node: controller.rootNode,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                appearance: appearance,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                onGeometryChange: onGeometryChange,
                enableAnimations: enableAnimations,
                animationDuration: animationDuration
            )
        }
    }
}
