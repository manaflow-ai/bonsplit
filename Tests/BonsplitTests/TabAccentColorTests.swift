import XCTest
@testable import Bonsplit

/// Covers the tab accent color: it survives the public/internal model hop,
/// `updateTab` can set and clear it, it rides along a drag payload, and a
/// payload written before the field existed still decodes.
final class TabAccentColorTests: XCTestCase {
    @MainActor
    private func makeController() -> BonsplitController {
        BonsplitController()
    }

    @MainActor
    func testCreatedTabKeepsItsColor() {
        let controller = makeController()
        guard let tabId = controller.createTab(title: "api.ts", colorHex: "#C0392B") else {
            return XCTFail("expected the tab to be created")
        }

        XCTAssertEqual(controller.tab(tabId)?.colorHex, "#C0392B")
    }

    @MainActor
    func testTabIsUncoloredByDefault() {
        let controller = makeController()
        guard let tabId = controller.createTab(title: "logs") else {
            return XCTFail("expected the tab to be created")
        }

        XCTAssertNil(controller.tab(tabId)?.colorHex)
    }

    @MainActor
    func testUpdateTabSetsAndClearsColor() {
        let controller = makeController()
        guard let tabId = controller.createTab(title: "notes") else {
            return XCTFail("expected the tab to be created")
        }

        controller.updateTab(tabId, colorHex: .some("#196F3D"))
        XCTAssertEqual(controller.tab(tabId)?.colorHex, "#196F3D")

        // .some(nil) clears; plain nil would mean "leave unchanged".
        controller.updateTab(tabId, colorHex: .some(nil))
        XCTAssertNil(controller.tab(tabId)?.colorHex)
    }

    @MainActor
    func testUpdateTabWithoutColorArgumentLeavesColorIntact() {
        let controller = makeController()
        guard let tabId = controller.createTab(title: "build", colorHex: "#1565C0") else {
            return XCTFail("expected the tab to be created")
        }

        controller.updateTab(tabId, title: "build (renamed)")

        XCTAssertEqual(controller.tab(tabId)?.title, "build (renamed)")
        XCTAssertEqual(controller.tab(tabId)?.colorHex, "#1565C0")
    }

    func testColorSurvivesDragPayloadRoundTrip() throws {
        let original = TabItem(title: "api.ts", colorHex: "#AD1457")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TabItem.self, from: data)

        XCTAssertEqual(decoded.colorHex, "#AD1457")
    }

    /// A payload encoded before `colorHex` existed must still decode, as an
    /// uncolored tab, rather than throwing.
    func testPayloadWithoutColorKeyStillDecodes() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","title":"legacy","hasCustomTitle":false,\
        "isDirty":false,"showsNotificationBadge":false,"isLoading":false,\
        "isAudioMuted":false,"isAudioPlaying":false,"isPinned":false,\
        "showsRemoteIndicator":false}
        """
        let decoded = try JSONDecoder().decode(TabItem.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.title, "legacy")
        XCTAssertNil(decoded.colorHex)
    }

    /// The selected tab's indicator is drawn by an overlay above the tab's own
    /// accent strip. It must adopt the tab's color, or selecting a colored tab
    /// repaints its top edge with the system accent.
    func testSelectedTabIndicatorAdoptsTheTabColor() {
        let appearance = BonsplitConfiguration.Appearance()

        let accent = TabBarColors.nsColorTabAccent(hex: "#C0392B", for: appearance)
        XCTAssertNotNil(accent)

        let systemIndicator = TabBarColors.nsColorActiveIndicator(saturation: 1)
        XCTAssertNotEqual(
            accent?.usingColorSpace(.sRGB)?.redComponent,
            systemIndicator.usingColorSpace(.sRGB)?.redComponent
        )
    }

    /// The strip and the AppKit indicator must derive from one place, so a
    /// selected colored tab reads as a single solid band rather than two shades.
    func testStripAndIndicatorShareTheirDerivation() {
        let appearance = BonsplitConfiguration.Appearance()

        XCTAssertNotNil(TabBarColors.tabAccentStrip(hex: "#196F3D", for: appearance, isSelected: true))
        XCTAssertNotNil(TabBarColors.nsColorTabAccent(hex: "#196F3D", for: appearance))
        XCTAssertNil(TabBarColors.nsColorTabAccent(hex: "nope", for: appearance))
    }

    func testAccentStripRejectsMalformedHex() {
        let appearance = BonsplitConfiguration.Appearance()

        XCTAssertNil(TabBarColors.tabAccentStrip(hex: "not-a-color", for: appearance, isSelected: true))
        XCTAssertNil(TabBarColors.tabAccentStrip(hex: "#FFF", for: appearance, isSelected: true))
        XCTAssertNotNil(TabBarColors.tabAccentStrip(hex: "#C0392B", for: appearance, isSelected: true))
    }
}
