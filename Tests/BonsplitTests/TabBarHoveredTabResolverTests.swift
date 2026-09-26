import CoreGraphics
import Foundation
import Testing
@testable import Bonsplit

@Suite("Tab strip hovered tab")
struct TabBarHoveredTabResolverTests {
    private let resolver = TabBarHoveredTabResolver()
    private let bounds = CGRect(x: 0, y: 0, width: 360, height: 34)
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func frames(_ ids: [UUID]) -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: CGFloat(index) * 100, y: 0, width: 100, height: 34))
        })
    }

    @Test("Closing the tab under a stationary pointer hovers the tab that slides in")
    func stationaryPointerFollowsReflow() {
        let pointer = CGPoint(x: 150, y: 17)
        #expect(resolver.hoveredTabId(pointInView: pointer, barBounds: bounds, tabIds: [a, b, c], frames: frames([a, b, c])) == b)

        // b closed: c reflows into b's slot under the same pointer.
        #expect(resolver.hoveredTabId(pointInView: pointer, barBounds: bounds, tabIds: [a, c], frames: frames([a, c])) == c)
    }

    @Test("Only one tab can be hovered, and none past the last tab or outside the bar")
    func singleHoverAndEmptySpace() {
        #expect(resolver.hoveredTabId(pointInView: CGPoint(x: 330, y: 17), barBounds: bounds, tabIds: [a, b], frames: frames([a, b])) == nil)
        #expect(resolver.hoveredTabId(pointInView: CGPoint(x: 50, y: 60), barBounds: bounds, tabIds: [a, b], frames: frames([a, b])) == nil)
        #expect(resolver.hoveredTabId(pointInView: nil, barBounds: bounds, tabIds: [a, b], frames: frames([a, b])) == nil)
    }

    @Test("A tab with no registered frame is never hovered")
    func unregisteredTabIgnored() {
        let pointer = CGPoint(x: 150, y: 17)
        #expect(resolver.hoveredTabId(pointInView: pointer, barBounds: bounds, tabIds: [a, b], frames: frames([a])) == nil)
    }

    @Test("A tab scrolled under the trailing action lane is not hovered from the lane")
    func trailingActionLaneMasksTabs() {
        let ids = [a, b, c, UUID()]
        #expect(resolver.hoveredTabId(
            pointInView: CGPoint(x: 330, y: 17),
            barBounds: bounds,
            tabIds: ids,
            frames: frames(ids),
            trailingObscuredWidth: 60
        ) == nil)
        #expect(resolver.hoveredTabId(
            pointInView: CGPoint(x: 290, y: 17),
            barBounds: bounds,
            tabIds: ids,
            frames: frames(ids),
            trailingObscuredWidth: 60
        ) == c)
    }
}
