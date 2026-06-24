import WidgetKit
import SwiftUI
import AppIntents
import NetworkExtension

// MARK: - Timeline

struct VPNEntry: TimelineEntry {
    let date: Date
    let snapshot: VPNSnapshot
}

struct VPNProvider: TimelineProvider {
    func placeholder(in _: Context) -> VPNEntry {
        VPNEntry(date: Date(), snapshot: VPNSnapshot(connected: true, serverName: "My Server", lastPingMs: 42))
    }

    func getSnapshot(in _: Context, completion: @escaping (VPNEntry) -> Void) {
        completion(VPNEntry(date: Date(), snapshot: SharedState.load()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<VPNEntry>) -> Void) {
        Task {
            let entry = await liveEntry()
            // Ask iOS to refresh ~every 100s (it throttles widget refreshes, so this is
            // best-effort; tapping the widget or opening the app refreshes immediately).
            let next = Date().addingTimeInterval(100)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Reads the LIVE VPN status (so it can't disagree with the app), pings if up, and
    /// pulls server name + Tailscale state from the shared snapshot.
    private func liveEntry() async -> VPNEntry {
        var snap = SharedState.load()

        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        let mgr = managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppGroup.tunnelBundleID
        }
        let status = mgr?.connection.status ?? .invalid
        if status != .invalid {
            // Live status wins. If we can't read it (.invalid), keep the app's snapshot.
            snap.connected = (status == .connected)
            snap.connecting = (status == .connecting || status == .reasserting)
        }

        if snap.connected, let ms = await ping() {
            snap.lastPingMs = ms
        }

        SharedState.save(snap)   // keep the app's view in sync too
        return VPNEntry(date: Date(), snapshot: snap)
    }

    private func ping() async -> Int? {
        guard let url = URL(string: "https://www.gstatic.com/generate_204") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = Date()
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
            return Int(Date().timeIntervalSince(start) * 1000)
        }
        return nil
    }
}

// MARK: - Styling

private let brand = LinearGradient(
    colors: [Color(red: 0.055, green: 0.647, blue: 0.914), Color(red: 0.427, green: 0.157, blue: 0.851)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

private extension VPNSnapshot {
    var statusText: String { connected ? "Connected" : (connecting ? "Connecting…" : "Off") }
    var statusColor: Color { connected ? .green : (connecting ? .yellow : .secondary) }
    var pingText: String { lastPingMs.map { "\($0) ms" } ?? "— ms" }
    var showTailscale: Bool { tailscaleOn && connected }
}

// MARK: - Views

struct HysteriaWidgetEntryView: View {
    var entry: VPNEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    // Display-only. A StaticConfiguration widget opens the containing app when tapped.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "bolt.horizontal.fill").font(.title3.bold()).foregroundStyle(brand)
                Spacer()
                Circle().fill(entry.snapshot.statusColor).frame(width: 10, height: 10)
            }
            Spacer()
            Text(entry.snapshot.statusText).font(.headline)
            Text(entry.snapshot.serverName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                if entry.snapshot.connected {
                    Label(entry.snapshot.pingText, systemImage: "wave.3.right")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                if entry.snapshot.showTailscale {
                    Image(systemName: "shield.lefthalf.filled").font(.caption2).foregroundStyle(.teal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.fill").foregroundStyle(brand)
                    Text("Hysteria").font(.headline)
                }
                HStack(spacing: 8) {
                    Circle().fill(entry.snapshot.statusColor).frame(width: 10, height: 10)
                    Text(entry.snapshot.statusText).font(.title3.bold())
                }
                Text(entry.snapshot.serverName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if entry.snapshot.connected {
                    Label(entry.snapshot.pingText, systemImage: "wave.3.right")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                if entry.snapshot.showTailscale {
                    Label("Tailscale", systemImage: "shield.lefthalf.filled")
                        .font(.caption).foregroundStyle(.teal)
                }
                Spacer(minLength: 0)
                Text("Tap to open").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Widget

struct HysteriaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HysteriaWidget", provider: VPNProvider()) { entry in
            HysteriaWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hysteria")
        .description("Connect, disconnect, and ping.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
