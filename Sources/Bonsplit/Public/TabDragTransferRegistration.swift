import AppKit
import Foundation

/// Immutable identity retained by a live drag source or item provider.
///
/// The type is safe to send because it carries no mutable state; the registry
/// only compares its object identity through a weak reference.
final class TabDragTransferLifetime: @unchecked Sendable {}

/// A lease that publishes one opaque tab-drag capability.
///
/// Retain this value until the native drag source completes. Releasing the
/// lease makes residual pasteboard data unresolvable even when the pasteboard
/// still advertises Bonsplit's transfer type.
@MainActor
public final class TabDragTransferRegistration {
    let token: UUID
    let lifetime = TabDragTransferLifetime()
    private let capabilityValue: String

    /// A pasteboard writer for AppKit-native dragging sessions.
    public let pasteboardItem: NSPasteboardItem

    init(token: UUID, capabilityValue: String, pasteboardItem: NSPasteboardItem) {
        self.token = token
        self.capabilityValue = capabilityValue
        self.pasteboardItem = pasteboardItem
    }

    /// Publishes this capability through a SwiftUI drag's item provider.
    ///
    /// The provider retains the lease identity for as long as it can vend the
    /// capability, so releasing the caller's registration does not invalidate
    /// an in-flight SwiftUI drag.
    ///
    /// - Parameter itemProvider: The provider returned from a SwiftUI drag source.
    public func register(with itemProvider: NSItemProvider) {
        let capabilityData = Data(capabilityValue.utf8)
        let lifetime = lifetime
        itemProvider.registerDataRepresentation(
            forTypeIdentifier: TabDragTransferRegistry.pasteboardType.rawValue,
            visibility: .ownProcess
        ) { completion in
            withExtendedLifetime(lifetime) {
                completion(capabilityData, nil)
            }
            return nil
        }
    }

    /// Writes this capability to a pasteboard without clearing its other types.
    ///
    /// - Parameter pasteboard: The destination pasteboard.
    /// - Returns: `true` when AppKit accepted the capability value.
    @discardableResult
    public func write(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.addTypes([TabDragTransferRegistry.pasteboardType], owner: nil)
        return pasteboard.setString(
            capabilityValue,
            forType: TabDragTransferRegistry.pasteboardType
        )
    }
}
