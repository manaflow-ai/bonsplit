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

  private static func paneBackgroundColor(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor? {
    guard let value = appearance.chromeColors.paneBackgroundHex else {
      return chromeBackgroundColor(for: appearance)
    }
    return NSColor(bonsplitHex: value)
  }

  private static func tabBarBackgroundColor(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor? {
    guard let value = appearance.chromeColors.tabBarBackgroundHex else {
      return chromeBackgroundColor(for: appearance)
    }
    return NSColor(bonsplitHex: value)
  }

  private static func nonClearColor(_ color: NSColor?) -> NSColor? {
    guard let color else { return nil }
    let resolved = color.usingColorSpace(.sRGB) ?? color
    return resolved.alphaComponent <= 0.001 ? nil : resolved
  }

  private static func semanticTabBarBackgroundColor(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor? {
    nonClearColor(tabBarBackgroundColor(for: appearance))
      ?? nonClearColor(chromeBackgroundColor(for: appearance))
  }

  private static func splitButtonBackdropColor(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor? {
    guard let value = appearance.chromeColors.splitButtonBackdropHex else {
      return tabBarBackgroundColor(for: appearance)
    }
    return NSColor(bonsplitHex: value)
  }

  private static func chromeBorderColor(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor? {
    guard let value = appearance.chromeColors.borderHex else { return nil }
    return NSColor(bonsplitHex: value)
  }

  private static func effectiveBackgroundColor(
    for appearance: BonsplitConfiguration.Appearance,
    fallback fallbackColor: NSColor
  ) -> NSColor {
    chromeBackgroundColor(for: appearance) ?? fallbackColor
  }

  private static func precompositedPaneBackground(
    for appearance: BonsplitConfiguration.Appearance,
    focused: Bool
  ) -> NSColor {
    let chrome = nsColorPaneBackground(for: appearance)
    let windowBackground = NSColor.windowBackgroundColor
    guard let foreground = chrome.usingColorSpace(.sRGB),
      let background = windowBackground.usingColorSpace(.sRGB)
    else {
      return chrome.withAlphaComponent(1.0)
    }
    let alpha = focused ? foreground.alphaComponent : foreground.alphaComponent * 0.95
    let oneMinusAlpha = 1.0 - alpha
    let red = foreground.redComponent * alpha + background.redComponent * oneMinusAlpha
    let green = foreground.greenComponent * alpha + background.greenComponent * oneMinusAlpha
    let blue = foreground.blueComponent * alpha + background.blueComponent * oneMinusAlpha
    return NSColor(red: red, green: green, blue: blue, alpha: 1.0)
  }

  private static func effectiveTextColor(
    for appearance: BonsplitConfiguration.Appearance,
    secondary: Bool
  ) -> NSColor {
    guard let custom = semanticTabBarBackgroundColor(for: appearance) else {
      return secondary ? .secondaryLabelColor : .labelColor
    }

    if custom.isBonsplitLightColor {
      let alpha = secondary ? Constants.darkSecondaryTextAlpha : Constants.darkTextAlpha
      return NSColor.black.withAlphaComponent(alpha)
    }

    let alpha = secondary ? Constants.lightSecondaryTextAlpha : Constants.lightTextAlpha
    return NSColor.white.withAlphaComponent(alpha)
  }

  static func nsColorPaneBackground(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
    paneBackgroundColor(for: appearance) ?? .textBackgroundColor
  }

  // MARK: - Tab Bar Background

  static func nsColorBarBackground(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
    tabBarBackgroundColor(for: appearance)
      ?? effectiveBackgroundColor(for: appearance, fallback: .windowBackgroundColor)
  }

  static func nsColorChromeBackground(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
    effectiveBackgroundColor(for: appearance, fallback: .windowBackgroundColor)
  }

  static func nsColorSplitButtonBackdropSurface(for appearance: BonsplitConfiguration.Appearance)
    -> NSColor
  {
    splitButtonBackdropColor(for: appearance) ?? nsColorBarBackground(for: appearance)
  }

  static func nsColorSplitButtonBackdropOccludingSurface(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor {
    nonClearColor(splitButtonBackdropColor(for: appearance))
      ?? .clear
  }

  static func nsColorSplitButtonBackdrop(
    for appearance: BonsplitConfiguration.Appearance,
    focused: Bool = true
  ) -> NSColor {
    precompositedPaneBackground(for: appearance, focused: focused)
  }

  static func shouldPaintSplitButtonBackdrop(for appearance: BonsplitConfiguration.Appearance)
    -> Bool
  {
    nonClearColor(splitButtonBackdropColor(for: appearance)) != nil
  }

  static func nsColorActiveText(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
    effectiveTextColor(for: appearance, secondary: false)
  }

  static func nsColorInactiveText(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
    effectiveTextColor(for: appearance, secondary: true)
  }

  static func nsColorActiveTabBackground(for appearance: BonsplitConfiguration.Appearance)
    -> NSColor
  {
    guard let custom = tabBarBackgroundColor(for: appearance) else {
      return .controlBackgroundColor
    }
    guard !appearance.usesSharedBackdrop else { return .clear }
    return custom.isBonsplitLightColor
      ? custom.bonsplitDarken(by: 0.065)
      : custom.bonsplitLighten(by: 0.12)
  }

  static func nsColorHoveredTabBackground(for appearance: BonsplitConfiguration.Appearance)
    -> NSColor
  {
    guard let custom = tabBarBackgroundColor(for: appearance) else {
      return NSColor.controlBackgroundColor.withAlphaComponent(0.5)
    }
    if appearance.usesSharedBackdrop {
      let background = semanticTabBarBackgroundColor(for: appearance) ?? custom
      return background.isBonsplitLightColor
        ? NSColor.black.withAlphaComponent(0.055)
        : NSColor.white.withAlphaComponent(0.075)
    }
    let adjusted =
      custom.isBonsplitLightColor
      ? custom.bonsplitDarken(by: 0.03)
      : custom.bonsplitLighten(by: 0.07)
    return adjusted.withAlphaComponent(0.78)
  }

  static func nsColorSplitActionIcon(
    for appearance: BonsplitConfiguration.Appearance,
    isPressed: Bool
  ) -> NSColor {
    isPressed ? nsColorActiveText(for: appearance) : nsColorInactiveText(for: appearance)
  }

  static func nsColorSeparator(for appearance: BonsplitConfiguration.Appearance) -> NSColor {
    if let explicit = chromeBorderColor(for: appearance) {
      return explicit
    }

    guard let custom = tabBarBackgroundColor(for: appearance) else {
      return .separatorColor
    }
    let alpha: CGFloat = custom.isBonsplitLightColor ? 0.26 : 0.36
    let tone =
      custom.isBonsplitLightColor
      ? custom.bonsplitDarken(by: 0.12)
      : custom.bonsplitLighten(by: 0.16)
    return tone.withAlphaComponent(alpha)
  }

  static func nsColorActiveIndicator(saturation: Double) -> NSColor {
    NSColor.controlAccentColor.bonsplitSaturating(by: saturation)
  }

  static func nsColorDirtyIndicator(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor {
    guard chromeBackgroundColor(for: appearance) != nil else {
      return NSColor.labelColor.withAlphaComponent(0.6)
    }
    return nsColorActiveText(for: appearance).withAlphaComponent(0.72)
  }

  static func nsColorNotificationBadge(
    for appearance: BonsplitConfiguration.Appearance
  ) -> NSColor {
    _ = appearance
    return .systemBlue
  }
}

extension NSColor {
  private static let bonsplitHexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

  fileprivate convenience init?(bonsplitHex value: String) {
    var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") {
      hex.removeFirst()
    }
    guard hex.count == 6 || hex.count == 8 else { return nil }
    guard hex.unicodeScalars.allSatisfy({ Self.bonsplitHexDigits.contains($0) }) else { return nil }
    guard let rgba = UInt64(hex, radix: 16) else { return nil }
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
    if hex.count == 8 {
      red = CGFloat((rgba & 0xFF00_0000) >> 24) / 255.0
      green = CGFloat((rgba & 0x00FF_0000) >> 16) / 255.0
      blue = CGFloat((rgba & 0x0000_FF00) >> 8) / 255.0
      alpha = CGFloat(rgba & 0x0000_00FF) / 255.0
    } else {
      red = CGFloat((rgba & 0xFF0000) >> 16) / 255.0
      green = CGFloat((rgba & 0x00FF00) >> 8) / 255.0
      blue = CGFloat(rgba & 0x0000FF) / 255.0
      alpha = 1.0
    }
    self.init(red: red, green: green, blue: blue, alpha: alpha)
  }

  fileprivate var isBonsplitLightColor: Bool {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    let color = usingColorSpace(.sRGB) ?? self
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
    return luminance > 0.5
  }

  fileprivate func bonsplitSaturating(by amount: Double) -> NSColor {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    let color = usingColorSpace(.sRGB) ?? self
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let clamped = CGFloat(min(max(amount, 0), 1))
    let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
    return NSColor(
      red: luminance + ((red - luminance) * clamped),
      green: luminance + ((green - luminance) * clamped),
      blue: luminance + ((blue - luminance) * clamped),
      alpha: alpha
    )
  }

  fileprivate func bonsplitLighten(by amount: CGFloat) -> NSColor {
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

  fileprivate func bonsplitDarken(by amount: CGFloat) -> NSColor {
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
