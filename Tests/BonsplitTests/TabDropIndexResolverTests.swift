import CoreGraphics
import Testing
@testable import Bonsplit

@Suite("Horizontal tab strip drop index")
struct TabDropIndexResolverTests {
    private let resolver = TabDropIndexResolver()
    private let bounds = CGRect(x: 0, y: 0, width: 360, height: 34)
    private let tabFrames = [
        CGRect(x: 12, y: 0, width: 80, height: 34),
        CGRect(x: 100, y: 0, width: 120, height: 34),
        CGRect(x: 228, y: 0, width: 72, height: 34),
    ]

    @Test("Pointer position resolves every insertion slot")
    func resolvesEveryInsertionSlot() {
        #expect(insertionIndex(x: 20) == 0)
        #expect(insertionIndex(x: 96) == 1)
        #expect(insertionIndex(x: 224) == 2)
        #expect(insertionIndex(x: 320) == 3)
    }

    @Test("Tab midpoints divide adjacent insertion slots")
    func usesTabMidpointsAsBoundaries() {
        #expect(insertionIndex(x: 51.9) == 0)
        #expect(insertionIndex(x: 52) == 1)
        #expect(insertionIndex(x: 159.9) == 1)
        #expect(insertionIndex(x: 160) == 2)
        #expect(insertionIndex(x: 263.9) == 2)
        #expect(insertionIndex(x: 264) == 3)
    }

    @Test("Pane-local geometry produces the same index in a translated split")
    func translatedSplitUsesItsOwnLocalGeometry() {
        let translatedBounds = bounds.offsetBy(dx: 500, dy: 120)
        let translatedFrames = tabFrames.map { $0.offsetBy(dx: 500, dy: 120) }

        #expect(
            resolver.insertionIndex(
                at: CGPoint(x: 596, y: 137),
                in: translatedBounds,
                tabFrames: translatedFrames
            ) == 1
        )
        #expect(
            resolver.insertionIndex(
                at: CGPoint(x: 724, y: 137),
                in: translatedBounds,
                tabFrames: translatedFrames
            ) == 2
        )
    }

    @Test("Locations outside the strip are rejected")
    func rejectsLocationsOutsideStrip() {
        #expect(insertionIndex(x: -1) == nil)
        #expect(insertionIndex(x: 361) == nil)
        #expect(
            resolver.insertionIndex(
                at: CGPoint(x: 96, y: 35),
                in: bounds,
                tabFrames: tabFrames
            ) == nil
        )
    }

    @Test("An empty strip accepts its only insertion slot")
    func emptyStripUsesZeroIndex() {
        #expect(
            resolver.insertionIndex(
                at: CGPoint(x: 180, y: 17),
                in: bounds,
                tabFrames: []
            ) == 0
        )
    }

    @Test("Registered frames preserve their model insertion indices")
    func indexedFramesPreserveModelIndices() {
        let indexedFrames = [
            TabDropIndexResolver.IndexedFrame(index: 1, frame: tabFrames[1]),
            TabDropIndexResolver.IndexedFrame(index: 2, frame: tabFrames[2]),
        ]

        #expect(
            resolver.insertionIndex(
                at: CGPoint(x: 120, y: bounds.midY),
                in: bounds,
                indexedTabFrames: indexedFrames,
                tabCount: tabFrames.count
            ) == 1
        )
        #expect(
            resolver.insertionIndex(
                at: CGPoint(x: 280, y: bounds.midY),
                in: bounds,
                indexedTabFrames: indexedFrames,
                tabCount: tabFrames.count
            ) == 3
        )
    }

    @Test("Registered frames must stay in model and visual order")
    func rejectsUnorderedIndexedFrames() {
        let unorderedFrames = [
            TabDropIndexResolver.IndexedFrame(index: 1, frame: tabFrames[1]),
            TabDropIndexResolver.IndexedFrame(index: 0, frame: tabFrames[0]),
        ]

        #expect(
            resolver.insertionIndex(
                at: CGPoint(x: 120, y: bounds.midY),
                in: bounds,
                indexedTabFrames: unorderedFrames,
                tabCount: tabFrames.count
            ) == nil
        )
    }

    private func insertionIndex(x: CGFloat) -> Int? {
        resolver.insertionIndex(
            at: CGPoint(x: x, y: bounds.midY),
            in: bounds,
            tabFrames: tabFrames
        )
    }
}
