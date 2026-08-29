import AppKit
@testable import Bonsplit
import SwiftUI
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

    @Test("An accepted drop leaves native source completion to AppKit")
    func acceptedCrossControllerDropWaitsForNativeSourceCompletion() throws {
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
        // Accepting a destination only revokes routing. The native source must
        // remain retained and its `endedAt` callback is the sole terminal
        // transition, otherwise AppKit can be left in an active drag state.
        #expect(sourceController.internalController.tabDragSession != nil)
        #expect(handler.operation(for: pasteboard).isEmpty)

        source.finishDrag()
        #expect(sourceController.internalController.tabDragSession == nil)
        withExtendedLifetime(source) {}
    }

    @Test("A failed local pane move keeps its native source live")
    func failedLocalPaneMoveKeepsNativeSourceLive() throws {
        let fixture = try makeLocalPaneDropFixture()
        defer { fixture.source.finishDrag() }
        let delegate = makePaneDropDelegate(
            controller: fixture.controller,
            pane: fixture.targetPane
        )
        #expect(fixture.controller.closeTab(TabID(id: fixture.dragSession.tab.id)))

        let handled = withExtendedLifetime(fixture.source) {
            delegate.performLocalTabDrop(
                fixture.dragSession,
                zone: .center,
                pasteboard: fixture.pasteboard
            )
        }

        #expect(!handled)
        #expect(
            fixture.controller.internalController.tabDragSession?.generation
                == fixture.dragSession.generation
        )
        #expect(fixture.registry.resolve(from: fixture.pasteboard) != nil)
    }

    @Test("A failed local pane split keeps its native source live")
    func failedLocalPaneSplitKeepsNativeSourceLive() throws {
        let fixture = try makeLocalPaneDropFixture()
        defer { fixture.source.finishDrag() }
        let delegate = makePaneDropDelegate(
            controller: fixture.controller,
            pane: fixture.targetPane
        )
        fixture.controller.configuration.allowSplits = false

        let handled = withExtendedLifetime(fixture.source) {
            delegate.performLocalTabDrop(
                fixture.dragSession,
                zone: .left,
                pasteboard: fixture.pasteboard
            )
        }

        #expect(!handled)
        #expect(
            fixture.controller.internalController.tabDragSession?.generation
                == fixture.dragSession.generation
        )
        #expect(fixture.registry.resolve(from: fixture.pasteboard) != nil)
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

    private func makePaneDropDelegate(
        controller: BonsplitController,
        pane: PaneState
    ) -> UnifiedPaneDropDelegate {
        UnifiedPaneDropDelegate(
            size: CGSize(width: 400, height: 300),
            pane: pane,
            controller: controller.internalController,
            bonsplitController: controller,
            activeDropZone: .constant(nil),
            dropLifecycle: .constant(.hovering)
        )
    }

    private func makeLocalPaneDropFixture() throws -> LocalPaneDropFixture {
        let registry = TabDragTransferRegistry()
        let controller = makeController(registry: registry)
        let sourcePane = try #require(controller.internalController.focusedPane)
        let draggedTab = try #require(sourcePane.selectedTab)
        _ = try #require(controller.createTab(title: "Source survivor", inPane: sourcePane.id))
        let targetPaneId = try #require(
            controller.splitPane(sourcePane.id, orientation: .horizontal)
        )
        let targetPane = try #require(
            controller.internalController.paneState(for: targetPaneId)
        )
        let generation = controller.internalController.beginTabDrag(
            draggedTab,
            from: sourcePane.id
        )
        let dragSession = try #require(controller.internalController.tabDragSession)
        let registration = try #require(
            registry.register(
                TabDragTransfer(tab: Tab(from: draggedTab), sourcePaneId: sourcePane.id)
            )
        )
        let source = TabDragSessionSource(
            generation: generation,
            transferRegistration: registration,
            transferRegistry: registry,
            controller: controller.internalController
        )
        let pasteboard = makePasteboard(item: registration.pasteboardItem)
        return LocalPaneDropFixture(
            registry: registry,
            controller: controller,
            targetPane: targetPane,
            dragSession: dragSession,
            source: source,
            pasteboard: pasteboard
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

    private struct LocalPaneDropFixture {
        let registry: TabDragTransferRegistry
        let controller: BonsplitController
        let targetPane: PaneState
        let dragSession: TabDragSession
        let source: TabDragSessionSource
        let pasteboard: NSPasteboard
    }
}
