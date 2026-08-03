import CoreGraphics
import Foundation
import os

#if DEBUG
enum TabGeometryDebugLog {
    static let isEnabled = ProcessInfo.processInfo.environment["CMUX_TAB_GEOMETRY_LOG"] != nil

    private static let sink = OSAllocatedUnfairLock(initialState: TabGeometryDebugLogSink())

    static func geometry(
        tabId: UUID,
        which: String,
        frame: CGRect,
        tabWidth: CGFloat?,
        tab: TabItem,
        isSelected: Bool,
        showsShortcutHint: Bool
    ) {
        guard isEnabled else { return }
        sink.withLock { sink in
            sink.write(
                tabId: tabId,
                event: "geom",
                fields: [
                    "which=\(escaped(which))",
                    "x=\(format(frame.origin.x))",
                    "y=\(format(frame.origin.y))",
                    "w=\(format(frame.width))",
                    "tabW=\(format(tabWidth))",
                    "title=\(escaped(truncated(tab.title)))",
                    "icon=\(escaped(optional: tab.icon))",
                    "iconAsset=\(escaped(optional: tab.iconAsset))",
                    "loading=\(tab.isLoading)",
                    "badge=\(tab.showsNotificationBadge)",
                    "sel=\(isSelected)",
                    "hint=\(showsShortcutHint)",
                ]
            )
        }
    }

    static func stateChange(
        tabId: UUID,
        field: String,
        oldValue: String,
        newValue: String,
        tab: TabItem,
        isSelected: Bool,
        showsShortcutHint: Bool
    ) {
        guard isEnabled else { return }
        sink.withLock { sink in
            sink.write(
                tabId: tabId,
                event: "state",
                fields: [
                    "field=\(escaped(field))",
                    "old=\(escaped(oldValue))",
                    "new=\(escaped(newValue))",
                    "change=\(escaped(oldValue))->\(escaped(newValue))",
                    "title=\(escaped(truncated(tab.title)))",
                    "icon=\(escaped(optional: tab.icon))",
                    "iconAsset=\(escaped(optional: tab.iconAsset))",
                    "loading=\(tab.isLoading)",
                    "badge=\(tab.showsNotificationBadge)",
                    "sel=\(isSelected)",
                    "hint=\(showsShortcutHint)",
                ]
            )
        }
    }

    static func optional(_ value: String?) -> String {
        value ?? "<nil>"
    }

    static func optional(_ value: Bool?) -> String {
        value.map(String.init) ?? "<nil>"
    }

    private static func format(_ value: CGFloat?) -> String {
        guard let value else { return "unknown" }
        return String(format: "%.3f", Double(value))
    }

    private static func truncated(_ value: String) -> String {
        String(value.prefix(24))
    }

    private static func escaped(optional value: String?) -> String {
        escaped(optional(value))
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

private struct TabGeometryDebugLogSink: Sendable {
    private let path = "/tmp/cmux-tab-geometry.log"
    private var handle: FileHandle?
    private var wroteHeader = false
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    mutating func write(tabId: UUID, event: String, fields: [String]) {
        writeHeaderIfNeeded()
        let lineFields = [
            "ts=\(timestampFormatter.string(from: Date()))",
            "tab=\(String(tabId.uuidString.prefix(8)))",
            "ev=\(event)",
        ] + fields
        append(lineFields.joined(separator: "\t"))
    }

    private mutating func writeHeaderIfNeeded() {
        guard !wroteHeader else { return }
        wroteHeader = true
        append([
            "ts=\(timestampFormatter.string(from: Date()))",
            "tab=session",
            "ev=session",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "bundle=\(Bundle.main.bundleIdentifier ?? "<nil>")",
        ].joined(separator: "\t"))
    }

    private mutating func append(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8),
              let handle = fileHandle() else {
            return
        }
        try? handle.write(contentsOf: data)
    }

    private mutating func fileHandle() -> FileHandle? {
        if let handle { return handle }
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let opened = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
            return nil
        }
        _ = try? opened.seekToEnd()
        handle = opened
        return opened
    }
}
#else
enum TabGeometryDebugLog {
    static let isEnabled = false

    static func geometry(
        tabId: UUID,
        which: String,
        frame: CGRect,
        tabWidth: CGFloat?,
        tab: TabItem,
        isSelected: Bool,
        showsShortcutHint: Bool
    ) {}

    static func stateChange(
        tabId: UUID,
        field: String,
        oldValue: String,
        newValue: String,
        tab: TabItem,
        isSelected: Bool,
        showsShortcutHint: Bool
    ) {}

    static func optional(_ value: String?) -> String {
        value ?? "<nil>"
    }

    static func optional(_ value: Bool?) -> String {
        value.map(String.init) ?? "<nil>"
    }
}
#endif
