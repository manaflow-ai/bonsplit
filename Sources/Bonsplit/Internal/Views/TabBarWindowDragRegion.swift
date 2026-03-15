import AppKit
import SwiftUI

private func performTabBarStandardDoubleClick(window: NSWindow?) -> Bool {
    guard let window else { return false }

    let globalDefaults = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
    if let action = (globalDefaults["AppleActionOnDoubleClick"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() {
        switch action {
        case "minimize":
            window.miniaturize(nil)
            return true
        case "none":
            return false
        case "maximize", "zoom":
            window.zoom(nil)
            return true
        default:
            break
        }
    }

    if let miniaturizeOnDoubleClick = globalDefaults["AppleMiniaturizeOnDoubleClick"] as? Bool,
       miniaturizeOnDoubleClick {
        window.miniaturize(nil)
        return true
    }

    window.zoom(nil)
    return true
}

struct TabBarWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TabBarWindowDragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class TabBarWindowDragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2, performTabBarStandardDoubleClick(window: window) {
            return
        }

        guard let window else {
            super.mouseDown(with: event)
            return
        }

        let previousMovableState = window.isMovable
        if !previousMovableState {
            window.isMovable = true
        }
        defer {
            if window.isMovable != previousMovableState {
                window.isMovable = previousMovableState
            }
        }

        window.performDrag(with: event)
    }
}
