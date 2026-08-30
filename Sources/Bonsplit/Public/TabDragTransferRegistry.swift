import AppKit
import Foundation
import UniformTypeIdentifiers

/// Process-local capability store shared by tab-drag sources and destinations.
@MainActor
public final class TabDragTransferRegistry {
    /// The AppKit pasteboard type that carries opaque tab-drag capabilities.
    public static let pasteboardType = NSPasteboard.PasteboardType(
        UTType.tabTransfer.identifier
    )

    private final class Entry {
        weak var lifetime: TabDragTransferLifetime?
        let transfer: TabDragTransfer

        init(lifetime: TabDragTransferLifetime, transfer: TabDragTransfer) {
            self.lifetime = lifetime
            self.transfer = transfer
        }
    }

    private var transfers: [UUID: Entry] = [:]

    /// Creates an empty capability registry.
    public init() {}

    /// Registers metadata and creates an opaque capability lease for a drag source.
    ///
    /// - Parameter transfer: The tab metadata that same-process destinations may resolve.
    /// - Returns: A lease and pasteboard writer, or `nil` if AppKit rejected the value.
    public func register(
        _ transfer: TabDragTransfer
    ) -> TabDragTransferRegistration? {
        compactReleasedRegistrations()
        let token = UUID()
        guard let capabilityValue = Self.capabilityValue(for: transfer, token: token) else {
            return nil
        }
        let item = NSPasteboardItem()
        guard item.setString(capabilityValue, forType: Self.pasteboardType) else {
            return nil
        }
        let registration = TabDragTransferRegistration(
            token: token,
            capabilityValue: capabilityValue,
            pasteboardItem: item
        )
        transfers[token] = Entry(
            lifetime: registration.lifetime,
            transfer: transfer
        )
        return registration
    }

    /// Resolves a live same-process capability from a pasteboard.
    ///
    /// Residual pasteboard data is rejected after its registration is ended or
    /// released, even if the pasteboard continues advertising the transfer type.
    ///
    /// - Parameter pasteboard: The pasteboard presented by a drag destination.
    /// - Returns: The registered transfer while its source lease remains live.
    public func resolve(from pasteboard: NSPasteboard) -> TabDragTransfer? {
        guard let token = token(from: pasteboard),
              let entry = transfers[token] else {
            return nil
        }
        guard entry.lifetime != nil else {
            transfers[token] = nil
            return nil
        }
        return entry.transfer
    }

    /// Revokes a capability when its retained native drag source completes.
    ///
    /// - Parameter registration: The exact registration returned at drag start.
    public func end(_ registration: TabDragTransferRegistration) {
        transfers[registration.token] = nil
    }

    /// Revokes the capability currently written to a completed drag pasteboard.
    ///
    /// - Parameter pasteboard: The pasteboard owned by the completed dragging session.
    public func end(from pasteboard: NSPasteboard) {
        guard let token = token(from: pasteboard) else { return }
        transfers[token] = nil
    }

    /// Revokes routing for the capability represented by an accepted drop.
    ///
    /// This method deliberately does not finish or release the native source.
    /// AppKit owns the native drag session until it delivers the source's
    /// `draggingSession(_:endedAt:operation:)` callback; that callback must
    /// remain the sole terminal transition. Releasing a source here can leave
    /// CoreDrag/WindowManager in an active drag state when the accepted drop
    /// callback arrives before AppKit's source completion.
    ///
    /// Rejected drops must not call this method.
    ///
    /// - Parameter pasteboard: The pasteboard presented by the accepted drop.
    public func finish(from pasteboard: NSPasteboard) {
        guard let token = token(from: pasteboard),
              let entry = transfers[token] else {
            return
        }
        // Accepted routing is revoked immediately, but the source object and
        // native AppKit session remain owned by their source until `endedAt`.
        // Keep this mutation explicit: a later destination must not resolve the
        // accepted capability a second time while AppKit finishes the source.
        transfers[token] = nil
        guard entry.lifetime != nil else { return }
    }

    private func token(from pasteboard: NSPasteboard) -> UUID? {
        guard let value = pasteboard.string(forType: Self.pasteboardType) else {
            return nil
        }
        if let token = UUID(uuidString: value) {
            return token
        }
        guard let payload = try? JSONDecoder().decode(
            CapabilityPayload.self,
            from: Data(value.utf8)
        ) else {
            return nil
        }
        return payload.token
    }

    /// The pasteboard payload restores the 0.64.22 host drop-target contract:
    /// host apps JSON-parse it for `tab.id`, `tab.kind`, `sourcePaneId`, and
    /// `sourceProcessId` to render pane/browser drop targets, while the
    /// registry resolves the live capability through the embedded `token`.
    /// The tab title (and every other tab field) stays off the pasteboard.
    private struct CapabilityPayload: Codable {
        struct TabInfo: Codable {
            let id: UUID
            let kind: String?
        }

        let token: UUID
        let tab: TabInfo
        let sourcePaneId: UUID
        let sourceProcessId: Int32
    }

    private static func capabilityValue(
        for transfer: TabDragTransfer,
        token: UUID
    ) -> String? {
        let payload = CapabilityPayload(
            token: token,
            tab: CapabilityPayload.TabInfo(
                id: transfer.tab.id.uuid,
                kind: transfer.tab.kind
            ),
            sourcePaneId: transfer.sourcePaneId.id,
            sourceProcessId: Int32(ProcessInfo.processInfo.processIdentifier)
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func compactReleasedRegistrations() {
        transfers = transfers.filter { $0.value.lifetime != nil }
    }
}
