import SwiftUI

/// Colored dot reflecting connection state.
struct StatusDot: View {
    let state: ConnectionState
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .help(label)
    }
    private var color: Color {
        switch state {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .error:        return .red
        case .disconnected: return .secondary
        }
    }
    private var label: String {
        switch state {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting…"
        case .error(let m): return m
        case .disconnected: return "Disconnected"
        }
    }
}

/// Small latency badge. nil ms = unknown/unreachable.
struct LatencyBadge: View {
    let ms: Int??
    var body: some View {
        Group {
            switch ms {
            case .some(.some(let value)):
                Text("\(value) ms")
                    .foregroundStyle(color(for: value))
            case .some(.none):
                Text("timeout").foregroundStyle(.red)
            case .none:
                Text("—").foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
    }
    private func color(for value: Int) -> Color {
        switch value {
        case ..<150:  return .green
        case ..<400:  return .orange
        default:      return .red
        }
    }
}

/// Up/down throughput readout.
struct TrafficLabel: View {
    let up: UInt64
    let down: UInt64
    var body: some View {
        HStack(spacing: 10) {
            Label(TrafficMonitor.formatRate(up), systemImage: "arrow.up")
            Label(TrafficMonitor.formatRate(down), systemImage: "arrow.down")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
