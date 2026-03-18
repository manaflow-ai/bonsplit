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
    let onDoubleClick: (() -> Bool)?

    init(onDoubleClick: (() -> Bool)? = nil) {
        self.onDoubleClick = onDoubleClick
    }

    func makeNSView(context: Context) -> NSView {
        let view = TabBarWindowDragRegionView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? TabBarWindowDragRegionView else { return }
        nsView.onDoubleClick = onDoubleClick
    }
}

final class TabBarWindowDragRegionView: NSView {
    var onDoubleClick: (() -> Bool)?
    private var eventMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { false }

    deinit {
        removeEventMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        removeEventMonitor()
        if window != nil {
            installEventMonitor()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            if onDoubleClick?() == true {
                return
            }
            if performTabBarStandardDoubleClick(window: window) {
                return
            }
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

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleLocalMouseDown(event) ?? event
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func handleLocalMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        guard event.window === window else { return event }

        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }

        if event.clickCount >= 2 {
            if onDoubleClick?() == true {
                return nil
            }

            return performTabBarStandardDoubleClick(window: window) ? nil : event
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
        return nil
    }
}
