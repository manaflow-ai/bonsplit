import SwiftUI

/// A horizontal flow layout used by the opt-in multi-row tab bar.
///
/// The tab strip's normal path is an AppKit-backed horizontal scroll view. In
/// wrapping mode the layout receives a finite viewport width and places each
/// tab at its natural width, starting a new row when the next tab would not
/// fit. The metrics are kept separate from SwiftUI so row placement remains
/// deterministic and can be covered without mounting a window.
struct TabBarWrappingLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 0, verticalSpacing: CGFloat = 0) {
        self.horizontalSpacing = max(0, horizontalSpacing)
        self.verticalSpacing = max(0, verticalSpacing)
    }

    struct Cache {
        var sizes: [CGSize] = []
        var arrangement = TabBarWrapLayoutMetrics.Arrangement(
            frames: [],
            size: .zero,
            rowCount: 0
        )
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = normalizedWidth(proposal.width)
        let arrangement = TabBarWrapLayoutMetrics.arrangement(
            sizes: sizes,
            availableWidth: availableWidth,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        cache.sizes = sizes
        cache.arrangement = arrangement

        let width = availableWidth.isFinite ? availableWidth : arrangement.size.width
        return CGSize(width: width, height: arrangement.size.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let arrangement = TabBarWrapLayoutMetrics.arrangement(
            sizes: sizes,
            availableWidth: max(0, bounds.width),
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        cache.sizes = sizes
        cache.arrangement = arrangement

        for (index, subview) in subviews.enumerated() {
            guard arrangement.frames.indices.contains(index) else { continue }
            let frame = arrangement.frames[index].offsetBy(
                dx: bounds.minX,
                dy: bounds.minY
            )
            subview.place(
                at: frame.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func normalizedWidth(_ width: CGFloat?) -> CGFloat {
        guard let width, width.isFinite, width > 0 else { return .infinity }
        return width
    }
}

/// Pure row-placement metrics for ``TabBarWrappingLayout``.
struct TabBarWrapLayoutMetrics {
    struct Arrangement: Equatable {
        let frames: [CGRect]
        let size: CGSize
        let rowCount: Int
    }

    static func arrangement(
        sizes: [CGSize],
        availableWidth: CGFloat,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) -> Arrangement {
        guard !sizes.isEmpty else {
            let emptyWidth = availableWidth.isFinite ? max(0, availableWidth) : 0
            return Arrangement(frames: [], size: CGSize(width: emptyWidth, height: 0), rowCount: 0)
        }

        let spacingX = max(0, horizontalSpacing)
        let spacingY = max(0, verticalSpacing)
        let widthLimit = availableWidth.isFinite && availableWidth > 0
            ? availableWidth
            : .infinity
        var frames: [CGRect] = []
        frames.reserveCapacity(sizes.count)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowCount = 1
        var contentWidth: CGFloat = 0

        for size in sizes {
            let width = min(max(0, size.width), widthLimit)
            let height = max(0, size.height)
            let wouldOverflow = x > 0 && x + spacingX + width > widthLimit + 0.001
            if wouldOverflow {
                contentWidth = max(contentWidth, x)
                y += rowHeight + spacingY
                x = 0
                rowHeight = 0
                rowCount += 1
            }

            if x > 0 {
                x += spacingX
            }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            frames.append(frame)
            x += width
            rowHeight = max(rowHeight, height)
        }

        contentWidth = max(contentWidth, x)
        let contentHeight = y + rowHeight
        let resultWidth = widthLimit.isFinite ? widthLimit : contentWidth
        return Arrangement(
            frames: frames,
            size: CGSize(width: resultWidth, height: contentHeight),
            rowCount: rowCount
        )
    }
}
