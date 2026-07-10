import SwiftUI

/// Main container view that renders the entire split tree (internal implementation)
struct SplitViewContainer<Content: View, EmptyContent: View>: View {
    @Environment(SplitViewController.self) private var controller

    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    let appearance: BonsplitConfiguration.Appearance
    let dividerPositionRange: ClosedRange<CGFloat>
    var showSplitButtons: Bool = true
    var tabBarVisibility: TabBarVisibility = .always
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?
    var enableAnimations: Bool = true
    var animationDuration: Double = 0.15

    var body: some View {
        GeometryReader { geometry in
            splitNodeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TabBarColors.paneBackground(for: appearance))
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
        // Always render the full tree. Zoom is applied by collapsing the
        // non-zoomed side of each split on the zoom path (see
        // SplitContainerView), never by swapping the rendered node: swapping
        // changes SwiftUI structural identity and tears down / rebuilds the
        // entire AppKit split hierarchy (one NSHostingController per pane),
        // which made maximize/minimize scale with pane count.
        SplitNodeView(
            node: controller.rootNode,
            zoomedPaneId: controller.zoomedPaneId,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            appearance: appearance,
            dividerPositionRange: dividerPositionRange,
            showSplitButtons: showSplitButtons,
            tabBarVisibility: tabBarVisibility,
            contentViewLifecycle: contentViewLifecycle,
            onGeometryChange: onGeometryChange,
            enableAnimations: enableAnimations,
            animationDuration: animationDuration
        )
    }
}
