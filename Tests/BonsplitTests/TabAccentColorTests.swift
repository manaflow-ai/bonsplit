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

    func testAccentStripRejectsMalformedHex() {
        let appearance = BonsplitConfiguration.Appearance()

        XCTAssertNil(TabBarColors.tabAccentStrip(hex: "not-a-color", for: appearance, isSelected: true))
        XCTAssertNil(TabBarColors.tabAccentStrip(hex: "#FFF", for: appearance, isSelected: true))
        XCTAssertNotNil(TabBarColors.tabAccentStrip(hex: "#C0392B", for: appearance, isSelected: true))
    }
}
