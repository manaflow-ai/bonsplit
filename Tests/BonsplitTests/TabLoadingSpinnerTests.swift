import AppKit
import Testing
@testable import Bonsplit

@Test("A visible loading spinner recovers when its rotation animation is stripped")
@MainActor
func visibleLoadingSpinnerRecoversAfterAnimationRemoval() throws {
    let spinner = TabLoadingSpinnerLayerView(
        frame: NSRect(x: 4, y: 4, width: 12, height: 12)
    )
    let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    let firstContainer = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    let secondContainer = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
    let window = NSWindow(
        contentRect: contentView.bounds,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = contentView
    contentView.addSubview(firstContainer)
    contentView.addSubview(secondContainer)
    firstContainer.addSubview(spinner)
    spinner.configure(size: 12, color: .labelColor)

    #expect(spinner.activeRotationAnimationForTesting != nil)

    // Simulate SwiftUI/AppKit stripping the animation while the visible view remains attached.
    spinner.removeRotationAnimationForTesting()
    spinner.removeFromSuperview()
    secondContainer.addSubview(spinner)

    #expect(spinner.activeRotationAnimationForTesting != nil)

    // A later layer transaction can strip the animation without moving the view.
    spinner.configure(size: 12, color: .labelColor)
    spinner.removeRotationAnimationForTesting()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    withExtendedLifetime(window) {
        #expect(spinner.activeRotationAnimationForTesting != nil)
    }
}
