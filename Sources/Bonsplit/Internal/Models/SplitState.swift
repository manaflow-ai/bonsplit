import Foundation
import SwiftUI

/// Direction from which a new split animates in
enum SplitAnimationOrigin {
    case fromFirst   // New pane slides in from start (left/top)
    case fromSecond  // New pane slides in from end (right/bottom)
}

/// State for a split node (branch in the split tree)
@Observable
final class SplitState: Identifiable {
    let id: UUID
    var orientation: SplitOrientation
    var first: SplitNode
    var second: SplitNode
    var dividerPosition: CGFloat  // 0.0 to 1.0

    /// Externally imposed extent, in points, for the FIRST child along the
    /// split axis. While set, layout places the divider at exactly this many
    /// points (clamped to pane minimums) instead of deriving pixels from
    /// `dividerPosition` — hosts that compute exact pane sizes (terminal
    /// grids) lose nothing to normalized-fraction rounding or drift
    /// deadbands. `dividerPosition` is kept mirrored to the applied value so
    /// every fraction reader stays coherent. A user divider drag clears it:
    /// the gesture takes ownership and fraction semantics resume.
    var imposedFirstExtent: CGFloat?
    /// Bumped when the imposed target changes. The view's convergence memo
    /// keys off this so repeated identical plans cannot keep re-arming a
    /// target that AppKit permanently refuses.
    var imposedEpoch: Int = 0
    /// Imperative hook the live split view's coordinator installs so divider
    /// authority changes apply immediately. Routing them through SwiftUI
    /// observation is not reliable for representables: a split whose only
    /// change is an extent update may never get another updateNSView, and its
    /// divider then renders a previous layout until some unrelated event
    /// nudges it. Weakly captured internals; safe to call when stale.
    @ObservationIgnored var syncDividerNow: (() -> Void)?

    /// Animation origin for entry animation (nil = no animation needed)
    var animationOrigin: SplitAnimationOrigin?

    init(
        id: UUID = UUID(),
        orientation: SplitOrientation,
        first: SplitNode,
        second: SplitNode,
        dividerPosition: CGFloat = 0.5,
        animationOrigin: SplitAnimationOrigin? = nil
    ) {
        self.id = id
        self.orientation = orientation
        self.first = first
        self.second = second
        self.dividerPosition = dividerPosition
        self.animationOrigin = animationOrigin
    }
}

extension SplitState: Equatable {
    static func == (lhs: SplitState, rhs: SplitState) -> Bool {
        lhs.id == rhs.id
    }
}
