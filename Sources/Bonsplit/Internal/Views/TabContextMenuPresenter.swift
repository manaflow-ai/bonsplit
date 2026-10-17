import AppKit
import SwiftUI

struct TabContextMenuSnapshot {
    let tabId: UUID
    let state: TabContextMenuState
    let moveDestinationsProvider: () -> [TabContextMoveDestination]
    let colorOptionsProvider: () -> [TabColorOption]
    /// The tab's current accent hex, used to check the matching palette row.
    let currentColorHex: String?
    let forkConversationAvailabilityProvider: () -> TabContextForkConversationAvailability
    let forkConversationAvailabilityRefreshHandler: @MainActor () async -> Void

    init(
        tabId: UUID,
        state: TabContextMenuState,
        moveDestinationsProvider: @escaping () -> [TabContextMoveDestination],
        colorOptionsProvider: @escaping () -> [TabColorOption] = { [] },
        currentColorHex: String? = nil,
        forkConversationAvailabilityProvider: @escaping () -> TabContextForkConversationAvailability,
        forkConversationAvailabilityRefreshHandler: @escaping @MainActor () async -> Void = {}
    ) {
        self.tabId = tabId
        self.state = state
        self.moveDestinationsProvider = moveDestinationsProvider
        self.colorOptionsProvider = colorOptionsProvider
        self.currentColorHex = currentColorHex
        self.forkConversationAvailabilityProvider = forkConversationAvailabilityProvider
        self.forkConversationAvailabilityRefreshHandler = forkConversationAvailabilityRefreshHandler
    }
}

final class TabContextMenuActionTarget: NSObject {
    var onContextAction: ((TabContextAction) -> Void)?
    var onMoveDestination: ((String) -> Void)?
    /// Receives the chosen accent hex, or nil when the user clears the color.
    var onColorSelection: ((String?) -> Void)?

    @objc func performContextAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = TabContextAction(rawValue: rawValue) else {
            return
        }
        onContextAction?(action)
    }

    @objc func performMoveDestination(_ sender: NSMenuItem) {
        guard let destinationId = sender.representedObject as? String else { return }
        onMoveDestination?(destinationId)
    }

    /// A nil `representedObject` is the Clear Color row.
    @objc func performColorSelection(_ sender: NSMenuItem) {
        onColorSelection?(sender.representedObject as? String)
    }
}

@MainActor
final class TabContextMenu: NSMenu, NSMenuDelegate {
    let snapshot: TabContextMenuSnapshot
    private(set) var forkConversationAvailability: TabContextForkConversationAvailability
    private var refreshTask: Task<Void, Never>?

    init(
        snapshot: TabContextMenuSnapshot,
        forkConversationAvailability: TabContextForkConversationAvailability
    ) {
        self.snapshot = snapshot
        self.forkConversationAvailability = forkConversationAvailability
        super.init(title: "")
        autoenablesItems = false
        delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        reevaluateForkConversationAvailability()
    }

    func menuWillOpen(_ menu: NSMenu) {
        reevaluateForkConversationAvailability()
        guard forkConversationAvailability == .refreshing,
              refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            await self?.resolveRefreshingForkConversationAvailability()
            self?.refreshTask = nil
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func resolveRefreshingForkConversationAvailability() async {
        guard forkConversationAvailability == .refreshing else { return }
        await snapshot.forkConversationAvailabilityRefreshHandler()
        guard !Task.isCancelled else { return }
        reevaluateForkConversationAvailability()
    }

    private func reevaluateForkConversationAvailability() {
        let availability = snapshot.forkConversationAvailabilityProvider()
        forkConversationAvailability = availability
        TabContextMenuBuilder.updateForkConversationAvailability(availability, in: self)
    }
}

struct TabContextMenuPresenter: NSViewRepresentable {
    let snapshot: TabContextMenuSnapshot
    let onContextAction: (TabContextAction) -> Void
    let onMoveDestination: (String) -> Void
    let onColorSelection: (String?) -> Void

    @MainActor
    final class Coordinator {
        var snapshot: TabContextMenuSnapshot
        let actionTarget = TabContextMenuActionTarget()
        weak var view: NSView?
        var monitor: Any?

        init(snapshot: TabContextMenuSnapshot) {
            self.snapshot = snapshot
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func presentMenu(at point: NSPoint, in view: NSView) {
            let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: actionTarget)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(snapshot: snapshot)
        coordinator.actionTarget.onContextAction = onContextAction
        coordinator.actionTarget.onMoveDestination = onMoveDestination
        coordinator.actionTarget.onColorSelection = onColorSelection
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        context.coordinator.view = view

        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak coordinator] event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            guard let coordinator, let view = coordinator.view, let window = view.window else { return event }
            guard event.window === window else { return event }

            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return event }

            coordinator.presentMenu(at: point, in: view)
            return nil
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.snapshot = snapshot
        context.coordinator.actionTarget.onContextAction = onContextAction
        context.coordinator.actionTarget.onMoveDestination = onMoveDestination
        context.coordinator.actionTarget.onColorSelection = onColorSelection
    }
}
