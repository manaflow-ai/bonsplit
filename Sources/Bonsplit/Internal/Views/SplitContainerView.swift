import SwiftUI
import AppKit

private var splitContainerProgrammaticSyncDepth = 0

/// SwiftUI wrapper around NSSplitView for native split behavior
struct SplitContainerView<Content: View, EmptyContent: View>: NSViewRepresentable {
    @Bindable var splitState: SplitState
    let controller: SplitViewController
    let contentBuilder: (TabItem, PaneID) -> Content
    let emptyPaneBuilder: (PaneID) -> EmptyContent
    var showSplitButtons: Bool = true
    var contentViewLifecycle: ContentViewLifecycle = .recreateOnSwitch
    /// Callback when geometry changes. Bool indicates if change is during active divider drag.
    var onGeometryChange: ((_ isDragging: Bool) -> Void)?
    /// Animation configuration
    var enableAnimations: Bool = true
    var animationDuration: Double = 0.15

    func makeCoordinator() -> Coordinator {
        Coordinator(splitState: splitState, onGeometryChange: onGeometryChange)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = splitState.orientation == .horizontal
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        // Bonsplit is often embedded in transparent/vibrant window backgrounds. Ensure the
        // split view itself is not fully transparent so divider regions don't "show through"
        // to whatever is behind the split hierarchy.
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Keep arranged subviews stable (always 2) to avoid transient "collapse" flashes when
        // replacing pane<->split content. We swap the hosted content within these containers.
        let firstContainer = NSView()
        firstContainer.wantsLayer = true
        firstContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        firstContainer.layer?.masksToBounds = true
        let firstController = makeHostingController(for: splitState.first)
        installHostingController(firstController, into: firstContainer)
        splitView.addArrangedSubview(firstContainer)
        context.coordinator.firstHostingController = firstController

        let secondContainer = NSView()
        secondContainer.wantsLayer = true
        secondContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        secondContainer.layer?.masksToBounds = true
        let secondController = makeHostingController(for: splitState.second)
        installHostingController(secondController, into: secondContainer)
        splitView.addArrangedSubview(secondContainer)
        context.coordinator.secondHostingController = secondController

        context.coordinator.splitView = splitView

        // Capture animation origin before it gets cleared
        let animationOrigin = splitState.animationOrigin

        // Determine which pane is new (will be hidden initially)
        let newPaneIndex = animationOrigin == .fromFirst ? 0 : 1

        // Capture animation settings for async block
        let shouldAnimate = enableAnimations && animationOrigin != nil
        let duration = animationDuration

        if animationOrigin != nil {
            // Clear immediately so we don't re-animate on updates
            splitState.animationOrigin = nil

            if shouldAnimate {
                // Hide the NEW pane immediately to prevent flash
                splitView.arrangedSubviews[newPaneIndex].isHidden = true

                // Track that we're animating (skip delegate position updates)
                context.coordinator.isAnimating = true
            }
        }

        // Apply the initial divider position once after initial layout scheduling.
        func applyInitialDividerPosition() {
            if context.coordinator.didApplyInitialDividerPosition {
                return
            }

            let totalSize = splitState.orientation == .horizontal
                ? splitView.bounds.width
                : splitView.bounds.height
            let availableSize = max(totalSize - splitView.dividerThickness, 0)

            guard availableSize > 0 else {
                // Ensure we don't leave the new pane hidden forever.
                context.coordinator.didApplyInitialDividerPosition = true
                if animationOrigin != nil, shouldAnimate {
                    splitView.arrangedSubviews[newPaneIndex].isHidden = false
                    context.coordinator.isAnimating = false
                }
                return
            }

            context.coordinator.didApplyInitialDividerPosition = true

            if animationOrigin != nil {
                let targetPosition = availableSize * 0.5
                splitState.dividerPosition = 0.5

                if shouldAnimate {
                    // Position at edge while new pane is hidden
                    let startPosition: CGFloat = animationOrigin == .fromFirst ? 0 : availableSize
                    context.coordinator.setPositionSafely(startPosition, in: splitView, layout: true)

                    // Wait for layout
                    DispatchQueue.main.async {
                        // Show the new pane and animate
                        splitView.arrangedSubviews[newPaneIndex].isHidden = false

                        SplitAnimator.shared.animate(
                            splitView: splitView,
                            from: startPosition,
                            to: targetPosition,
                            duration: duration
                        ) {
                            context.coordinator.isAnimating = false
                            // Re-assert exact 0.5 ratio to prevent pixel-rounding drift
                            splitState.dividerPosition = 0.5
                            context.coordinator.lastAppliedPosition = 0.5
                        }
                    }
                } else {
                    // No animation - just set the position immediately
                    context.coordinator.setPositionSafely(targetPosition, in: splitView, layout: false)
                }
            } else {
                // No animation - just set the position
                let position = availableSize * splitState.dividerPosition
                context.coordinator.setPositionSafely(position, in: splitView, layout: false)
            }
        }

        DispatchQueue.main.async {
            applyInitialDividerPosition()
        }

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        // SwiftUI may reuse the same NSSplitView/Coordinator instance while the underlying SplitState
        // object changes (e.g., during split tree restructuring). Keep the coordinator pointed at
        // the latest state to avoid syncing geometry against a stale model.
        context.coordinator.update(splitState: splitState, onGeometryChange: onGeometryChange)

        // Update orientation if changed
        splitView.isVertical = splitState.orientation == .horizontal

        // Update children. When a child's node type changes (split→pane or pane→split),
        // replace the hosted content (not the arranged subview) to ensure native NSViews
        // (e.g., Metal-backed terminals) are properly moved through the AppKit hierarchy
        // without briefly dropping arrangedSubviews to 1.
        let arranged = splitView.arrangedSubviews
        if arranged.count >= 2 {
            let firstType = splitState.first.nodeType
            let secondType = splitState.second.nodeType

            let firstContainer = arranged[0]
            let secondContainer = arranged[1]

            updateHostedContent(
                in: firstContainer,
                node: splitState.first,
                nodeTypeChanged: firstType != context.coordinator.firstNodeType,
                controller: &context.coordinator.firstHostingController
            )
            context.coordinator.firstNodeType = firstType

            updateHostedContent(
                in: secondContainer,
                node: splitState.second,
                nodeTypeChanged: secondType != context.coordinator.secondNodeType,
                controller: &context.coordinator.secondHostingController
            )
            context.coordinator.secondNodeType = secondType
        }

        // Access dividerPosition to ensure SwiftUI tracks this dependency
        // Then sync if the position changed externally
        let currentPosition = splitState.dividerPosition
        context.coordinator.syncPosition(currentPosition, in: splitView)
    }

