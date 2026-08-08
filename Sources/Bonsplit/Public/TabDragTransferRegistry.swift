import AppKit
import Foundation
import UniformTypeIdentifiers

/// Process-local capability store shared by tab-drag sources and destinations.
@MainActor
public final class TabDragTransferRegistry {
    /// The registry used by Bonsplit controllers created with the default initializer.
    ///
    /// AppKit exposes one drag pasteboard for the process, so the default registry
    /// is process-wide as well. Construct a separate registry for isolated tests.
    public static let process = TabDragTransferRegistry()

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
        let item = NSPasteboardItem()
        guard item.setString(token.uuidString, forType: Self.pasteboardType) else {
            return nil
        }
        let registration = TabDragTransferRegistration(
            token: token,
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

    private func token(from pasteboard: NSPasteboard) -> UUID? {
        guard let value = pasteboard.string(forType: Self.pasteboardType) else {
            return nil
        }
        return UUID(uuidString: value)
    }

    private func compactReleasedRegistrations() {
        transfers = transfers.filter { $0.value.lifetime != nil }
    }
}
