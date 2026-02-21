import SwiftUI
import AppKit

/// Recursively renders a split node (pane or split)
struct SplitNodeView<Content: View, EmptyContent: View>: View {
    @Environment(SplitViewController.self) private var controller

    let node: SplitNode
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    let appearance: BonsplitConfiguration.Appearance
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?
    var enableAnimations: Bool = true
    var animationDuration: Double = 0.15

    var body: some View {
        switch node {
        case .pane(let paneState):
            // Wrap in NSHostingController for proper layout constraints
            SinglePaneWrapper(
                pane: paneState,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )

        case .split(let splitState):
            SplitContainerView(
                splitState: splitState,
                controller: controller,
                appearance: appearance,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle,
                onGeometryChange: onGeometryChange,
                enableAnimations: enableAnimations,
                animationDuration: animationDuration
            )
        }
    }
}

/// Container NSView for a pane inside SinglePaneWrapper.
class PaneDragContainerView: NSView {
    override var isOpaque: Bool { false }
}

/// Wrapper that uses NSHostingController for proper AppKit layout constraints
struct SinglePaneWrapper<Content: View, EmptyContent: View>: NSViewRepresentable {
    @Environment(SplitViewController.self) private var controller
    
    let pane: PaneState
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch

    private func configureHostingViewTransparency(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }

    func makeNSView(context: Context) -> NSView {
        let paneView = PaneContainerView(
            pane: pane,
            controller: controller,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        let hostingController = NSHostingController(rootView: paneView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        configureHostingViewTransparency(hostingController.view)

        let containerView = PaneDragContainerView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.layer?.isOpaque = false
        containerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        // Store hosting controller to keep it alive
        context.coordinator.hostingController = hostingController

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Hide the container when inactive so AppKit's drag routing doesn't deliver
        // drag sessions to views belonging to background workspaces.
        nsView.isHidden = !controller.isInteractive

        let paneView = PaneContainerView(
            pane: pane,
            controller: controller,
            contentBuilder: contentBuilder,
            emptyPaneBuilder: emptyPaneBuilder,
            showSplitButtons: showSplitButtons,
            contentViewLifecycle: contentViewLifecycle
        )
        if let hostingController = context.coordinator.hostingController {
            hostingController.rootView = paneView
            configureHostingViewTransparency(hostingController.view)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingController: NSHostingController<PaneContainerView<Content, EmptyContent>>?
    }
}
