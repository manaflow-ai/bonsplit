import AppKit

/// Ground-truth exits for a tab drag that never reaches a SwiftUI drop callback.
/// Event callbacks enqueue cancellation after returning so AppKit can finish
/// delivering a real drop first; the session generation rejects stale callbacks.
@MainActor
final class TabDragLifecycleMonitor {
    private static let escapeKeyCode: UInt16 = 53

    private let generation: Int
    private let onRequestEnd: @MainActor (Int) -> Void
    private var appResignObserver: (any NSObjectProtocol)?
    private var keyDownMonitor: Any?
    private var localMouseUpMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var endRequested = false
    private var isStopped = false

    init(generation: Int, onRequestEnd: @escaping @MainActor (Int) -> Void) {
        self.generation = generation
        self.onRequestEnd = onRequestEnd
    }

    func start() {
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.requestEnd()
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == Self.escapeKeyCode {
                self?.requestEnd()
            }
            return event
        }
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.requestEnd()
            return event
        }
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.requestEnd()
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
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

    private nonisolated func requestEnd() {
        Task { @MainActor [weak self] in
            guard let self, !self.isStopped, !self.endRequested else { return }
            self.endRequested = true
            self.onRequestEnd(self.generation)
        }
    }
}
