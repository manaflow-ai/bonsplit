import AppKit
import SwiftUI
import Testing
@testable import Bonsplit

@Suite("Tab bar host window lifetime")
@MainActor
struct TabBarHostWindowLifetimeTests {
    private final class ReentrantTeardownWindow: NSWindow {
        deinit {
            // Model AppKit draining pending main-queue work while the window
            // is deallocating but its content view is still attached.
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
    }

    @Test("Deferred tab hint lookup tolerates window deallocation")
    func deferredLookupDuringWindowDeallocation() async {
        _ = NSApplication.shared
        let released = await withCheckedContinuation { continuation in
            // A run-loop callback permits reentrant dispatch during teardown;
            // dispatching this block itself would keep the main queue occupied.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
                MainActor.assumeIsolated {
                    continuation.resume(returning: Self.releaseHostedWindow())
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        #expect(released)
    }

    private static func releaseHostedWindow() -> Bool {
        weak var releasedWindow: NSWindow?
        autoreleasepool {
            let controller = BonsplitController()
            controller.createTab(title: "Lifetime probe")
            let window = ReentrantTeardownWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            releasedWindow = window
            window.contentView = NSHostingView(rootView:
                BonsplitView(controller: controller) { _, _ in Color.clear }
            )
            window.contentView?.layoutSubtreeIfNeeded()
        }
        return releasedWindow == nil
    }
}
