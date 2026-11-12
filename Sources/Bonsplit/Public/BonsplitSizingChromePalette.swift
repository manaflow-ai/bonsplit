import AppKit

/// Colors of a host's shared-terminal sizing chrome on a pane: the grid
/// border, the hatch outside the grid, and the size chip.
///
/// Lines use the split divider's own color, so the bounds read as the same
/// gray as every other pane edge. The hatch is that color at reduced opacity
/// over the terminal background, with no fill of its own. Only the chip text
/// keeps a contrast floor, because it is text.
public struct BonsplitSizingChromePalette: Equatable, Sendable {
    public typealias RGB = BonsplitContrastPalette.RGB

    /// Opacity of the hatch lines relative to the divider color.
    public static let hatchOpacity = 0.6

    /// The terminal background the chrome sits on.
    public let background: RGB
    /// Grid border and chip outline: the split divider as drawn over
    /// ``background``.
    public let line: RGB
    /// Hatch lines outside the grid: ``line`` at ``hatchOpacity``.
    public let hatch: RGB
    /// The chip's fill: the terminal background.
    public var chipFill: RGB { background }
    /// Chip text, at least 4.5:1 on ``chipFill``.
    public let text: RGB

    /// - Parameters:
    ///   - background: The terminal background.
    ///   - foreground: The terminal foreground; chip text mixes toward it.
    ///   - line: The split divider color, already composited over `background`.
    public init(background: RGB, foreground: RGB, line: RGB) {
        self.background = background
        self.line = line
        hatch = background.mixed(toward: line, by: Self.hatchOpacity)
        text = BonsplitContrastPalette(background: background, foreground: foreground).text
    }

    /// The palette for the terminal colors and the split divider color,
    /// resolved in the current drawing appearance. A translucent divider
    /// composites over the terminal background, the backdrop the divider
    /// itself draws over.
    public init(background: NSColor, foreground: NSColor, divider: NSColor) {
        let surface = BonsplitContrastPalette.rgb(background)
        let surfaceColor = NSColor(srgbRed: surface.red, green: surface.green, blue: surface.blue, alpha: 1)
        self.init(
            background: surface,
            foreground: BonsplitContrastPalette.rgb(foreground, over: surfaceColor),
            line: BonsplitContrastPalette.rgb(divider, over: surfaceColor)
        )
    }
}

extension BonsplitConfiguration.Appearance {
    /// The color split dividers draw with: `dividerHex`, else `borderHex`,
    /// else a separator derived from the chrome background.
    public var splitDividerColor: NSColor {
        TabBarColors.nsColorSplitDivider(for: self)
    }
}
