import CoreGraphics
import Testing
@testable import Bonsplit

@Suite("Pane auto layout")
@MainActor
struct AutoLayoutTests {
    @Test("Auto layout column sizes follow Zellij's default swap layout")
    func autoLayoutColumnSizes() {
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 1) == [1])
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 2) == [1, 1])
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 3) == [1, 2])
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 5) == [1, 4])
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 6) == [2, 4])
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 8) == [4, 4])
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 9) == [1, 4, 4])
        #expect(SplitViewController.autoLayoutColumnSizes(paneCount: 12) == [4, 4, 4])
    }

    @Test("Auto layout places panes in creation order with equal sizes")
    func autoLayoutPlacesPanes() throws {
        let controller = BonsplitController()
        var panes = [try #require(controller.focusedPaneId)]
        for index in 1..<6 {
            let pane = try #require(controller.addPaneWithAutoLayout(withTab: Tab(title: "\(index)")))
            #expect(controller.focusedPaneId == pane)
            panes.append(pane)
        }

        let bounds = Dictionary(
            uniqueKeysWithValues: controller.internalController.rootNode.computePaneBounds().map { ($0.paneId, $0.bounds) }
        )
        #expect(bounds.count == 6)
        // Six panes: [0, 1] in the left column, [2, 3, 4, 5] in the right.
        func approx(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }
        for (index, pane) in panes.enumerated() {
            let rect = try #require(bounds[pane])
            #expect(approx(rect.width, 0.5))
            let column = index < 2 ? 0 : 1
            let row = index < 2 ? index : index - 2
            let rows: CGFloat = index < 2 ? 2 : 4
            #expect(approx(rect.minX, CGFloat(column) * 0.5))
            #expect(approx(rect.minY, CGFloat(row) / rows))
            #expect(approx(rect.height, 1 / rows))
            #expect(controller.tabs(inPane: pane).count == 1)
        }
    }

    @Test("Auto layout keeps creation order after a manual split and clears zoom")
    func autoLayoutAfterManualSplit() throws {
        let controller = BonsplitController()
        let first = try #require(controller.focusedPaneId)
        let second = try #require(controller.addPaneWithAutoLayout(withTab: Tab(title: "2")))
        let third = try #require(
            controller.splitPane(first, orientation: .vertical, withTab: Tab(title: "3"), insertFirst: false)
        )
        #expect(controller.togglePaneZoom(inPane: third))
        let fourth = try #require(controller.addPaneWithAutoLayout(from: third, withTab: Tab(title: "4")))
        #expect(controller.zoomedPaneId == nil)
        #expect(controller.internalController.rootNode.allPaneIds == [first, second, third, fourth])
    }
}
