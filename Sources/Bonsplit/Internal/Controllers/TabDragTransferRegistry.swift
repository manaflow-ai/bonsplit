import AppKit
import Foundation
import UniformTypeIdentifiers

/// Process-local capability store for transfers owned by live native tab drags.
@MainActor
final class TabDragTransferRegistry {
    /// AppKit's drag pasteboard is process-wide, so controllers share one registry
    /// to support cross-window moves while still allowing isolated registries in tests.
    static let process = TabDragTransferRegistry()

    static let pasteboardType = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)

    private var transfers: [UUID: TabTransferData] = [:]

    func register(_ transfer: TabTransferData) -> (token: UUID, pasteboardItem: NSPasteboardItem)? {
        let token = UUID()
        let item = NSPasteboardItem()
        guard item.setString(token.uuidString, forType: Self.pasteboardType) else {
            return nil
        }
        transfers[token] = transfer
        return (token, item)
    }

    func resolve(from pasteboard: NSPasteboard) -> TabTransferData? {
        guard let token = token(from: pasteboard) else { return nil }
        return transfers[token]
    }

    func end(token: UUID) {
        transfers[token] = nil
    }

    private func token(from pasteboard: NSPasteboard) -> UUID? {
        guard let value = pasteboard.string(forType: Self.pasteboardType) else {
            return nil
        }
        return UUID(uuidString: value)
    }
}
