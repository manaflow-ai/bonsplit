import AppKit

/// Drop zone within a native Bonsplit pane.
public enum DropZone: Equatable, Sendable {
    case center
    case left
    case right
    case top
    case bottom

    var orientation: SplitOrientation? {
        switch self {
        case .left, .right: .horizontal
        case .top, .bottom: .vertical
        case .center: nil
        }
    }

    var insertsFirst: Bool {
        switch self {
        case .left, .top: true
        case .center, .right, .bottom: false
        }
    }
}

/// Pure drop-routing policy shared by native views and tests.
enum UnifiedPaneDropDelegate {
    static func acceptsFileDrop(
        zone: DropZone,
        hasExternalFileDropHandler: Bool,
        hasLegacyFileDropHandler: Bool
    ) -> Bool {
        if hasExternalFileDropHandler { return true }
        return hasLegacyFileDropHandler && zone == .center
    }

    static func acceptedDropZone(
        _ zone: DropZone,
        isFileDropOnly: Bool,
        hasExternalFileDropHandler: Bool,
        hasLegacyFileDropHandler: Bool
    ) -> DropZone? {
        guard !isFileDropOnly || acceptsFileDrop(
            zone: zone,
            hasExternalFileDropHandler: hasExternalFileDropHandler,
            hasLegacyFileDropHandler: hasLegacyFileDropHandler
        ) else { return nil }
        return zone
    }

    static func isFileDropOnly(hasTabTransfer: Bool, hasFileURL: Bool) -> Bool {
        hasFileURL && !hasTabTransfer
    }

    static func shouldHandleFileDrop(
        hasTabTransfer: Bool,
        hasFileURL: Bool,
        permitsTabTransfer: Bool
    ) -> Bool {
        hasFileURL && (!hasTabTransfer || !permitsTabTransfer)
    }

    static func shouldUseLocalTabDrag(
        hasTabTransfer: Bool,
        hasFileURL: Bool,
        hasLocalTabDrag: Bool
    ) -> Bool {
        hasLocalTabDrag && !isFileDropOnly(hasTabTransfer: hasTabTransfer, hasFileURL: hasFileURL)
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { object in
            if let url = object as? URL { return url.isFileURL ? url : nil }
            if let url = object as? NSURL {
                let value = url as URL
                return value.isFileURL ? value : nil
            }
            return nil
        }
    }

    static func hasReadableFileURLs(
        from pasteboard: NSPasteboard = NSPasteboard(name: .drag)
    ) -> Bool {
        !fileURLs(from: pasteboard).isEmpty
    }
}
