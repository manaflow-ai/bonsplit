import AppKit
@testable import Bonsplit
import Testing

@Suite("Native tab drag capabilities")
@MainActor
struct TabDragTransferRegistryTests {
    @Test("Pasteboard publishes only an opaque capability")
    func pasteboardDoesNotExposeSerializedTabMetadata() throws {
        let registry = TabDragTransferRegistry()
        let controller = makeController(registry: registry)
        let pane = try #require(controller.internalController.focusedPane)
        let tab = try #require(pane.selectedTab)
        let registration = try #require(
            registry.register(TabTransferData(tab: tab, sourcePaneId: pane.id.id))
        )
        let value = try #require(
            registration.pasteboardItem.string(forType: TabDragTransferRegistry.pasteboardType)
        )

        #expect(UUID(uuidString: value) != nil)
        #expect(!value.contains(tab.title))
        #expect(!value.contains(pane.id.id.uuidString))
    }

    @Test("A registered capability routes across controllers")
    func registeredCapabilityRoutesAcrossControllers() throws {
        let sourceController = makeController()
        let targetController = makeController()
        let registry = sourceController.internalController.tabDragTransferRegistry
        let sourcePane = try #require(sourceController.internalController.focusedPane)
        let sourceTab = try #require(sourcePane.selectedTab)
        let targetPane = try #require(targetController.internalController.focusedPane)
        let registration = try #require(
            registry.register(TabTransferData(tab: sourceTab, sourcePaneId: sourcePane.id.id))
        )
        defer { registry.end(token: registration.token) }
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
            registry.register(TabTransferData(tab: sourceTab, sourcePaneId: sourcePane.id.id))
        )
        let source = TabDragSessionSource(
            generation: generation,
            transferToken: registration.token,
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
