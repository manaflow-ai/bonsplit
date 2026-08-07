import CoreGraphics

/// Resolves a pointer in a horizontal tab strip to an insertion index.
struct TabDropIndexResolver {
    /// A live tab frame paired with its index in the pane model.
    struct IndexedFrame {
        let index: Int
        let frame: CGRect
    }

    /// Resolves frames whose offsets already match their pane-model indices.
    func insertionIndex(
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

    /// Resolves leading-to-trailing live frames while preserving their pane-model indices.
    func insertionIndex(
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
              }) else {
            return nil
        }

        let framesAreModelAndVisuallyOrdered = zip(
            indexedTabFrames,
            indexedTabFrames.dropFirst()
        ).allSatisfy { pair in
            let (lhs, rhs) = pair
            guard lhs.index < rhs.index else { return false }
            if lhs.frame.midX == rhs.frame.midX {
                return lhs.index < rhs.index
            }
            return lhs.frame.midX < rhs.frame.midX
        }
        guard framesAreModelAndVisuallyOrdered else { return nil }

        for item in indexedTabFrames where location.x < item.frame.midX {
            return item.index
        }

        guard let lastItem = indexedTabFrames.last else { return nil }
        return min(lastItem.index + 1, tabCount)
    }
}
