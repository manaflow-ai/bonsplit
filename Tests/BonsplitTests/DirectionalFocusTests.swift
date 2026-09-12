import Bonsplit
import Testing

@Suite("Directional pane focus")
@MainActor
struct DirectionalFocusTests {
    @Test("Horizontal navigation stays in the adjacent column")
    func horizontalNavigationStaysInAdjacentColumn() throws {
        let controller = BonsplitController()
        let centerPane = try #require(controller.focusedPaneId)
        let rightPane = try #require(
            controller.splitPane(
                centerPane,
                orientation: .horizontal,
                withTab: Tab(title: "Right"),
                insertFirst: false
            )
        )
        let leftPane = try #require(
            controller.splitPane(
                centerPane,
                orientation: .horizontal,
                withTab: Tab(title: "Left"),
                insertFirst: true
            )
        )
        let upPane = try #require(
            controller.splitPane(
                centerPane,
                orientation: .vertical,
                withTab: Tab(title: "Up"),
                insertFirst: true
            )
        )
        let downPane = try #require(
            controller.splitPane(
                centerPane,
                orientation: .vertical,
                withTab: Tab(title: "Down"),
                insertFirst: false
            )
        )

        let adjacentColumn = Set([upPane, centerPane, downPane])

        controller.focusPane(rightPane)
        controller.navigateFocus(direction: .left)
        let rightNavigationTarget = try #require(controller.focusedPaneId)
        #expect(adjacentColumn.contains(rightNavigationTarget))

        controller.focusPane(leftPane)
        controller.navigateFocus(direction: .right)
        let leftNavigationTarget = try #require(controller.focusedPaneId)
        #expect(adjacentColumn.contains(leftNavigationTarget))
    }
}
