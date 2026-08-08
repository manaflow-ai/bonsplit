import AppKit
import Bonsplit
import Testing

@Suite("Public tab drag transfer capabilities")
@MainActor
struct PublicTabDragTransferRegistryTests {
    @Test("Host producers and consumers share one opaque transfer contract")
    func hostProducerAndConsumerShareOpaqueTransfer() throws {
        let registry = TabDragTransferRegistry()
        let transfer = TabDragTransfer(
            tab: Tab(
                id: TabID(uuid: UUID()),
                title: "Private tab title",
                kind: "terminal"
            ),
            sourcePaneId: PaneID()
        )
        let registration = try #require(registry.register(transfer))
        let pasteboard = makePasteboard()

        #expect(pasteboard.writeObjects([registration.pasteboardItem]))
        #expect(registry.resolve(from: pasteboard) == transfer)

        let capability = try #require(
            pasteboard.string(forType: TabDragTransferRegistry.pasteboardType)
        )
        #expect(UUID(uuidString: capability) != nil)
        #expect(!capability.contains(transfer.tab.title))
        #expect(!capability.contains(transfer.sourcePaneId.id.uuidString))
    }

    @Test("Item providers publish the same capability as AppKit pasteboard writers")
    func itemProviderPublishesRegisteredCapability() throws {
        let registry = TabDragTransferRegistry()
        let transfer = TabDragTransfer(
            tab: Tab(title: "Session", kind: "terminal"),
            sourcePaneId: PaneID()
        )
        let registration = try #require(registry.register(transfer))
        let provider = NSItemProvider()
        let pasteboard = makePasteboard()

        registration.register(with: provider)
        #expect(
            provider.registeredTypeIdentifiers.contains(
                TabDragTransferRegistry.pasteboardType.rawValue
            )
        )
        #expect(registration.write(to: pasteboard))
        #expect(registry.resolve(from: pasteboard) == transfer)
    }

    @Test("Ending or releasing a registration makes stale pasteboard data inert")
    func capabilityRequiresLiveRegistration() throws {
        let registry = TabDragTransferRegistry()
        let transfer = TabDragTransfer(
            tab: Tab(title: "Ephemeral"),
            sourcePaneId: PaneID()
        )
        var registration: TabDragTransferRegistration? = try #require(
            registry.register(transfer)
        )
        let pasteboard = makePasteboard()
        #expect(registration?.write(to: pasteboard) == true)
        #expect(registry.resolve(from: pasteboard) == transfer)

        registry.end(try #require(registration))
        #expect(registry.resolve(from: pasteboard) == nil)

        registration = try #require(registry.register(transfer))
        pasteboard.clearContents()
        #expect(registration?.write(to: pasteboard) == true)
        #expect(registry.resolve(from: pasteboard) == transfer)

        registration = nil
        #expect(registry.resolve(from: pasteboard) == nil)
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PublicTabDragTransferRegistryTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        return pasteboard
    }
}
