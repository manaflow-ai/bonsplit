import Foundation

/// An outer edge of the complete split tree.
public enum RootSplitEdge: Sendable, Equatable {
    /// The full-height leading edge.
    case left
    /// The full-height trailing edge.
    case right
    /// The full-width top edge.
    case above
    /// The full-width bottom edge.
    case below
}

extension RootSplitEdge {
    var orientation: SplitOrientation {
        switch self {
        case .left, .right: .horizontal
        case .above, .below: .vertical
        }
    }

    var insertsFirst: Bool {
        switch self {
        case .left, .above: true
        case .right, .below: false
        }
    }
}
