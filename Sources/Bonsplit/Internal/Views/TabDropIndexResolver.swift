import CoreGraphics

/// Resolves a pointer in a horizontal tab strip to an insertion index.
struct TabDropIndexResolver {
    struct IndexedFrame {
        let index: Int
        let frame: CGRect
    }

    static func insertionIndex(
        at location: CGPoint,
        in bounds: CGRect,
        tabFrames: [CGRect]
    ) -> Int? {
        insertionIndex(
            at: location,
            in: bounds,
            indexedTabFrames: tabFrames.enumerated().map { IndexedFrame(index: $0.offset, frame: $0.element) },
            tabCount: tabFrames.count
        )
    }

    static func insertionIndex(
        at location: CGPoint,
        in bounds: CGRect,
        indexedTabFrames: [IndexedFrame],
        tabCount: Int
    ) -> Int? {
        guard bounds.contains(location), tabCount >= 0 else { return nil }
        guard tabCount > 0 else { return 0 }
        guard !indexedTabFrames.isEmpty,
              indexedTabFrames.allSatisfy({ item in
                  (0..<tabCount).contains(item.index)
                      && item.frame.width > 0
                      && item.frame.midX.isFinite
              }),
              Set(indexedTabFrames.map(\.index)).count == indexedTabFrames.count else {
            return nil
        }

        let visuallyOrderedFrames = indexedTabFrames.sorted { lhs, rhs in
            if lhs.frame.midX == rhs.frame.midX {
                return lhs.index < rhs.index
            }
            return lhs.frame.midX < rhs.frame.midX
        }

        for item in visuallyOrderedFrames where location.x < item.frame.midX {
            return item.index
        }

        guard let lastItem = visuallyOrderedFrames.last else { return nil }
        return min(lastItem.index + 1, tabCount)
    }
}
