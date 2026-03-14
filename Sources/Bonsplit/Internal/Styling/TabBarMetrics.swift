import Foundation

/// Sizing and spacing constants for the tab bar (following macOS HIG)
public enum TabBarMetrics {
    // MARK: - Tab Bar

    public static let barHeight: CGFloat = 30
    public static let barPadding: CGFloat = 0

    // MARK: - Individual Tabs

    public static let tabHeight: CGFloat = 30
    public static let tabMinWidth: CGFloat = 48
    public static let tabMaxWidth: CGFloat = 220
    public static let tabCornerRadius: CGFloat = 0
    public static let tabHorizontalPadding: CGFloat = 6
    public static let tabSpacing: CGFloat = 0
    public static let activeIndicatorHeight: CGFloat = 2

    // MARK: - Tab Content

    public static let iconSize: CGFloat = 14
    public static let titleFontSize: CGFloat = 11
    public static let closeButtonSize: CGFloat = 16
    public static let closeIconSize: CGFloat = 9
    public static let dirtyIndicatorSize: CGFloat = 8
    public static let notificationBadgeSize: CGFloat = 6
    public static let contentSpacing: CGFloat = 6

    // MARK: - Drop Indicator

    public static let dropIndicatorWidth: CGFloat = 2
    public static let dropIndicatorHeight: CGFloat = 20

    // MARK: - Split View

    public static let minimumPaneWidth: CGFloat = 100
    public static let minimumPaneHeight: CGFloat = 100
    public static let dividerThickness: CGFloat = 1

    // MARK: - Animations

    public static let selectionDuration: Double = 0.15
    public static let closeDuration: Double = 0.2
    public static let reorderDuration: Double = 0.3
    public static let reorderBounce: Double = 0.15
    public static let hoverDuration: Double = 0.1

    // MARK: - Split Animations (120fps via CADisplayLink)

    /// Duration for split entry animation (fast and snappy like Hyprland)
    public static let splitAnimationDuration: Double = 0.15
}
