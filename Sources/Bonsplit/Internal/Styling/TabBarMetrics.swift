import Foundation

/// Sizing and spacing constants for the tab bar (following macOS HIG)
enum TabBarMetrics {
    // MARK: - Tab Bar

    static func barHeight(_ scale: CGFloat) -> CGFloat { 30 * scale }
    static let barPadding: CGFloat = 0

    // MARK: - Individual Tabs

    static func tabHeight(_ scale: CGFloat) -> CGFloat { 30 * scale }
    static func tabMinWidth(_ scale: CGFloat) -> CGFloat { 48 * scale }
    static func tabMaxWidth(_ scale: CGFloat) -> CGFloat { 220 * scale }
    static let tabCornerRadius: CGFloat = 0
    static func tabHorizontalPadding(_ scale: CGFloat) -> CGFloat { 6 * scale }
    static let tabSpacing: CGFloat = 0
    static func activeIndicatorHeight(_ scale: CGFloat) -> CGFloat { 2 * scale }

    // MARK: - Tab Content

    static func iconSize(_ scale: CGFloat) -> CGFloat { 14 * scale }
    static func titleFontSize(_ scale: CGFloat) -> CGFloat { 11 * scale }
    static func closeButtonSize(_ scale: CGFloat) -> CGFloat { 16 * scale }
    static func closeIconSize(_ scale: CGFloat) -> CGFloat { 9 * scale }
    static func dirtyIndicatorSize(_ scale: CGFloat) -> CGFloat { 8 * scale }
    static func notificationBadgeSize(_ scale: CGFloat) -> CGFloat { 6 * scale }
    static func contentSpacing(_ scale: CGFloat) -> CGFloat { 6 * scale }

    // MARK: - Drop Indicator

    static func dropIndicatorWidth(_ scale: CGFloat) -> CGFloat { 2 * scale }
    static func dropIndicatorHeight(_ scale: CGFloat) -> CGFloat { 20 * scale }

    // MARK: - Split View

    static let minimumPaneWidth: CGFloat = 100
    static let minimumPaneHeight: CGFloat = 100
    static let dividerThickness: CGFloat = 1

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
