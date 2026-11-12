import XCTest
@testable import Bonsplit
import AppKit

/// Theme matrix for the neutral presence / sizing palette. Every theme must
/// meet each contrast floor: glyphs and text 4.5:1, rings and borders 3:1,
/// fills visibly off the background.
final class BonsplitContrastPaletteTests: XCTestCase {
    typealias RGB = BonsplitContrastPalette.RGB

    static let themes: [(name: String, background: String, foreground: String)] = [
        ("default light", "#ffffff", "#1d1d1f"),
        ("macOS window light", "#ececec", "#262626"),
        ("default dark", "#282c34", "#ffffff"),
        ("solarized light", "#fdf6e3", "#657b83"),
        ("solarized dark", "#002b36", "#839496"),
        ("low-contrast dark", "#1e1e1e", "#3a3a3a"),
        ("pure white", "#ffffff", "#000000"),
        ("pure black", "#000000", "#ffffff"),
        ("mid grey / white", "#808080", "#ffffff"),
        ("mid grey / black", "#808080", "#000000"),
        ("dracula", "#282a36", "#f8f8f2"),
    ]

    private func palette(_ theme: (name: String, background: String, foreground: String)) throws -> BonsplitContrastPalette {
        BonsplitContrastPalette(
            background: try XCTUnwrap(RGB(hex: theme.background), theme.name),
            foreground: try XCTUnwrap(RGB(hex: theme.foreground), theme.name)
        )
    }

    func testEveryThemeMeetsEveryContrastFloor() throws {
        for theme in Self.themes {
            let p = try palette(theme)
            let ratio = BonsplitContrastPalette.contrastRatio
            XCTAssertGreaterThanOrEqual(ratio(p.glyph, p.fill), 4.5, "\(theme.name): glyph on fill")
            XCTAssertGreaterThanOrEqual(ratio(p.text, p.background), 4.5, "\(theme.name): text on background")
            XCTAssertGreaterThanOrEqual(ratio(p.line, p.background), 3.0, "\(theme.name): line on background")
            XCTAssertGreaterThanOrEqual(ratio(p.fill, p.background), 1.2, "\(theme.name): fill visible")
            XCTAssertGreaterThanOrEqual(ratio(p.hatch, p.background), 1.3, "\(theme.name): hatch visible")
            // Subtle: the fill never competes with the glyph it carries.
            XCTAssertLessThan(ratio(p.fill, p.background), 2.2, "\(theme.name): fill subtle")
        }
    }

    func testPaletteStaysNeutralForNeutralThemes() throws {
        let p = try palette(("pure white", "#ffffff", "#000000"))
        for color in [p.fill, p.glyph, p.text, p.line, p.hatch] {
            XCTAssertEqual(color.red, color.green, accuracy: 0.001)
            XCTAssertEqual(color.green, color.blue, accuracy: 0.001)
        }
    }

    func testContrastRatioMatchesWCAGReferencePoints() throws {
        let white = try XCTUnwrap(RGB(hex: "#ffffff"))
        let black = try XCTUnwrap(RGB(hex: "#000000"))
        XCTAssertEqual(BonsplitContrastPalette.contrastRatio(white, black), 21, accuracy: 0.01)
        XCTAssertEqual(BonsplitContrastPalette.contrastRatio(white, try XCTUnwrap(RGB(hex: "#767676"))), 4.54, accuracy: 0.01)
    }

    /// The reported bug: a light terminal theme while macOS runs dark. The
    /// accessory must follow the tab bar's own colors, not the system label.
    func testPresenceColorsFollowLightTabBarUnderDarkSystemAppearance() throws {
        var appearance = BonsplitConfiguration.Appearance()
        appearance.chromeColors = .init(backgroundHex: "#fdf6e3")
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        for isSelected in [true, false] {
            let colors = TabBarColors.presenceColors(for: appearance, isSelected: isSelected)
            var surface = RGB(red: 0, green: 0, blue: 0)
            var fill = surface, glyph = surface, line = surface, text = surface
            dark.performAsCurrentDrawingAppearance {
                surface = BonsplitContrastPalette.rgb(colors.surface)
                fill = BonsplitContrastPalette.rgb(colors.fill)
                glyph = BonsplitContrastPalette.rgb(colors.glyph)
                line = BonsplitContrastPalette.rgb(colors.line)
                text = BonsplitContrastPalette.rgb(colors.text)
            }
            XCTAssertGreaterThan(surface.relativeLuminance, 0.5, "selected=\(isSelected): tab surface is light")
            XCTAssertGreaterThanOrEqual(BonsplitContrastPalette.contrastRatio(glyph, fill), 4.5, "selected=\(isSelected)")
            XCTAssertGreaterThanOrEqual(BonsplitContrastPalette.contrastRatio(text, surface), 4.5, "selected=\(isSelected)")
            XCTAssertGreaterThanOrEqual(BonsplitContrastPalette.contrastRatio(line, surface), 3.0, "selected=\(isSelected)")
        }
    }

    /// Without theme colors the accessory uses the system surface and label,
    /// resolved in whichever appearance draws it.
    func testPresenceColorsResolveSystemColorsPerAppearance() throws {
        let colors = TabBarColors.presenceColors(for: BonsplitConfiguration.Appearance(), isSelected: false)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let drawing = try XCTUnwrap(NSAppearance(named: name))
            var surface = RGB(red: 0, green: 0, blue: 0)
            var fill = surface, glyph = surface
            drawing.performAsCurrentDrawingAppearance {
                surface = BonsplitContrastPalette.rgb(colors.surface)
                fill = BonsplitContrastPalette.rgb(colors.fill)
                glyph = BonsplitContrastPalette.rgb(colors.glyph)
            }
            XCTAssertEqual(surface.relativeLuminance > 0.5, name == .aqua, "\(name.rawValue)")
            XCTAssertGreaterThanOrEqual(BonsplitContrastPalette.contrastRatio(glyph, fill), 4.5, "\(name.rawValue)")
        }
    }
}
