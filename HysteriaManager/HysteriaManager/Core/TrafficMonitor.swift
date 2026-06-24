import Foundation

/// Best-effort per-process throughput sampling via `nettop`.
///
/// `nettop` in logging mode prints the *incremental* bytes transferred between
/// samples, so two samples one second apart give us a bytes/second rate for the
/// hysteria process. This is approximate (and returns nil if nettop output can't
/// be parsed), so the UI treats it as informational.
enum TrafficMonitor {

    struct Sample {
        /// Upload rate (bytes/sec) — bytes_out.
        var upBytesPerSec: UInt64
        /// Download rate (bytes/sec) — bytes_in.
        var downBytesPerSec: UInt64
    }

    /// Blocks for ~1 second (two nettop samples). Call from a detached Task.
    static func sample(pid: Int32) -> Sample? {
        let result = Shell.run("/usr/bin/nettop", [
            "-P",                       // per-process
            "-p", "\(pid)",             // filter to our pid
            "-x",                       // raw byte values (no human formatting)
            "-J", "bytes_in,bytes_out", // only the columns we need
            "-L", "2",                  // two samples...
            "-s", "1",                  // ...one second apart
        ])
        guard result.status == 0 else { return nil }

        // Keep only data rows for our pid; the last one is the incremental sample.
        let rows = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains(".\(pid)") || $0.contains(",\(pid)") }

        guard let last = rows.last else { return nil }
        let ints = last
            .split(separator: ",")
            .compactMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }

        // Expect [bytes_in, bytes_out] following the process-name column.
        guard ints.count >= 2 else { return nil }
        return Sample(upBytesPerSec: ints[1], downBytesPerSec: ints[0])
    }

    /// Human-readable byte rate, e.g. "1.2 MB/s".
    static func formatRate(_ bytesPerSec: UInt64) -> String {
        formatBytes(bytesPerSec) + "/s"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1024 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0 ? "\(Int(value)) \(units[unit])" : String(format: "%.1f %@", value, units[unit])
    }
}
