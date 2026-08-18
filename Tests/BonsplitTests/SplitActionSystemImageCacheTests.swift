import AppKit
@testable import Bonsplit
import Testing

/// `splitActionButtonIcon` resolves every split button's icon during every tab
/// bar body evaluation, and resolving asks AppKit whether a name is a real SF
/// Symbol by loading the symbol image and discarding it. Under an animating tab
/// title the tab bar re-evaluates ~20 times a second, so the resolution has to
/// be memoized rather than repeated.
@Suite("Split action symbol resolution")
struct SplitActionSystemImageCacheTests {
    private let names = ["plus", "square.split.2x1", "ellipsis.vertical", "not.a.real.symbol.name"]

    @Test func repeatedLookupsResolveEachNameOnce() {
        let cache = SplitActionSystemImageCache()

        for _ in 0..<500 {
            for name in names {
                _ = cache.image(for: name)
            }
        }

        #expect(cache.resolutionCount == names.count)
    }

    @Test func memoizingDoesNotChangeWhatIsResolved() {
        let cache = SplitActionSystemImageCache()

        // A real symbol keeps its own name and is drawn upright.
        let real = cache.image(for: "plus")
        #expect(real == TabBarStyling.resolveSplitActionSystemImage(for: "plus"))
        #expect(real.name == "plus")
        #expect(real.rotationDegrees == 0)

        // `ellipsis.vertical` is not a symbol; it is a rotated `ellipsis`.
        let rotated = cache.image(for: "ellipsis.vertical")
        #expect(rotated == TabBarStyling.resolveSplitActionSystemImage(for: "ellipsis.vertical"))
        #expect(rotated.name == "ellipsis")
        #expect(rotated.rotationDegrees == 90)

        // Anything else falls back rather than drawing nothing.
        let unknown = cache.image(for: "not.a.real.symbol.name")
        #expect(unknown == TabBarStyling.resolveSplitActionSystemImage(for: "not.a.real.symbol.name"))
        #expect(unknown.name == "questionmark.circle")
    }

    @Test func theTabBarGoesThroughTheCache() {
        // Two calls with no cache in between would resolve twice; the point of
        // the accessor is that the second one costs a dictionary lookup.
        let before = SplitActionSystemImageCache.shared.resolutionCount
        for _ in 0..<200 {
            _ = TabBarStyling.splitActionSystemImage(for: "square.split.2x1")
        }
        let resolutions = SplitActionSystemImageCache.shared.resolutionCount - before

        #expect(resolutions <= 1)
    }

    /// A repeat lookup must not reach AppKit at all. Timed rather than counted
    /// so the assertion still means something if the cache is later replaced by
    /// a different mechanism. The bound is loose on purpose: the measured gap is
    /// two to three orders of magnitude.
    @Test func cachedLookupsAreOrdersOfMagnitudeCheaper() {
        let iterations = 2_000
        let name = "square.split.2x1"
        let cache = SplitActionSystemImageCache()

        let uncachedStart = ContinuousClock.now
        for _ in 0..<iterations {
            _ = TabBarStyling.resolveSplitActionSystemImage(for: name)
        }
        let uncached = ContinuousClock.now - uncachedStart

        _ = cache.image(for: name)
        let cachedStart = ContinuousClock.now
        for _ in 0..<iterations {
            _ = cache.image(for: name)
        }
        let cached = ContinuousClock.now - cachedStart

        print("[split-action-symbol] \(iterations) lookups: uncached \(uncached), cached \(cached)")
        #expect(cached < uncached / 10)
    }
}
