import XCTest
@testable import Bonsplit
import AppKit

/// The host's shared-terminal sizing chrome on a pane: grid border and hatch
/// in the split divider's color, no fill, and contrast-safe chip text.
final class BonsplitSizingChromePaletteTests: XCTestCase {
    typealias RGB = BonsplitContrastPalette.RGB

    /// Each theme as the host resolves it: terminal background, foreground,
    /// and a chrome border (the default split divider) for that background.
    static let themes: [(name: String, background: String, foreground: String, divider: String)] = [
        ("default light", "#ffffff", "#1d1d1f", "#b3b3b342"),
        ("default dark", "#282c34", "#ffffff", "#4f5566"),
        ("solarized light", "#fdf6e3", "#657b83", "#b1ac9f42"),
        ("solarized dark", "#002b36", "#839496", "#29535c5c"),
        ("low-contrast dark", "#1e1e1e", "#3a3a3a", "#4a4a4a5c"),
        ("mid grey / white", "#808080", "#ffffff", "#5a5a5a42"),
        ("dracula", "#282a36", "#f8f8f2", "#50525e5c"),
    ]

    /// `#rrggbb` or `#rrggbbaa` in sRGB.
    private func hexColor(_ hex: String) -> NSColor? {
        let digits = String(hex.dropFirst())
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? (value << 8) | 0xFF : value
        func component(_ shift: UInt64) -> CGFloat { CGFloat((rgba >> shift) & 0xFF) / 255 }
        return NSColor(srgbRed: component(24), green: component(16), blue: component(8), alpha: component(0))
    }

    private func divider(_ hex: String) throws -> NSColor {
        try XCTUnwrap(hexColor(hex), hex)
    }

    func testBorderAndChipOutlineAreTheSplitDividerColor() throws {
        for theme in Self.themes {
            let background = try XCTUnwrap(hexColor(theme.background))
            let foreground = try XCTUnwrap(hexColor(theme.foreground))
            let dividerColor = try divider(theme.divider)
            let palette = BonsplitSizingChromePalette(
                background: background,
                foreground: foreground,
                divider: dividerColor
            )
            // The divider draws over the pane backdrop, which is the
            // terminal background, so the composite is the pixel it shows.
            let expected = BonsplitContrastPalette.rgb(dividerColor, over: background)
            XCTAssertEqual(palette.line, expected, "\(theme.name): border is the divider")
        }
    }

    func testHatchIsTheDividerAtReducedOpacityWithNoFill() throws {
        for theme in Self.themes {
            let background = try XCTUnwrap(RGB(hex: theme.background))
            let palette = BonsplitSizingChromePalette(
                background: try XCTUnwrap(hexColor(theme.background)),
                foreground: try XCTUnwrap(hexColor(theme.foreground)),
                divider: try divider(theme.divider)
            )
            let expected = background.mixed(toward: palette.line, by: BonsplitSizingChromePalette.hatchOpacity)
            XCTAssertEqual(palette.hatch, expected, "\(theme.name): hatch is the divider, fainter")
            XCTAssertEqual(palette.chipFill, background, "\(theme.name): chip fill is the terminal background")
            let ratio = BonsplitContrastPalette.contrastRatio
            // Never brighter than the divider it sits next to.
            XCTAssertLessThanOrEqual(ratio(palette.hatch, background), ratio(palette.line, background) + 0.001, theme.name)
        }
    }

    func testChipTextKeepsItsContrastFloor() throws {
        for theme in Self.themes + BonsplitContrastPaletteTests.themes.map({ (name: $0.name, background: $0.background, foreground: $0.foreground, divider: "#80808060") }) {
            let palette = BonsplitSizingChromePalette(
                background: try XCTUnwrap(hexColor(theme.background)),
                foreground: try XCTUnwrap(hexColor(theme.foreground)),
                divider: try divider(theme.divider)
            )
            XCTAssertGreaterThanOrEqual(
                BonsplitContrastPalette.contrastRatio(palette.text, palette.chipFill),
                4.5,
                "\(theme.name): chip text on its fill"
            )
        }
    }

    func testAppearanceExposesTheColorSplitDividersDraw() throws {
        var appearance = BonsplitConfiguration.Appearance()
        appearance.chromeColors = .init(backgroundHex: "#282c34", borderHex: "#4f5566", dividerHex: "#ff000080")
        XCTAssertEqual(appearance.splitDividerColor, TabBarColors.nsColorSplitDivider(for: appearance))
        appearance.chromeColors = .init(backgroundHex: "#282c34", borderHex: "#4f5566")
        XCTAssertEqual(appearance.splitDividerColor, TabBarColors.nsColorSplitDivider(for: appearance))
    }
}
