import AppKit
import SwiftUI
import XCTest
@testable import Bonsplit

@MainActor
final class SplitInitialLayoutTests: XCTestCase {
    private typealias Coordinator = SplitContainerView<Color, Color>.Coordinator

    private final class PaneProbe: NSView {
        var sizes: [NSSize] = []

        override func setFrameSize(_ newSize: NSSize) {
            if newSize.width > 0, newSize.height > 0, frame.size != newSize {
                sizes.append(newSize)
            }
            super.setFrameSize(newSize)
        }
    }

    private func state(_ ratio: CGFloat, orientation: SplitOrientation = .horizontal) -> SplitState {
        SplitState(
            orientation: orientation,
            first: .pane(PaneState()),
            second: .pane(PaneState()),
            dividerPosition: ratio
        )
    }

    private func split(_ state: SplitState, children: [NSView]) -> (NSSplitView, Coordinator) {
        let view = NSSplitView(frame: .zero)
        view.isVertical = state.orientation == .horizontal
        view.dividerStyle = .thin
        let coordinator = Coordinator(
            splitState: state,
            minimumPaneWidth: 1,
            minimumPaneHeight: 1,
            dividerPositionRange: 0.1...0.9,
            onGeometryChange: nil
        )
        view.delegate = coordinator
        coordinator.splitView = view
        for child in children { view.addArrangedSubview(child) }
        return (view, coordinator)
    }

    func testNestedSplitsUseSavedRatiosDuringParentLayout() {
        _ = NSApplication.shared
        let upperState = state(0.60)
        let lowerState = state(0.43)
        let upperFirst = PaneProbe()
        let lowerFirst = PaneProbe()
        let (upper, upperCoordinator) = split(upperState, children: [upperFirst, PaneProbe()])
        let (lower, lowerCoordinator) = split(lowerState, children: [lowerFirst, PaneProbe()])
        let rightState = state(0.46, orientation: .vertical)
        rightState.first = .split(upperState)
        rightState.second = .split(lowerState)
        let (right, rightCoordinator) = split(rightState, children: [upper, lower])
        let rootState = state(0.57)
        rootState.second = .split(rightState)
        let (root, rootCoordinator) = split(rootState, children: [PaneProbe(), right])

        // Do not pump the run loop: a later repair is precisely the visible
        // second layout this regression covers.
        withExtendedLifetime([upperCoordinator, lowerCoordinator, rightCoordinator, rootCoordinator]) {
            root.setFrameSize(NSSize(width: 800, height: 600))

            for (view, model, probe) in [(upper, upperState, upperFirst), (lower, lowerState, lowerFirst)] {
                let expected = (view.bounds.width - view.dividerThickness) * model.dividerPosition
                XCTAssertGreaterThan(expected, 10)
                XCTAssertEqual(view.arrangedSubviews[0].frame.width, expected, accuracy: 1)
                XCTAssertFalse(probe.sizes.isEmpty, "The pane must receive real geometry")
                XCTAssertEqual(probe.sizes.first?.width ?? -1, expected, accuracy: 1,
                               "The first visible width must already match the saved ratio")
            }
            XCTAssertEqual(upperState.dividerPosition, 0.60)
            XCTAssertEqual(lowerState.dividerPosition, 0.43)

            // A parent's programmatic divider move also resizes descendants.
            // Each child must lay out correctly inside that same call.
            rootCoordinator.setPositionSafely(320, in: root)
            for (view, model) in [(upper, upperState), (lower, lowerState)] {
                XCTAssertEqual(view.arrangedSubviews[0].frame.width,
                               (view.bounds.width - view.dividerThickness) * model.dividerPosition,
                               accuracy: 1)
            }

            let counts = [upperFirst.sizes.count, lowerFirst.sizes.count]
            for _ in 0..<20 { root.layoutSubtreeIfNeeded() }
            XCTAssertEqual([upperFirst.sizes.count, lowerFirst.sizes.count], counts,
                           "Unchanged layout passes must not resize panes again")
        }
    }

    func testFirstLayoutHonorsDividerRangeAndPaneMinimums() {
        _ = NSApplication.shared
        for orientation in [SplitOrientation.horizontal, .vertical] {
            let model = state(0.05, orientation: orientation)
            let (view, coordinator) = split(model, children: [PaneProbe(), PaneProbe()])
            coordinator.update(splitState: model, minimumPaneWidth: 100, minimumPaneHeight: 100,
                               dividerPositionRange: 0.2...0.8, onGeometryChange: nil)
            withExtendedLifetime(coordinator) {
                view.setFrameSize(NSSize(width: 800, height: 800))
                let first = view.arrangedSubviews[0]
                XCTAssertEqual(orientation == .horizontal ? first.frame.width : first.frame.height,
                               799 * 0.2, accuracy: 1)
                view.setFrameSize(NSSize(width: 100, height: 100))
                XCTAssertEqual(orientation == .horizontal ? first.frame.width : first.frame.height,
                               99 * 0.5, accuracy: 1)
                XCTAssertEqual(model.dividerPosition, 0.05, "Resizing must not overwrite the saved ratio")
            }
        }
    }
}
