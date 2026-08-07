import AppKit

/// Ground-truth exits for a tab drag that never reaches a SwiftUI drop callback.
/// AppKit delivers event-monitor callbacks on the main thread, so one synchronous
/// bridge ends the matching generation without a deferred cleanup race.
@MainActor
final class TabDragLifecycleMonitor {
    private struct Registrations {
        var appResignObserver: (any NSObjectProtocol)?
        var keyDownMonitor: Any?
        var localMouseUpMonitor: Any?
        var globalMouseUpMonitor: Any?

        mutating func removeAll() {
            if let appResignObserver {
                NotificationCenter.default.removeObserver(appResignObserver)
                self.appResignObserver = nil
            }
            if let keyDownMonitor {
                NSEvent.removeMonitor(keyDownMonitor)
                self.keyDownMonitor = nil
            }
            if let localMouseUpMonitor {
                NSEvent.removeMonitor(localMouseUpMonitor)
                self.localMouseUpMonitor = nil
            }
            if let globalMouseUpMonitor {
                NSEvent.removeMonitor(globalMouseUpMonitor)
                self.globalMouseUpMonitor = nil
            }
        }
    }

    private static let escapeKeyCode: UInt16 = 53

    private let generation: Int
    private let onRequestEnd: @MainActor (Int) -> Void
    private var registrations = Registrations()
    private var endRequested = false
    private var isStopped = false

    init(generation: Int, onRequestEnd: @escaping @MainActor (Int) -> Void) {
        self.generation = generation
        self.onRequestEnd = onRequestEnd
    }

    isolated deinit {
        registrations.removeAll()
    }

    func start() {
        registrations.appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestEndFromMainThreadCallback()
        }
        registrations.keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == Self.escapeKeyCode {
                self?.requestEndFromMainThreadCallback()
            }
            return event
        }
        registrations.localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.requestEndFromMainThreadCallback()
            return event
        }
        registrations.globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.requestEndFromMainThreadCallback()
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        registrations.removeAll()
    }

    private nonisolated func requestEndFromMainThreadCallback() {
        MainActor.assumeIsolated {
            requestEnd()
        }
    }

    private func requestEnd() {
        guard !isStopped, !endRequested else { return }
        endRequested = true
        onRequestEnd(generation)
    }
}
