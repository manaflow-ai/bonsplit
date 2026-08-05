#if DEBUG
import Foundation
import os

/// Unified ring-buffer event log for key, mouse, focus, and split events.
/// Writes every entry to a debug log path so `tail -f` works in real time.
nonisolated public final class DebugEventLog: Sendable {
    public static let shared = DebugEventLog()

    private struct State {
        var entries: [String] = []
        var externalSink: (@Sendable (String) -> Void)?
        var appendHandle: FileHandle?
        let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    private let capacity = 500
    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let logPath = resolveLogPath()

    /// When set, lines are handed to this closure instead of appended here.
    /// A host app whose own debug log writes to the same file installs a
    /// sink at startup so the file has exactly one serialized append path;
    /// two independent appenders interleave and reorder lines under load.
    /// Routes every subsequent line to `sink` (or back to the built-in file
    /// append when `nil`). The sink receives the raw message, without the
    /// timestamp prefix, so the receiving log applies its own line format.
    public static func setExternalSink(_ sink: (@Sendable (String) -> Void)?) {
        shared.state.withLock { state in
            state.externalSink = sink
        }
    }

    private static func sanitizePathToken(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let unicode = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(unicode).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return sanitized.isEmpty ? "debug" : sanitized
    }

    private static func resolveLogPath() -> String {
        let env = ProcessInfo.processInfo.environment

        if let explicit = env["CMUX_DEBUG_LOG"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }

        if let tag = env["CMUX_TAG"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tag.isEmpty {
            return "/tmp/cmux-debug-\(sanitizePathToken(tag)).log"
        }

        if let socketPath = env["CMUX_SOCKET_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !socketPath.isEmpty {
            let socketBase = URL(fileURLWithPath: socketPath).deletingPathExtension().lastPathComponent
            if socketBase.hasPrefix("cmux-debug-") {
                return "/tmp/\(socketBase).log"
            }
        }

        if let bundleId = Bundle.main.bundleIdentifier,
           bundleId != "com.cmuxterm.app.debug" {
            return "/tmp/cmux-debug-\(sanitizePathToken(bundleId)).log"
        }

        return "/tmp/cmux-debug.log"
    }

    public func log(_ msg: String) {
        state.withLock { state in
            if let sink = state.externalSink {
                sink(msg)
                return
            }
            let ts = state.formatter.string(from: Date())
            let entry = "\(ts) \(msg)"
            if state.entries.count >= capacity {
                state.entries.removeFirst()
            }
            state.entries.append(entry)
            // Append to file for real-time tail -f
            guard let data = (entry + "\n").data(using: .utf8) else { return }
            if state.appendHandle == nil {
                let fd = open(Self.logPath, O_WRONLY | O_APPEND | O_CREAT, 0o644)
                if fd >= 0 {
                    state.appendHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                }
            }
            guard let handle = state.appendHandle else { return }
            do {
                try handle.write(contentsOf: data)
            } catch {
                // The file may have been rotated away; reopen on the next line.
                state.appendHandle = nil
            }
        }
    }

    /// Write all buffered entries to the log file (full dump, replacing contents).
    public func dump() {
        state.withLock { state in
            // With a sink installed the receiving log owns the file; replacing
            // its contents here would throw away the other writer's lines.
            if state.externalSink != nil { return }
            // The atomic write replaces the inode; reopen the handle lazily.
            try? state.appendHandle?.close()
            state.appendHandle = nil
            let content = state.entries.joined(separator: "\n") + "\n"
            try? content.write(toFile: Self.logPath, atomically: true, encoding: .utf8)
        }
    }
}

/// Convenience free function. Logs the message and appends to the configured debug log path.
nonisolated public func dlog(_ msg: String) {
    DebugEventLog.shared.log(msg)
}
#endif
