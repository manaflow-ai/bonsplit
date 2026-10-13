import Foundation
// TEMPORARY PROBE for CMUXTERM-MACOS-41NN; not for merge.
enum ProbeCounters {
    nonisolated(unsafe) static var tabItemBody = 0
    nonisolated(unsafe) static var tabBarBody = 0
    nonisolated(unsafe) static var tabBarInit = 0
    nonisolated(unsafe) static var paneBody = 0
    nonisolated(unsafe) static var monitorInit = 0
    nonisolated(unsafe) static var tabItemBodyNs: UInt64 = 0
    nonisolated(unsafe) static var tabBarBodyNs: UInt64 = 0
    nonisolated(unsafe) static var tabBarInitNs: UInt64 = 0
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func reset() { tabItemBody = 0; tabBarBody = 0; tabBarInit = 0; paneBody = 0; monitorInit = 0; tabItemBodyNs = 0; tabBarBodyNs = 0; tabBarInitNs = 0 }
    static var summary: String { "tabItemBody=\(tabItemBody) tabBarBody=\(tabBarBody) tabBarInit=\(tabBarInit) paneBody=\(paneBody) monitorInit=\(monitorInit) tabItemBodyUs=\(tabItemBodyNs/1000) tabBarBodyUs=\(tabBarBodyNs/1000) tabBarInitUs=\(tabBarInitNs/1000)" }
}
