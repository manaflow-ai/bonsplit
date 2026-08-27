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
        var finishSource: (() -> Void)?

        init(lifetime: TabDragTransferLifetime, transfer: TabDragTransfer) {
            self.lifetime = lifetime
            self.transfer = transfer
        }
    }

    private final class ResolutionCache {
        let pasteboardName: NSPasteboard.Name
        let changeCount: Int
        let mutationGeneration: UInt64
        weak var lifetime: TabDragTransferLifetime?
        let transfer: TabDragTransfer?

        init(
            pasteboardName: NSPasteboard.Name,
            changeCount: Int,
            mutationGeneration: UInt64,
            lifetime: TabDragTransferLifetime?,
            transfer: TabDragTransfer?
        ) {
            self.pasteboardName = pasteboardName
            self.changeCount = changeCount
            self.mutationGeneration = mutationGeneration
            self.lifetime = lifetime
            self.transfer = transfer
        }
    }

    private typealias TokenResolver = @MainActor (NSPasteboard) -> UUID?

    private var transfers: [UUID: Entry] = [:]
    private var mutationGeneration: UInt64 = 0
    private var resolutionCache: ResolutionCache?
    private let tokenResolver: TokenResolver

    /// Creates an empty capability registry.
    public init() {
        tokenResolver = Self.decodeToken
    }

    /// Creates a registry with an injected token decoder for package-level tests.
    init(tokenResolver: @escaping @MainActor (NSPasteboard) -> UUID?) {
        self.tokenResolver = tokenResolver
    }

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
        mutationGeneration &+= 1
        return registration
    }

    /// Resolves a live same-process capability from a pasteboard.
    ///
    /// Residual pasteboard data is rejected after its registration is ended or
    /// released, even if the pasteboard continues advertising the transfer type.
    /// Unchanged pasteboard generations use a bounded token/liveness cache; the
    /// payload is decoded again only after a pasteboard or registry mutation,
    /// or when a weak registration lease has expired.
    ///
    /// - Parameter pasteboard: The pasteboard presented by a drag destination.
    /// - Returns: The registered transfer while its source lease remains live.
    public func resolve(from pasteboard: NSPasteboard) -> TabDragTransfer? {
        let pasteboardName = pasteboard.name
        let changeCount = pasteboard.changeCount
        if let resolutionCache,
           resolutionCache.pasteboardName == pasteboardName,
           resolutionCache.changeCount == changeCount,
           resolutionCache.mutationGeneration == mutationGeneration {
            // Positive entries retain only a weak lease, so a released source
            // is still rejected without trusting stale pasteboard identity.
            if resolutionCache.transfer == nil || resolutionCache.lifetime != nil {
                return resolutionCache.transfer
            }
            self.resolutionCache = nil
        }

        var resolvedLifetime: TabDragTransferLifetime?
        let transfer: TabDragTransfer? = {
            guard let token = tokenResolver(pasteboard),
                  let entry = transfers[token] else {
                return nil
            }
            guard let lifetime = entry.lifetime else {
                transfers[token] = nil
                mutationGeneration &+= 1
                return nil
            }
            resolvedLifetime = lifetime
            return entry.transfer
        }()
        resolutionCache = ResolutionCache(
            pasteboardName: pasteboardName,
            changeCount: changeCount,
            mutationGeneration: mutationGeneration,
            lifetime: resolvedLifetime,
            transfer: transfer
        )
        return transfer
    }

    /// Revokes a capability when its retained native drag source completes.
    ///
    /// - Parameter registration: The exact registration returned at drag start.
    public func end(_ registration: TabDragTransferRegistration) {
        guard transfers.removeValue(forKey: registration.token) != nil else { return }
        mutationGeneration &+= 1
    }

    /// Revokes the capability currently written to a completed drag pasteboard.
    ///
    /// - Parameter pasteboard: The pasteboard owned by the completed dragging session.
    public func end(from pasteboard: NSPasteboard) {
        guard let token = tokenResolver(pasteboard),
              transfers.removeValue(forKey: token) != nil else {
            return
        }
        mutationGeneration &+= 1
    }

    /// Finishes the live drag source represented by an accepted drop.
    ///
    /// The capability is revoked before the source callback runs, making this
    /// safe when AppKit later delivers its native drag-ended callback too.
    /// Rejected drops must not call this method.
    ///
    /// - Parameter pasteboard: The pasteboard presented by the accepted drop.
    public func finish(from pasteboard: NSPasteboard) {
        guard let token = tokenResolver(pasteboard),
              let entry = transfers.removeValue(forKey: token) else {
            return
        }
        mutationGeneration &+= 1
        guard entry.lifetime != nil else { return }
        entry.finishSource?()
    }

    /// Attaches the native source lifecycle to a registered capability.
    func attachSourceCompletion(
        to registration: TabDragTransferRegistration,
        _ completion: @escaping () -> Void
    ) {
        guard let entry = transfers[registration.token],
              entry.lifetime === registration.lifetime else {
            return
        }
        entry.finishSource = completion
    }

    private static func decodeToken(from pasteboard: NSPasteboard) -> UUID? {
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
        let compacted = transfers.filter { $0.value.lifetime != nil }
        guard compacted.count != transfers.count else { return }
        transfers = compacted
        mutationGeneration &+= 1
    }
}