    // MARK: - Helpers

    private func makeHostingController(for node: SplitNode) -> NSHostingController<AnyView> {
        let hostingController = NSHostingController(rootView: AnyView(makeView(for: node)))
        // NSSplitView lays out arranged subviews by setting frames. Leaving Auto Layout
        // enabled on these NSHostingViews can allow them to compress to 0 during
        // structural updates, collapsing panes.
        hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        hostingController.view.autoresizingMask = [.width, .height]
        return hostingController
    }

    private func installHostingController(_ hostingController: NSHostingController<AnyView>, into container: NSView) {
        let hostedView = hostingController.view
        hostedView.frame = container.bounds
        hostedView.autoresizingMask = [.width, .height]
        if hostedView.superview !== container {
            container.addSubview(hostedView)
        }
    }

    private func updateHostedContent(
        in container: NSView,
        node: SplitNode,
        nodeTypeChanged: Bool,
        controller: inout NSHostingController<AnyView>?
    ) {
        // Historically we recreated the NSHostingController when the child node type changed
        // (pane <-> split) to force a full detach/reattach of native AppKit subviews.
        //
        // In practice, that can introduce a single-frame "blank flash" for Metal/IOSurface-backed
        // content during split collapse (SwiftUI tears down the old subtree before the new subtree
        // has produced its native backing views).
        //
        // Keeping the hosting controller stable and just swapping its rootView makes the update
        // atomic from AppKit's perspective and avoids the transient blank frame.
        _ = nodeTypeChanged // keep signature; behavior is intentionally identical either way.

        if let current = controller {
            current.rootView = AnyView(makeView(for: node))
            // Ensure fill if container bounds changed without a layout pass yet.
            current.view.frame = container.bounds
            return
        }

        let newController = makeHostingController(for: node)
        installHostingController(newController, into: container)
        controller = newController
    }

