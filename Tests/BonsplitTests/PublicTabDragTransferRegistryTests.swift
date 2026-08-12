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
        #expect(!capability.contains(transfer.tab.title))
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

    @Test("Pasteboard payload keeps the 0.64.22 host drop-target contract")
    func pasteboardPayloadRemainsLegacyJSONDecodable() throws {
        // Regression (manaflow-ai/cmux#10033): host apps resolve pane/browser
        // drop targets by JSON-parsing the tab-transfer pasteboard payload for
        // tab.id, tab.kind, sourcePaneId, and sourceProcessId (the 0.64.22
        // contract). Replacing the payload with a bare token blinded every
        // host drop overlay: drags rendered but no drop targets appeared.
        let registry = TabDragTransferRegistry()
        let tabId = UUID()
        let paneId = PaneID()
        let transfer = TabDragTransfer(
            tab: Tab(id: TabID(uuid: tabId), title: "Private tab title", kind: "terminal"),
            sourcePaneId: paneId
        )
        let registration = try #require(registry.register(transfer))
        let pasteboard = makePasteboard()
        #expect(pasteboard.writeObjects([registration.pasteboardItem]))

        let raw = try #require(
            pasteboard.string(forType: TabDragTransferRegistry.pasteboardType)
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        let tabJSON = try #require(json["tab"] as? [String: Any])
        #expect((tabJSON["id"] as? String).flatMap(UUID.init(uuidString:)) == tabId)
        #expect(tabJSON["kind"] as? String == "terminal")
        #expect(
            (json["sourcePaneId"] as? String).flatMap(UUID.init(uuidString:)) == paneId.id
        )
        #expect(
            (json["sourceProcessId"] as? NSNumber)?.int32Value
                == Int32(ProcessInfo.processInfo.processIdentifier)
        )
        // The tab title must stay off the pasteboard.
        #expect(!raw.contains(transfer.tab.title))
        // The registry still resolves its own capability from the same payload.
        #expect(registry.resolve(from: pasteboard) == transfer)
    }

    @Test("Ending or releasing a registration makes stale pasteboard data inert")
    func capabilityRequiresLiveRegistration() throws {
        let registry = TabDragTransferRegistry()
        let transfer = TabDragTransfer(
            tab: Tab(title: "Ephemeral"),
            sourcePaneId: PaneID()
        )
        let firstRegistration = try #require(
            registry.register(transfer)
        )
        var registration: TabDragTransferRegistration? = firstRegistration
        let pasteboard = makePasteboard()
        #expect(registration?.write(to: pasteboard) == true)
        #expect(registry.resolve(from: pasteboard) == transfer)

        registry.end(try #require(registration))
        #expect(registry.resolve(from: pasteboard) == nil)

        do {
            let secondRegistration = try #require(registry.register(transfer))
            registration = secondRegistration
            pasteboard.clearContents()
            #expect(registration?.write(to: pasteboard) == true)
            #expect(registry.resolve(from: pasteboard) == transfer)
        }

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
