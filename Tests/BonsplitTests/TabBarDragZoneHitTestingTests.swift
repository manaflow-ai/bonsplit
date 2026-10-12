import AppKit
import XCTest
@testable import Bonsplit

final class TabBarDragZoneHitTestingTests: XCTestCase {
    func testHitTestConvertsTranslatedDragZoneOrigin() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        window.contentView = contentView

        let dragZone = TabBarDragZoneView.DragNSView(
            frame: NSRect(x: 96, y: 72, width: 120, height: 28)
        )
        dragZone.hitRegion = .entireBounds
        dragZone.hitTestEventTypeOverride = .leftMouseDown
        contentView.addSubview(dragZone)
        window.makeKeyAndOrderFront(nil)

        let localPoint = NSPoint(x: 48, y: 14)
        let windowPoint = dragZone.convert(localPoint, to: nil)
        let superviewPoint = contentView.convert(windowPoint, from: nil)

        XCTAssertIdentical(
            dragZone.hitTest(superviewPoint),
            dragZone,
            "A translated drag-zone overlay must evaluate the AppKit hit point in local coordinates."
        )
    }

    func testLeadingChromeDoesNotCaptureWhileTabFramesAreTemporarilyMissing() {
        let bounds = CGRect(x: 0, y: 0, width: 80, height: 28)

        XCTAssertFalse(
            TabBarDragZoneHitTesting.shouldCaptureLeadingChrome(
                at: CGPoint(x: 24, y: 14),
                bounds: bounds,
                tabFrames: [],
                hasTabs: true
            ),
            "A visible tab must not be swallowed by the titlebar drag lane while geometry is catching up."
        )
    }

    func testTrailingChromeStillCapturesAfterKnownTabFrames() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 28)
        let tabFrame = CGRect(x: 8, y: 0, width: 72, height: 28)

        XCTAssertTrue(
            TabBarDragZoneHitTesting.shouldCaptureTrailingEmptyChrome(
                at: CGPoint(x: 180, y: 14),
                bounds: bounds,
                tabFrames: [tabFrame],
                reservedTrailingWidth: 0
            )
        )
        XCTAssertFalse(
            TabBarDragZoneHitTesting.shouldCaptureTrailingEmptyChrome(
                at: CGPoint(x: 40, y: 14),
                bounds: bounds,
                tabFrames: [tabFrame],
                reservedTrailingWidth: 0
            )
        )
    }

    func testTrailingChromeDoesNotCaptureWhileTabFramesAreTemporarilyMissing() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 28)

        XCTAssertFalse(
            TabBarDragZoneHitTesting.shouldCaptureTrailingEmptyChrome(
                at: CGPoint(x: 180, y: 14),
                bounds: bounds,
                tabFrames: [],
                reservedTrailingWidth: 0,
                tabFramesReady: false
            ),
            "The empty-chrome overlay must yield while a non-empty tab strip is missing live geometry."
        )
    }
}
