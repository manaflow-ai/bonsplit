import SwiftUI
import AppKit

/// Native macOS colors for the tab bar
enum TabBarColors {
    private enum Constants {
        static let darkTextAlpha: CGFloat = 0.82
        static let darkSecondaryTextAlpha: CGFloat = 0.62
        static let lightTextAlpha: CGFloat = 0.82
        static let lightSecondaryTextAlpha: CGFloat = 0.68
    }

    private static func chromeBackgroundColor(
        for appearance: BonsplitConfiguration.Appearance
    ) -> NSColor? {
        guard let value = appearance.chromeColors.backgroundHex else { return nil }
        return NSColor(bonsplitHex: value)
    }

    private static func effectiveBackgroundColor(
        for appearance: BonsplitConfiguration.Appearance
    ) -> NSColor {
        chromeBackgroundColor(for: appearance) ?? NSColor.windowBackgroundColor
    }

    private static func effectiveTextColor(
        for appearance: BonsplitConfiguration.Appearance,
        secondary: Bool
    ) -> NSColor {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return secondary ? .secondaryLabelColor : .labelColor
        }

        if custom.isBonsplitLightColor {
            let alpha = secondary ? Constants.darkSecondaryTextAlpha : Constants.darkTextAlpha
            return NSColor.black.withAlphaComponent(alpha)
        }

        let alpha = secondary ? Constants.lightSecondaryTextAlpha : Constants.lightTextAlpha
        return NSColor.white.withAlphaComponent(alpha)
    }

    static func paneBackground(for appearance: BonsplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveBackgroundColor(for: appearance))
    }

    static func nsColorPaneBackground(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
        effectiveBackgroundColor(for: appearance)
    }

    // MARK: - Tab Bar Background

    static var barBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static func barBackground(for appearance: BonsplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveBackgroundColor(for: appearance))
    }

    static var barMaterial: Material {
        .bar
    }

    // MARK: - Tab States

    static var activeTabBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func activeTabBackground(for appearance: BonsplitConfiguration.Appearance) -> Color {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return activeTabBackground
        }
        let adjusted = custom.isBonsplitLightColor
            ? custom.bonsplitDarken(by: 0.065)
            : custom.bonsplitLighten(by: 0.12)
        return Color(nsColor: adjusted)
    }

    static var hoveredTabBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    static func hoveredTabBackground(for appearance: BonsplitConfiguration.Appearance) -> Color {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return hoveredTabBackground
        }
        let adjusted = custom.isBonsplitLightColor
            ? custom.bonsplitDarken(by: 0.03)
            : custom.bonsplitLighten(by: 0.07)
        return Color(nsColor: adjusted.withAlphaComponent(0.78))
    }

    static var inactiveTabBackground: Color {
        .clear
    }

    // MARK: - Text Colors

    static var activeText: Color {
        Color(nsColor: .labelColor)
    }

    static func activeText(for appearance: BonsplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveTextColor(for: appearance, secondary: false))
    }

    static func nsColorActiveText(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
        effectiveTextColor(for: appearance, secondary: false)
    }

    static var inactiveText: Color {
        Color(nsColor: .secondaryLabelColor)
    }

    static func inactiveText(for appearance: BonsplitConfiguration.Appearance) -> Color {
        Color(nsColor: effectiveTextColor(for: appearance, secondary: true))
    }

    static func nsColorInactiveText(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
        effectiveTextColor(for: appearance, secondary: true)
    }

    // MARK: - Borders & Indicators

    static var separator: Color {
        Color(nsColor: .separatorColor)
    }

    static func separator(for appearance: BonsplitConfiguration.Appearance) -> Color {
        guard let custom = chromeBackgroundColor(for: appearance) else {
            return separator
        }
        let alpha: CGFloat = custom.isBonsplitLightColor ? 0.26 : 0.36
        let tone = custom.isBonsplitLightColor
            ? custom.bonsplitDarken(by: 0.12)
            : custom.bonsplitLighten(by: 0.16)
        return Color(nsColor: tone.withAlphaComponent(alpha))
    }

    static var dropIndicator: Color {
        Color.accentColor
    }

    static func dropIndicator(for appearance: BonsplitConfiguration.Appearance) -> Color {
        _ = appearance
        return dropIndicator
    }

    static var focusRing: Color {
        Color.accentColor.opacity(0.5)
    }

    static var dirtyIndicator: Color {
        Color(nsColor: .labelColor).opacity(0.6)
    }

    static func dirtyIndicator(for appearance: BonsplitConfiguration.Appearance) -> Color {
        guard chromeBackgroundColor(for: appearance) != nil else { return dirtyIndicator }
        return activeText(for: appearance).opacity(0.72)
    }

    static var notificationBadge: Color {
        Color(nsColor: .systemBlue)
    }

    static func notificationBadge(for appearance: BonsplitConfiguration.Appearance) -> Color {
        _ = appearance
        return notificationBadge
    }

    // MARK: - Shadows

    static var tabShadow: Color {
        Color.black.opacity(0.08)
    }
}

private extension NSColor {
    convenience init?(bonsplitHex value: String) {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&rgb) else { return nil }
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }

    var isBonsplitLightColor: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let color = usingColorSpace(.sRGB) ?? self
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance > 0.5
    }

    func bonsplitLighten(by amount: CGFloat) -> NSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let color = usingColorSpace(.sRGB) ?? self
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return NSColor(
            red: min(1.0, red + amount),
            green: min(1.0, green + amount),
            blue: min(1.0, blue + amount),
            alpha: alpha
        )
    }

    func bonsplitDarken(by amount: CGFloat) -> NSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let color = usingColorSpace(.sRGB) ?? self
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return NSColor(
            red: max(0.0, red - amount),
            green: max(0.0, green - amount),
            blue: max(0.0, blue - amount),
            alpha: alpha
        )
    }
}
