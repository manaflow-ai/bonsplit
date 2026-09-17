import Foundation

#if DEBUG
/// Debug-only counters for Bonsplit internal behavior.
///
/// These are intended for automated tests (via cmuxterm's debug socket) to
/// detect transient structural updates that can cause visible flashes.
public enum BonsplitDebugCounters {
    public private(set) static var arrangedSubviewUnderflowCount: Int = 0

    struct HotPathActivity: Equatable {
        fileprivate(set) var splitActionSystemImageLookupCount = 0
        fileprivate(set) var tabItemTypeConstructionCount = 0
        fileprivate(set) var tabTransferTypeConstructionCount = 0
        fileprivate(set) var faviconImageDecodeCount = 0
    }

    private final class HotPathRecorder: NSObject {
        var activity = HotPathActivity()
    }

    private static let hotPathRecorderKey = "com.manaflow.bonsplit.hot-path-recorder"

    public static func reset() {
        arrangedSubviewUnderflowCount = 0
    }

    internal static func recordArrangedSubviewUnderflow() {
        arrangedSubviewUnderflowCount += 1
    }

    static func measureHotPathActivity(_ body: () -> Void) -> HotPathActivity {
        let threadDictionary = Thread.current.threadDictionary
        precondition(threadDictionary[hotPathRecorderKey] == nil)

        let recorder = HotPathRecorder()
        threadDictionary[hotPathRecorderKey] = recorder
        defer { threadDictionary.removeObject(forKey: hotPathRecorderKey) }

        body()
        return recorder.activity
    }

    static func recordSplitActionSystemImageLookup() {
        currentHotPathRecorder?.activity.splitActionSystemImageLookupCount += 1
    }

    static func recordTabItemTypeConstruction() {
        currentHotPathRecorder?.activity.tabItemTypeConstructionCount += 1
    }

    static func recordTabTransferTypeConstruction() {
        currentHotPathRecorder?.activity.tabTransferTypeConstructionCount += 1
    }

    static func recordFaviconImageDecode() {
        currentHotPathRecorder?.activity.faviconImageDecodeCount += 1
    }

    private static var currentHotPathRecorder: HotPathRecorder? {
        Thread.current.threadDictionary[hotPathRecorderKey] as? HotPathRecorder
    }
}
#endif
