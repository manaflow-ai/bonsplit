import Foundation

/// Sizing and spacing constants for the tab bar (following macOS HIG)
enum TabBarMetrics {
    // MARK: - Tab Bar

    static let barHeight: CGFloat = 30
    static let barPadding: CGFloat = 0

    // MARK: - Individual Tabs

    static let tabHeight: CGFloat = 30
    static let tabMinWidth: CGFloat = 48
    static let tabMaxWidth: CGFloat = 220
    static let tabCornerRadius: CGFloat = 0
    static let tabHorizontalPadding: CGFloat = 6
    static let tabSpacing: CGFloat = 0
    static let activeIndicatorHeight: CGFloat = 1.5
    static let activeIndicatorTrailingInset: CGFloat = 1
    static let selectedTabLeftSeparatorBottomInset: CGFloat = 1
    static let tabColorRailWidth: CGFloat = 3

    // MARK: - Tab Content

    static let iconSize: CGFloat = 14
    static let titleFontSize: CGFloat = 11
    static let closeButtonSize: CGFloat = 16
    static let closeIconSize: CGFloat = 9
    static let dirtyIndicatorSize: CGFloat = 8
    static let notificationBadgeSize: CGFloat = 6
    static let contentSpacing: CGFloat = 6

    // MARK: - Drop Indicator

    static let dropIndicatorWidth: CGFloat = 2
    static let dropIndicatorHeight: CGFloat = 20

    // MARK: - Split View

    static let minimumPaneWidth: CGFloat = 100
    static let minimumPaneHeight: CGFloat = 100
    static let dividerThickness: CGFloat = 1

    /// Lower bound for a host-configured divider thickness. Zero keeps the
    /// divider hit-testable while letting hosts hide the painted bar.
    static let minimumDividerThickness: CGFloat = 0
    /// Upper bound for a host-configured divider thickness. Guards against
    /// runaway values that would swallow pane content.
    static let maximumDividerThickness: CGFloat = 12

    /// Clamp a host-supplied divider thickness into a usable range, falling
    /// back to the hairline default for non-finite input.
    static func resolvedDividerThickness(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return dividerThickness }
        return min(max(value, minimumDividerThickness), maximumDividerThickness)
    }

    // MARK: - Animations

    static let selectionDuration: Double = 0.15
    static let closeDuration: Double = 0.2
    static let reorderDuration: Double = 0.3
    static let reorderBounce: Double = 0.15
    static let hoverDuration: Double = 0.1

    // MARK: - Split Animations (120fps via CADisplayLink)

    /// Duration for split entry animation (fast and snappy like Hyprland)
    static let splitAnimationDuration: Double = 0.15
}
