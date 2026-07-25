import XCTest
import AppKit
@testable import Bonsplit

/// Verifies that ``BonsplitConfiguration/Appearance/TabStyle`` overrides flow
/// through ``TabBarColors`` and that an empty style is a no-op that preserves the
/// historical derived styling.
final class TabStyleTests: XCTestCase {
    private func components(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent)
    }

    private func assertColor(
        _ color: NSColor,
        _ expected: (CGFloat, CGFloat, CGFloat, CGFloat),
        accuracy: CGFloat = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = components(color)
        XCTAssertEqual(actual.0, expected.0, accuracy: accuracy, "red", file: file, line: line)
        XCTAssertEqual(actual.1, expected.1, accuracy: accuracy, "green", file: file, line: line)
        XCTAssertEqual(actual.2, expected.2, accuracy: accuracy, "blue", file: file, line: line)
        XCTAssertEqual(actual.3, expected.3, accuracy: accuracy, "alpha", file: file, line: line)
    }

    private func appearance(
        tabStyle: BonsplitConfiguration.Appearance.TabStyle
    ) -> BonsplitConfiguration.Appearance {
        BonsplitConfiguration.Appearance(tabStyle: tabStyle)
    }

    func testForegroundOverridesResolveToConfiguredColors() {
        let style = BonsplitConfiguration.Appearance.TabStyle(
            activeForegroundHex: "#ff0000",
            inactiveForegroundHex: "#00ff00"
        )
        let appearance = appearance(tabStyle: style)

        assertColor(TabBarColors.nsColorActiveText(for: appearance), (1, 0, 0, 1))
        assertColor(TabBarColors.nsColorInactiveText(for: appearance), (0, 1, 0, 1))
    }

    func testActiveIndicatorOverrideReplacesSystemAccent() {
        let style = BonsplitConfiguration.Appearance.TabStyle(activeIndicatorHex: "#0000ff")
        let appearance = appearance(tabStyle: style)

        assertColor(
            TabBarColors.nsColorActiveIndicator(for: appearance, saturation: 1),
            (0, 0, 1, 1)
        )
    }

    func testDividerOverrideAndNoneSentinel() {
        let hexAppearance = appearance(
            tabStyle: BonsplitConfiguration.Appearance.TabStyle(dividerHex: "#112233")
        )
        assertColor(
            TabBarColors.nsColorSeparator(for: hexAppearance),
            (0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0, 1)
        )

        let noneAppearance = appearance(
            tabStyle: BonsplitConfiguration.Appearance.TabStyle(dividerHex: "none")
        )
        let separator = TabBarColors.nsColorSeparator(for: noneAppearance)
        XCTAssertEqual(components(separator).3, 0, accuracy: 0.001, "divider 'none' should be transparent")
    }

    func testEmptyTabStyleFallsBackToDerivedIndicator() {
        let appearance = appearance(tabStyle: .none)
        XCTAssertFalse(appearance.tabStyle.hasOverrides)

        let overridden = TabBarColors.nsColorActiveIndicator(for: appearance, saturation: 1)
        let derived = TabBarColors.nsColorActiveIndicator(saturation: 1)
        assertColor(overridden, components(derived))
    }

    func testFontWeightMapsToAppKitWeight() {
        XCTAssertEqual(BonsplitConfiguration.Appearance.TabStyle.FontWeight.semibold.nsFontWeight, .semibold)
        XCTAssertEqual(BonsplitConfiguration.Appearance.TabStyle.FontWeight.black.nsFontWeight, .black)
    }

    func testActiveIndicatorEdgePlacement() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 30)
        let base = CGRect(x: 10, y: 0, width: 100, height: 30)

        let top = TabBarSelectionChromeView.ChromeNSView.positionedIndicatorFrame(
            base: base, in: bounds, edge: .top
        )
        let bottom = TabBarSelectionChromeView.ChromeNSView.positionedIndicatorFrame(
            base: base, in: bounds, edge: .bottom
        )

        // The view is flipped: .top pins to minY, .bottom to the far edge.
        XCTAssertEqual(top.origin.y, bounds.minY, accuracy: 0.001)
        XCTAssertEqual(bottom.origin.y, bounds.maxY - TabBarMetrics.activeIndicatorHeight, accuracy: 0.001)
        XCTAssertNotEqual(top.origin.y, bottom.origin.y, "top and bottom must differ")
        XCTAssertEqual(bottom.size.height, TabBarMetrics.activeIndicatorHeight, accuracy: 0.001)
    }
}