    @ViewBuilder
    private func makeView(for node: SplitNode) -> some View {
        switch node {
        case .pane(let paneState):
            PaneContainerView(
                pane: paneState,
                controller: controller,
                contentBuilder: contentBuilder,
                emptyPaneBuilder: emptyPaneBuilder,
                showSplitButtons: showSplitButtons,
                contentViewLifecycle: contentViewLifecycle
            )
        case .split(let nestedSplitState):
            SplitContainerView(
                splitState: nestedSplitState,
                controller: controller,
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

    // MARK: - Coordinator

    class Coordinator: NSObject, NSSplitViewDelegate {
        var splitState: SplitState
        private var splitStateId: UUID
        weak var splitView: NSSplitView?
        var isAnimating = false
        var didApplyInitialDividerPosition = false
        var onGeometryChange: ((_ isDragging: Bool) -> Void)?
        /// Track last applied position to detect external changes
        var lastAppliedPosition: CGFloat = 0.5
        // Guard programmatic `setPosition` re-entrancy from resize callbacks.
        var isSyncingProgrammatically = false
        /// Track if user is actively dragging the divider
        var isDragging = false
        /// Track child node types to detect structural changes
        var firstNodeType: SplitNode.NodeType
        var secondNodeType: SplitNode.NodeType
        /// Retain hosting controllers so SwiftUI content stays alive
        var firstHostingController: NSHostingController<AnyView>?
        var secondHostingController: NSHostingController<AnyView>?

        init(splitState: SplitState, onGeometryChange: ((_ isDragging: Bool) -> Void)?) {
            self.splitState = splitState
            self.splitStateId = splitState.id
            self.onGeometryChange = onGeometryChange
            self.lastAppliedPosition = splitState.dividerPosition
            self.firstNodeType = splitState.first.nodeType
            self.secondNodeType = splitState.second.nodeType
        }

        func update(splitState newState: SplitState, onGeometryChange: ((_ isDragging: Bool) -> Void)?) {
            self.onGeometryChange = onGeometryChange

            // If SwiftUI reused this representable for a different split node,
            // reset our cached sync state so we don't "pin" the divider to an edge.
            if newState.id != splitStateId {
                splitStateId = newState.id
                splitState = newState
                lastAppliedPosition = newState.dividerPosition
                didApplyInitialDividerPosition = false
                isAnimating = false
                isDragging = false
                firstNodeType = newState.first.nodeType
                secondNodeType = newState.second.nodeType
                return
            }

            // Same split node; keep reference updated anyway.
            splitState = newState
        }

        /// Apply external position changes to the NSSplitView
        func setPositionSafely(_ position: CGFloat, in splitView: NSSplitView, layout: Bool = true) {
            isSyncingProgrammatically = true
            splitContainerProgrammaticSyncDepth += 1
            defer {
                isSyncingProgrammatically = false
                splitContainerProgrammaticSyncDepth = max(0, splitContainerProgrammaticSyncDepth - 1)
            }
            splitView.setPosition(position, ofDividerAt: 0)
            if layout {
                splitView.layoutSubtreeIfNeeded()
            }
        }

        func syncPosition(_ statePosition: CGFloat, in splitView: NSSplitView) {
            guard !isAnimating else { return }
            guard !isSyncingProgrammatically else { return }
            guard splitContainerProgrammaticSyncDepth == 0 else { return }

            guard splitView.arrangedSubviews.count >= 2 else {
                // Structural updates can temporarily remove an arranged subview.
                // A subsequent update/layout pass will re-apply the model position.
#if DEBUG
                BonsplitDebugCounters.recordArrangedSubviewUnderflow()
#endif
                return
            }

            let totalSize = splitState.orientation == .horizontal
                ? splitView.bounds.width
                : splitView.bounds.height
            let availableSize = max(totalSize - splitView.dividerThickness, 0)

            // During view reparenting, NSSplitView can briefly report 0-sized bounds.
            // A later layout pass with real bounds will apply the model ratio.
            guard availableSize > 0 else { return }

            // Keep the view in sync even if the model hasn't changed. Structural updates (pane↔split)
            // can temporarily reset divider positions; lastAppliedPosition alone isn't enough.
            let currentDividerPixels: CGFloat = {
                let firstSubview = splitView.arrangedSubviews[0]
                return splitState.orientation == .horizontal ? firstSubview.frame.width : firstSubview.frame.height
            }()
            let currentNormalized = currentDividerPixels / availableSize

            if abs(statePosition - lastAppliedPosition) <= 0.01 && abs(currentNormalized - statePosition) <= 0.01 {
                return
            }

            let pixelPosition = availableSize * statePosition
            setPositionSafely(pixelPosition, in: splitView, layout: true)
            lastAppliedPosition = statePosition
        }

        func splitViewWillResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView else { return }
            // If the left mouse button isn't down, this can't be an interactive divider drag.
            // (`splitViewWillResizeSubviews` can fire for programmatic/layout-driven resizes too.)
            guard (NSEvent.pressedMouseButtons & 1) != 0 else {
                isDragging = false
                return
            }

            // If we're already tracking an active drag, keep the flag until mouse-up.
            if isDragging {
                return
            }

            guard let event = NSApp.currentEvent else { return }

            // Only treat this as a divider drag if the pointer is actually on the divider.
            // This delegate callback can also fire during window resizes or structural updates,
            // and persisting divider ratios in those cases can permanently collapse a pane.
            let now = ProcessInfo.processInfo.systemUptime
            // `NSApp.currentEvent` can be stale when called from async UI work (e.g. socket commands).
            // Only trust very recent events.
            guard (now - event.timestamp) < 0.1 else { return }
            guard event.type == .leftMouseDown || event.type == .leftMouseDragged else { return }
            guard event.window == splitView.window else { return }
            guard splitView.arrangedSubviews.count >= 2 else { return }

            let location = splitView.convert(event.locationInWindow, from: nil)
            let a = splitView.arrangedSubviews[0].frame
            let b = splitView.arrangedSubviews[1].frame
            let thickness = splitView.dividerThickness
            let dividerRect: NSRect
            if splitView.isVertical {
                // If we don't have real frames yet (during structural updates), don't infer dragging.
                guard a.width > 1, b.width > 1 else { return }
                // Vertical divider between left/right arranged subviews.
                let x = max(0, a.maxX)
                dividerRect = NSRect(x: x, y: 0, width: thickness, height: splitView.bounds.height)
            } else {
                guard a.height > 1, b.height > 1 else { return }
                // Horizontal divider between top/bottom arranged subviews.
                let y = max(0, a.maxY)
                dividerRect = NSRect(x: 0, y: y, width: splitView.bounds.width, height: thickness)
            }
            let hitRect = dividerRect.insetBy(dx: -4, dy: -4)
            if hitRect.contains(location) {
                isDragging = true
#if DEBUG
                dlog("divider.dragStart split=\(splitState.id.uuidString.prefix(5))")
#endif
            }
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            // Skip position updates during animation
            guard !isAnimating else { return }
            guard let splitView = notification.object as? NSSplitView else { return }
            if isSyncingProgrammatically || splitContainerProgrammaticSyncDepth > 0 {
                return
            }
            // Prevent stale drag state from persisting through programmatic/async resizes.
            let leftDown = (NSEvent.pressedMouseButtons & 1) != 0
            if !leftDown {
                isDragging = false
            }
            // During structural updates (pane↔split), arranged subviews can be temporarily removed.
            // Avoid persisting a dividerPosition derived from a transient 1-subview layout.
            guard splitView.arrangedSubviews.count >= 2 else {
#if DEBUG
                BonsplitDebugCounters.recordArrangedSubviewUnderflow()
#endif
                return
            }

            let totalSize = splitState.orientation == .horizontal
                ? splitView.bounds.width
                : splitView.bounds.height
            let availableSize = max(totalSize - splitView.dividerThickness, 0)

            guard availableSize > 0 else { return }

            if let firstSubview = splitView.arrangedSubviews.first {
                let dividerPosition = splitState.orientation == .horizontal
                    ? firstSubview.frame.width
                    : firstSubview.frame.height

                var normalizedPosition = dividerPosition / availableSize

                // Never persist a fully-collapsed pane ratio. (This can happen if we ever
                // see a transient 0-sized layout during a drag or structural update.)
                let minNormalized = min(0.5, TabBarMetrics.minimumPaneWidth / availableSize)
                let maxNormalized = 1 - minNormalized
                normalizedPosition = max(minNormalized, min(maxNormalized, normalizedPosition))

                // Snap to 0.5 if very close (prevents pixel-rounding drift)
                if abs(normalizedPosition - 0.5) < 0.01 {
                    normalizedPosition = 0.5
                }

                // Check if drag ended (mouse up)
                let wasDragging = isDragging && leftDown
                if let event = NSApp.currentEvent, event.type == .leftMouseUp {
                    isDragging = false
                }

                // Only update the model when the user is actively dragging. For other resizes
                // (window resizes, view reparenting, pane↔split structural updates), the model's
                // dividerPosition should remain stable; syncPosition() will keep the view aligned.
                guard wasDragging else {
                    let statePosition = self.splitState.dividerPosition
                    // Re-assert on the next runloop turn to avoid recursive NSSplitView resize callbacks.
                    DispatchQueue.main.async { [weak self, weak splitView] in
                        guard let self, let splitView else { return }
                        self.syncPosition(statePosition, in: splitView)
                    }
                    self.onGeometryChange?(false)
                    return
                }

                Task { @MainActor in
                    self.splitState.dividerPosition = normalizedPosition
                    self.lastAppliedPosition = normalizedPosition
                    // Notify geometry change with drag state
                    self.onGeometryChange?(wasDragging)
                }
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Allow edge positions during animation
            guard !isAnimating else { return proposedMinimumPosition }
            return max(proposedMinimumPosition, TabBarMetrics.minimumPaneWidth)
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            // Allow edge positions during animation
            guard !isAnimating else { return proposedMaximumPosition }
            let totalSize = splitState.orientation == .horizontal
                ? splitView.bounds.width
                : splitView.bounds.height
            return min(proposedMaximumPosition, totalSize - splitView.dividerThickness - TabBarMetrics.minimumPaneWidth)
        }
    }
}
