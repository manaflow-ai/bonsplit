import AppKit
@testable import Bonsplit
import Testing

@Suite("Native tab drag capabilities")
@MainActor
struct TabDragTransferRegistryTests {
    @Test("Pasteboard payload keeps tab titles private")
    func pasteboardDoesNotExposeSerializedTabMetadata() throws {
        let registry = TabDragTransferRegistry()
        let controller = makeController(registry: registry)
        let pane = try #require(controller.internalController.focusedPane)
        let tab = try #require(pane.selectedTab)
        let registration = try #require(
            registry.register(
                TabDragTransfer(tab: Tab(from: tab), sourcePaneId: pane.id)
            )
        )
        let value = try #require(
            registration.pasteboardItem.string(forType: TabDragTransferRegistry.pasteboardType)
        )

        // Host drop targets parse tab.id / sourcePaneId / sourceProcessId from
        // the payload (the 0.64.22 contract), but titles and every other tab
        // field stay off the pasteboard.
        #expect(!value.contains(tab.title))
        let payload = try #require(
            try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )
        #expect((payload["token"] as? String).flatMap(UUID.init(uuidString:)) != nil)
    }

    @Test("A registered capability routes across controllers")
    func registeredCapabilityRoutesAcrossControllers() throws {
        let registry = TabDragTransferRegistry()
        let sourceController = makeController(registry: registry)
        let targetController = makeController(registry: registry)
        let sourcePane = try #require(sourceController.internalController.focusedPane)
        let sourceTab = try #require(sourcePane.selectedTab)
        let targetPane = try #require(targetController.internalController.focusedPane)
        let registration = try #require(
            registry.register(
                TabDragTransfer(tab: Tab(from: sourceTab), sourcePaneId: sourcePane.id)
            )
        )
        defer { registry.end(registration) }
        let pasteboard = makePasteboard(item: registration.pasteboardItem)
        let handler = makeHandler(controller: targetController, pane: targetPane)
        var receivedRequest: BonsplitController.ExternalTabDropRequest?
        targetController.onExternalTabDrop = { request in
            receivedRequest = request
            return true
        }

        #expect(handler.operation(for: pasteboard) == .move)
        #expect(handler.performDrop(from: pasteboard, at: 0))
        #expect(receivedRequest?.tabId == TabID(id: sourceTab.id))
        #expect(receivedRequest?.sourcePaneId == sourcePane.id)
    }

    @Test("Controllers do not share an implicit capability registry")
    func defaultControllersHaveIsolatedCapabilityRegistries() {
        let firstController = makeController()
        let secondController = makeController()

        #expect(
            firstController.internalController.tabDragTransferRegistry
                !== secondController.internalController.tabDragTransferRegistry
        )
    }

    @Test("An unregistered capability is rejected")
    func unregisteredCapabilityIsRejected() throws {
        let registry = TabDragTransferRegistry()
        let targetController = makeController(registry: registry)
        let targetPane = try #require(targetController.internalController.focusedPane)
        let pasteboard = makePasteboard(token: UUID())
        let handler = makeHandler(controller: targetController, pane: targetPane)
        targetController.onExternalTabDrop = { _ in true }

        #expect(handler.operation(for: pasteboard).isEmpty)
        #expect(!handler.performDrop(from: pasteboard, at: 0))
    }

    @Test("Native source completion revokes its capability")
    func sourceCompletionRevokesCapability() throws {
        let registry = TabDragTransferRegistry()
        let sourceController = makeController(registry: registry)
        let targetController = makeController(registry: registry)
        let sourcePane = try #require(sourceController.internalController.focusedPane)
        let sourceTab = try #require(sourcePane.selectedTab)
        let targetPane = try #require(targetController.internalController.focusedPane)
        let generation = sourceController.internalController.beginTabDrag(sourceTab, from: sourcePane.id)
        let registration = try #require(
            registry.register(
                TabDragTransfer(tab: Tab(from: sourceTab), sourcePaneId: sourcePane.id)
            )
        )
        let source = TabDragSessionSource(
            generation: generation,
            transferRegistration: registration,
            transferRegistry: registry,
            controller: sourceController.internalController
        )
        let pasteboard = makePasteboard(item: registration.pasteboardItem)
        let handler = makeHandler(controller: targetController, pane: targetPane)
        targetController.onExternalTabDrop = { _ in true }
        #expect(handler.operation(for: pasteboard) == .move)

        source.finishDrag()

        #expect(sourceController.internalController.tabDragSession == nil)
        #expect(handler.operation(for: pasteboard).isEmpty)
    }

    @Test("An accepted cross-controller drop finishes its native source")
    func acceptedCrossControllerDropFinishesNativeSource() throws {
        let registry = TabDragTransferRegistry()
        let sourceController = makeController(registry: registry)
        let targetController = makeController(registry: registry)
        let sourcePane = try #require(sourceController.internalController.focusedPane)
        let sourceTab = try #require(sourcePane.selectedTab)
        let targetPane = try #require(targetController.internalController.focusedPane)
        let generation = sourceController.internalController.beginTabDrag(sourceTab, from: sourcePane.id)
        let registration = try #require(
            registry.register(
                TabDragTransfer(tab: Tab(from: sourceTab), sourcePaneId: sourcePane.id)
            )
        )
        let source = TabDragSessionSource(
            generation: generation,
            transferRegistration: registration,
            transferRegistry: registry,
            controller: sourceController.internalController
        )
        let pasteboard = makePasteboard(item: registration.pasteboardItem)
        let handler = makeHandler(controller: targetController, pane: targetPane)
        targetController.onExternalTabDrop = { _ in true }

        #expect(handler.performDrop(from: pasteboard, at: 0))
        #expect(sourceController.internalController.tabDragSession == nil)
        #expect(handler.operation(for: pasteboard).isEmpty)
        withExtendedLifetime(source) {}
    }

    private func makeController(
        registry: TabDragTransferRegistry? = nil
    ) -> BonsplitController {
        let configuration = BonsplitConfiguration(
            allowTabReordering: true,
            allowCrossPaneTabMove: true,
            newTabPosition: .end
        )
        if let registry {
            return BonsplitController(
                configuration: configuration,
                tabDragTransferRegistry: registry
            )
        }
        return BonsplitController(configuration: configuration)
    }

    private func makeHandler(
        controller: BonsplitController,
        pane: PaneState
    ) -> TabBarDropHandler {
        TabBarDropHandler(
            pane: pane,
            bonsplitController: controller,
            splitViewController: controller.internalController
        )
    }

    private func makePasteboard(item: NSPasteboardItem) -> NSPasteboard {
        let pasteboard = emptyPasteboard()
        #expect(pasteboard.writeObjects([item]))
        return pasteboard
    }

    private func makePasteboard(token: UUID) -> NSPasteboard {
        let pasteboard = emptyPasteboard()
        #expect(
            pasteboard.setString(
                token.uuidString,
                forType: TabDragTransferRegistry.pasteboardType
            )
        )
        return pasteboard
    }

    private func emptyPasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TabDragTransferRegistryTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }
}
