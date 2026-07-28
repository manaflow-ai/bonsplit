import AppKit

/// Owns one explicit window-drag mouse sequence in screen coordinates.
///
/// AppKit's native `performDrag(with:)` does not reliably move child windows.
/// Explicit chrome uses this session so the same mouse sequence works for both
/// ordinary windows and windows attached to a workspace owner.
@MainActor
public struct BonsplitWindowDragSession {
    private var windowIdentifier: ObjectIdentifier?
    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?

    public init() {}

    public var isActive: Bool {
        windowIdentifier != nil
    }

    public mutating func begin(with event: NSEvent, in window: NSWindow) {
        window.makeKey()
        windowIdentifier = ObjectIdentifier(window)
        initialMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        initialWindowOrigin = window.frame.origin
    }

    @discardableResult
    public mutating func update(with event: NSEvent, in window: NSWindow) -> NSPoint? {
        guard windowIdentifier == ObjectIdentifier(window),
              let initialMouseLocation,
              let initialWindowOrigin else {
            return nil
        }

        let mouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        var proposedFrame = window.frame
        proposedFrame.origin = Self.movedOrigin(
            initialWindowOrigin: initialWindowOrigin,
            initialMouseLocation: initialMouseLocation,
            currentMouseLocation: mouseLocation
        )
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? window.screen
        let constrainedFrame = window.constrainFrameRect(proposedFrame, to: targetScreen)
        window.setFrameOrigin(constrainedFrame.origin)
        return constrainedFrame.origin
    }

    public mutating func end() {
        windowIdentifier = nil
        initialMouseLocation = nil
        initialWindowOrigin = nil
    }

    public nonisolated static func movedOrigin(
        initialWindowOrigin: NSPoint,
        initialMouseLocation: NSPoint,
        currentMouseLocation: NSPoint
    ) -> NSPoint {
        NSPoint(
            x: initialWindowOrigin.x + currentMouseLocation.x - initialMouseLocation.x,
            y: initialWindowOrigin.y + currentMouseLocation.y - initialMouseLocation.y
        )
    }
}
