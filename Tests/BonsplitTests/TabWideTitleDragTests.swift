import CoreGraphics
import Testing
@testable import Bonsplit

@Suite("Wide tab drag hit testing")
struct TabWideTitleDragTests {
    private let resolver = TabDropIndexResolver()
    private let bounds = CGRect(x: 0, y: 0, width: 1_400, height: 34)

    @Test("A wide source tab keeps midpoint insertion boundaries stable")
    func wideSourceTabUsesStableMidpoints() {
        let tabFrames = [
            CGRect(x: 12, y: 0, width: 84, height: 34),
            // Models a long directory or agent-session title.
            CGRect(x: 104, y: 0, width: 760, height: 34),
            CGRect(x: 876, y: 0, width: 120, height: 34),
            CGRect(x: 1_004, y: 0, width: 132, height: 34),
        ]
        let probes: [(x: CGFloat, expectedIndex: Int)] = [
            (20, 0),
            (54, 1),
            (120, 1),
            (483.9, 1),
            (484, 2),
            (700, 2),
            (875.9, 2),
            (936, 3),
            (1_200, 4),
        ]

        for probe in probes {
            let resolvedIndex = resolver.insertionIndex(
                at: CGPoint(x: probe.x, y: bounds.midY),
                in: bounds,
                tabFrames: tabFrames
            )
            #expect(resolvedIndex == probe.expectedIndex)
        }
    }

    @Test("Short-title tabs retain the ordinary insertion slots")
    func shortTitleControlUsesExpectedMidpoints() {
        let tabFrames = [
            CGRect(x: 12, y: 0, width: 80, height: 34),
            CGRect(x: 100, y: 0, width: 120, height: 34),
            CGRect(x: 228, y: 0, width: 72, height: 34),
        ]

        #expect(resolver.insertionIndex(
            at: CGPoint(x: 51.9, y: bounds.midY),
            in: bounds,
            tabFrames: tabFrames
        ) == 0)
        #expect(resolver.insertionIndex(
            at: CGPoint(x: 52, y: bounds.midY),
            in: bounds,
            tabFrames: tabFrames
        ) == 1)
        #expect(resolver.insertionIndex(
            at: CGPoint(x: 160, y: bounds.midY),
            in: bounds,
            tabFrames: tabFrames
        ) == 2)
        #expect(resolver.insertionIndex(
            at: CGPoint(x: 264, y: bounds.midY),
            in: bounds,
            tabFrames: tabFrames
        ) == 3)
    }
}
