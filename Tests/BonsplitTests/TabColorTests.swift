import XCTest
@testable import Bonsplit

final class TabColorTests: XCTestCase {
    func testHexParsesWithAndWithoutHash() throws {
        let color = try XCTUnwrap(TabColor(hex: "#BB9AF7"))
        XCTAssertEqual(color.red, 187.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(color.green, 154.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(color.blue, 247.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(TabColor(hex: "bb9af7"), color)
        XCTAssertEqual(color.hexString, "#BB9AF7")
    }

    func testHexRejectsMalformedInput() {
        for bad in ["", "#", "#BB9AF", "#BB9AF7A", "#GG9AF7", "BB 9AF7", "#+B9AF7"] {
            XCTAssertNil(TabColor(hex: bad), bad)
        }
    }

    func testComponentsAreClamped() {
        let color = TabColor(red: -1, green: 0.5, blue: 2)
        XCTAssertEqual(color.red, 0)
        XCTAssertEqual(color.green, 0.5)
        XCTAssertEqual(color.blue, 1)
    }

    func testTabItemCodableRoundTripsColor() throws {
        let color = try XCTUnwrap(TabColor(hex: "#38B44A"))
        let decoded = try JSONDecoder().decode(TabItem.self, from: JSONEncoder().encode(TabItem(title: "zsh", color: color)))
        XCTAssertEqual(decoded.color, color)

        let legacy = try JSONDecoder().decode(TabItem.self, from: JSONEncoder().encode(TabItem(title: "zsh")))
        XCTAssertNil(legacy.color)
    }

    @MainActor
    func testUpdateTabSetsKeepsAndClearsColor() throws {
        let controller = BonsplitController()
        let tabId = try XCTUnwrap(controller.createTab(title: "zsh"))
        XCTAssertNil(controller.tab(tabId)?.color)

        let color = try XCTUnwrap(TabColor(hex: "#26A8E0"))
        controller.updateTab(tabId, color: .some(color))
        XCTAssertEqual(controller.tab(tabId)?.color, color)

        controller.updateTab(tabId, title: "renamed")
        XCTAssertEqual(controller.tab(tabId)?.color, color)

        controller.updateTab(tabId, color: .some(nil))
        XCTAssertNil(controller.tab(tabId)?.color)
    }

    @MainActor
    func testSplittingWithATabKeepsItsColor() throws {
        let controller = BonsplitController()
        let pane = try XCTUnwrap(controller.allPaneIds.first)
        let color = try XCTUnwrap(TabColor(hex: "#FF9E64"))
        let tab = Tab(title: "zsh", color: color)

        let newPane = try XCTUnwrap(controller.splitPane(pane, orientation: .horizontal, withTab: tab))
        let created = try XCTUnwrap(controller.tabs(inPane: newPane).first)
        XCTAssertEqual(created.color, color)
    }
}
