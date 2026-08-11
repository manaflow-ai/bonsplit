/// Owns the replaceable delay used before showing a tab's fallback globe.
///
/// The queued task captures this owner weakly. Replacement cancels and drops
/// the previous task before constructing its successor, so a successor closure
/// cannot retain a predecessor through a SwiftUI view snapshot.
@MainActor
final class TabIconFallbackScheduler {
    private let clock: any Clock<Duration>
    private var pendingTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func cancel() {
        generation &+= 1
        pendingTask?.cancel()
        pendingTask = nil
    }

    func schedule(
        after delay: Duration,
        _ action: @escaping @MainActor () -> Void
    ) {
        cancel()

        let scheduledGeneration = generation
        pendingTask = Task { @MainActor [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard let self, generation == scheduledGeneration else { return }
            pendingTask = nil
            action()
        }
    }

    deinit {
        pendingTask?.cancel()
    }
}
