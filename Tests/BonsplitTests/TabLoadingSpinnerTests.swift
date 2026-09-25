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
    let window = NSWindow(
        contentRect: contentView.bounds,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.contentView = contentView
    contentView.addSubview(spinner)
    spinner.configure(size: 12, color: .labelColor)

    #expect(spinner.activeRotationAnimationForTesting != nil)

    spinner.configure(size: 12, color: .labelColor)
    // Simulate SwiftUI/AppKit stripping the animation while the visible view remains attached.
    spinner.removeRotationAnimationForTesting()

    #expect(spinner.activeRotationAnimationForTesting == nil)

    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    withExtendedLifetime(window) {
        #expect(spinner.activeRotationAnimationForTesting != nil)
    }
}
