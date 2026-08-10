import Foundation
import Testing

@testable import Bonsplit

@Suite(.serialized)
struct DeferredActionOwnershipTests {
    /// Lock-protected because task-context destruction may occur off-main.
    private final class ReleaseStackRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var minimumAddress = UInt.max
        private var maximumAddress: UInt = 0
        private var releaseCount = 0

        func record(address: UInt, isMainThread: Bool) {
            lock.lock()
            releaseCount += 1
            if isMainThread {
                minimumAddress = min(minimumAddress, address)
                maximumAddress = max(maximumAddress, address)
            }
            lock.unlock()
        }

        var snapshot: (count: Int, addressSpan: UInt) {
            lock.lock()
            defer { lock.unlock() }
            let span = minimumAddress == UInt.max ? 0 : maximumAddress - minimumAddress
            return (releaseCount, span)
        }
    }

    private final class ClosureLifetimeProbe {
        let identifier: Int
        let recorder: ReleaseStackRecorder
        let deinitialized: AsyncStream<Int>.Continuation

        init(
            identifier: Int,
            recorder: ReleaseStackRecorder,
            deinitialized: AsyncStream<Int>.Continuation
        ) {
            self.identifier = identifier
            self.recorder = recorder
            self.deinitialized = deinitialized
        }

        deinit {
            var stackMarker: UInt8 = 0
            let address = withUnsafePointer(to: &stackMarker) {
                UInt(bitPattern: UnsafeRawPointer($0))
            }
            recorder.record(address: address, isMainThread: Thread.isMainThread)
            deinitialized.yield(identifier)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func schedulerReplacementBurstKeepsReleaseStackBounded() async throws {
        let replacementCount = 5_000
        let recorder = ReleaseStackRecorder()
        let deinitializations = AsyncStream<Int>.makeStream()
        defer { deinitializations.continuation.finish() }
        var deinitializationIterator = deinitializations.stream.makeAsyncIterator()
        let actions = AsyncStream<Int>.makeStream()
        defer { actions.continuation.finish() }
        var actionIterator = actions.stream.makeAsyncIterator()
        let scheduler = TabIconFallbackScheduler()

        for identifier in 0..<replacementCount {
            let probe = ClosureLifetimeProbe(
                identifier: identifier,
                recorder: recorder,
                deinitialized: deinitializations.continuation
            )
            scheduler.schedule(after: .zero) { [probe] in
                _ = probe
                actions.continuation.yield(identifier)
            }
        }

        let fired = try #require(await actionIterator.next())
        #expect(fired == replacementCount - 1)

        var deinitializedIdentifiers: Set<Int> = []
        for _ in 0..<replacementCount {
            let identifier = try #require(await deinitializationIterator.next())
            deinitializedIdentifiers.insert(identifier)
        }
        #expect(deinitializedIdentifiers == Set(0..<replacementCount))

        let snapshot = recorder.snapshot
        #expect(snapshot.count == replacementCount)
        #expect(snapshot.addressSpan < 512 * 1_024)
    }
}
