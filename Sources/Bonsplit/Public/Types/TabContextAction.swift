import Foundation

/// Context menu actions that can be triggered from a tab item.
public enum TabContextAction: String, CaseIterable, Sendable {
    case rename
    case closeToLeft
    case closeToRight
    case closeOthers
    case newTerminalToRight
    case newBrowserToRight
    case reload
    case duplicate
    case togglePin
    case markAsUnread
}
