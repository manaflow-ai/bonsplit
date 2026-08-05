import AppKit

struct TabContextMenuSnapshot {
    let tabId: UUID
    let state: TabContextMenuState
    let moveDestinationsProvider: () -> [TabContextMoveDestination]
    let forkConversationAvailabilityProvider: () -> TabContextForkConversationAvailability
    let forkConversationAvailabilityRefreshHandler: @MainActor () async -> Void

    init(
        tabId: UUID,
        state: TabContextMenuState,
        moveDestinationsProvider: @escaping () -> [TabContextMoveDestination],
        forkConversationAvailabilityProvider: @escaping () -> TabContextForkConversationAvailability,
        forkConversationAvailabilityRefreshHandler: @escaping @MainActor () async -> Void = {}
    ) {
        self.tabId = tabId
        self.state = state
        self.moveDestinationsProvider = moveDestinationsProvider
        self.forkConversationAvailabilityProvider = forkConversationAvailabilityProvider
        self.forkConversationAvailabilityRefreshHandler = forkConversationAvailabilityRefreshHandler
    }
}

final class TabContextMenuActionTarget: NSObject {
    var onContextAction: ((TabContextAction) -> Void)?
    var onMoveDestination: ((String) -> Void)?

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
}

@MainActor
final class TabContextMenu: NSMenu, NSMenuDelegate {
    let snapshot: TabContextMenuSnapshot
    private let actionTarget: TabContextMenuActionTarget
    private(set) var forkConversationAvailability: TabContextForkConversationAvailability
    private var refreshTask: Task<Void, Never>?

    init(
        snapshot: TabContextMenuSnapshot,
        forkConversationAvailability: TabContextForkConversationAvailability,
        actionTarget: TabContextMenuActionTarget
    ) {
        self.snapshot = snapshot
        self.forkConversationAvailability = forkConversationAvailability
        self.actionTarget = actionTarget
        super.init(title: "")
        autoenablesItems = false
        delegate = self
    }

    @available(*, unavailable)
    nonisolated override init(title: String) {
        fatalError("Use init(snapshot:forkConversationAvailability:actionTarget:)")
    }

    @available(*, unavailable)
    nonisolated required init(coder: NSCoder) {
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
