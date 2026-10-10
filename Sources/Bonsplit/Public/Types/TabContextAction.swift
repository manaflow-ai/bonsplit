import Foundation

/// Presentation state for a host-provided Fork Conversation tab action.
public enum TabContextForkConversationAvailability: Sendable {
    case hidden
    case refreshing
    case available
}

/// Context menu actions that can be triggered from a tab item.
public enum TabContextAction: String, CaseIterable, Sendable {
    case rename
    case clearName
    case copyIdentifiers
    case close
    case closeToLeft
    case closeToRight
    case closeOthers
    /// Closes every unpinned browser tab in the pane, leaving other tabs open.
    case closeBrowserTabs
    case move
    case moveToNewWorkspace
    case moveToLeftPane
    case moveToRightPane
    case newTerminalToRight
    case newBrowserToRight
    case reload
    case duplicate
    case toggleAudioMute
    case togglePin
    case markAsRead
    case markAsUnread
    case toggleZoom
    case toggleFullWidthTab
    case disconnectRemote
    case forkConversation
    case forkConversationRight
    case forkConversationLeft
    case forkConversationTop
    case forkConversationBottom
    case forkConversationNewTab
    case forkConversationNewWorkspace
    /// Makes this device's window set the shared terminal's size.
    case sizeToMyWindow
    /// Sets the shared terminal's sizing mode to ``TabPresence/SizeMode/latest``.
    case sizeModeLatest
    /// Sets the sizing mode to ``TabPresence/SizeMode/smallest``.
    case sizeModeSmallest
    /// Sets the sizing mode to ``TabPresence/SizeMode/largest``.
    case sizeModeLargest
    /// Sets the sizing mode to ``TabPresence/SizeMode/priority``.
    case sizeModePriority
    /// Sets the sizing mode to ``TabPresence/SizeMode/fixed``.
    case sizeModeFixed
    /// Opens the host's terminal size panel, or closes it when it is already
    /// open for this tab. Sent by the presence accessory.
    case toggleSizePanel
    /// Asks the host to disconnect every other client of the terminal.
    case disconnectOtherClients

    public static let defaultForkConversationDestination: TabContextAction = .forkConversationRight

    /// The context action that selects a sizing mode.
    ///
    /// - Parameter mode: The sizing mode.
    /// - Returns: The matching `sizeMode*` action.
    public static func sizeMode(_ mode: TabPresence.SizeMode) -> TabContextAction {
        switch mode {
        case .latest: return .sizeModeLatest
        case .smallest: return .sizeModeSmallest
        case .largest: return .sizeModeLargest
        case .priority: return .sizeModePriority
        case .fixed: return .sizeModeFixed
        }
    }

    /// The sizing mode this action selects, or nil for any other action.
    public var sizeMode: TabPresence.SizeMode? {
        switch self {
        case .sizeModeLatest: return .latest
        case .sizeModeSmallest: return .smallest
        case .sizeModeLargest: return .largest
        case .sizeModePriority: return .priority
        case .sizeModeFixed: return .fixed
        default: return nil
        }
    }

    public var isForkConversationDestination: Bool {
        switch self {
        case .forkConversationRight,
             .forkConversationLeft,
             .forkConversationTop,
             .forkConversationBottom,
             .forkConversationNewTab,
             .forkConversationNewWorkspace:
            return true
        default:
            return false
        }
    }
}

public struct TabContextMoveDestination: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let isEnabled: Bool

    public init(id: String, title: String, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
    }
}
