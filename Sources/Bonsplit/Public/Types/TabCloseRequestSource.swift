import Foundation

/// Describes the user gesture that requested a tab-strip close.
public enum TabCloseRequestSource: Sendable, Equatable {
    case closeButton
    case middleClick
    case contextMenu
}
