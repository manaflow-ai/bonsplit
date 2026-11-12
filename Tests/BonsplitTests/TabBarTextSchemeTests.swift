import AppKit
import XCTest
@testable import Bonsplit

/// Tab bar text picks black or white by WCAG contrast, matching the host
/// sidebar, so saturated mid-tone backgrounds get the more readable color.
final class TabBarTextSchemeTests: XCTestCase {
    func testSaturatedRedUsesDarkText() {
        // Hot Dog Stand: black reads at 5.4:1, white at 3.2:1.
        XCTAssertTrue(activeTextIsDark(onBackgroundHex: "#E44330"))
    }

    func testDarkGreenUsesLightText() {
        // Grass: white reads at 5.5:1, black at 3.8:1.
        XCTAssertFalse(activeTextIsDark(onBackgroundHex: "#1C763F"))
    }

    func testNeutralBackgroundsKeepTheirScheme() {
        XCTAssertTrue(activeTextIsDark(onBackgroundHex: "#FDF6E3"))
        XCTAssertFalse(activeTextIsDark(onBackgroundHex: "#272822"))
    }

    func testShortcutHintPillFollowsTheTabBarChoice() {
        let red = BonsplitConfiguration.Appearance(chromeColors: .init(backgroundHex: "#E44330"))
        let dark = BonsplitConfiguration.Appearance(chromeColors: .init(backgroundHex: "#272822"))
        XCTAssertEqual(TabBarColors.usesDarkChrome(for: red), false)
        XCTAssertEqual(TabBarColors.usesDarkChrome(for: dark), true)
        XCTAssertNil(TabBarColors.usesDarkChrome(for: BonsplitConfiguration.Appearance()))
    }

    private func activeTextIsDark(onBackgroundHex hex: String) -> Bool {
        let appearance = BonsplitConfiguration.Appearance(chromeColors: .init(backgroundHex: hex))
        let text = TabBarColors.nsColorActiveText(for: appearance).usingColorSpace(.sRGB)!
        return text.redComponent < 0.5
    }
}
