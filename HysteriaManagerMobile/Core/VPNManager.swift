import Foundation
import NetworkExtension
import Combine
import WidgetKit

/// Drives the on-device VPN via `NETunnelProviderManager`: installs the tunnel
/// profile, writes the generated sing-box config to the App Group, and starts/stops
/// the packet-tunnel extension. Connection status comes from `NEVPNStatus`.
@MainActor
final class VPNManager: ObservableObject {
    static let tunnelBundleID = "com.isaacclarke.HysteriaManagerMobile.tunnel"

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published var lastError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var lastPingMs: Int?
    @Published private(set) var isPinging = false

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?
    private var activeServerName = "—"
    private var activeTailscaleOn = false

    var isActive: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    init() {
        Task { await refresh() }
    }

    /// Load the existing tunnel profile (if any) and start observing its status.
    func refresh() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let mine = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == Self.tunnelBundleID }
            if let mine {
                manager = mine
                observe(mine)
                status = mine.connection.status
            }
        } catch {
            lastError = error.localizedDescription
        }
        updateSnapshot()
    }

    // MARK: - Connect / disconnect

    func connect(store: MobileStore) async {
        guard !store.connections.filter({ $0.enabled && !$0.server.isEmpty }).isEmpty else {
            lastError = "Add and enable at least one connection first."
            return
        }
        activeServerName = store.activeConnection?.name ?? store.connections.first?.name ?? "—"
        activeTailscaleOn = store.settings.tailscaleEnabled &&
            !store.settings.tailscaleAuthKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isBusy = true
        defer { isBusy = false }
        do {
            try writeConfig(store: store)
            let mgr = try await loadOrCreateManager(store: store)
            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()   // refresh to get a live connection object
            observe(mgr)
            manager = mgr
            try (mgr.connection as? NETunnelProviderSession)?.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        (manager?.connection as? NETunnelProviderSession)?.stopVPNTunnel()
    }

    /// Timed request to a test URL. When connected this travels through the tunnel,
    /// so it reflects real proxy latency.
    func ping(urlString: String) async {
        // iOS App Transport Security blocks cleartext http:// — use https for the probe.
        var s = urlString
        if s.hasPrefix("http://") { s = "https://" + s.dropFirst("http://".count) }
        guard let url = URL(string: s) else { return }
        isPinging = true
        defer { isPinging = false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                lastPingMs = Int(Date().timeIntervalSince(start) * 1000)
            } else {
                lastPingMs = nil
            }
        } catch {
            lastPingMs = nil
        }
        updateSnapshot()
    }

    func toggle(store: MobileStore) async {
        if isActive { disconnect() } else { await connect(store: store) }
    }

    /// Regenerate the config and hot-reload the running tunnel (used after changing
    /// the selected profile or routing mode while connected).
    func reload(store: MobileStore) async {
        do {
            try writeConfig(store: store)
            if isActive, let session = manager?.connection as? NETunnelProviderSession {
                try? session.sendProviderMessage(Data("reload".utf8)) { _ in }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Internals

    private func writeConfig(store: MobileStore) throws {
        AppGroup.ensureDirectories()
        let data = SingboxConfigBuilder.build(connections: store.connections, settings: store.settings)
        try data.write(to: AppGroup.configURL, options: .atomic)
    }

    private func loadOrCreateManager(store: MobileStore) async throws -> NETunnelProviderManager {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let mgr = managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.tunnelBundleID
        } ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleID
        proto.serverAddress = store.activeConnection?.host ?? "hysteria2"
        proto.providerConfiguration = [:]   // config is delivered via the App Group file
        mgr.protocolConfiguration = proto
        mgr.localizedDescription = "Hysteria Manager"
        mgr.isEnabled = true

        if store.settings.onDemandEnabled {
            mgr.isOnDemandEnabled = true
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            mgr.onDemandRules = [rule]
        } else {
            mgr.isOnDemandEnabled = false
            mgr.onDemandRules = []
        }
        return mgr
    }

    private func observe(_ mgr: NETunnelProviderManager) {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        status = mgr.connection.status
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: mgr.connection,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.status = mgr.connection.status
                self?.updateSnapshot()
            }
        }
    }

    /// Publish current state to the App Group + refresh the homescreen widget.
    private func updateSnapshot() {
        let existing = SharedState.load()
        let snap = VPNSnapshot(
            connected: status == .connected,
            connecting: status == .connecting || status == .reasserting,
            serverName: activeServerName == "—" ? existing.serverName : activeServerName,
            lastPingMs: lastPingMs ?? existing.lastPingMs,
            tailscaleOn: activeTailscaleOn,
            updated: Date()
        )
        SharedState.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    var statusText: String {
        switch status {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .reasserting:  return "Reconnecting…"
        case .disconnected: return "Disconnected"
        case .invalid:      return "Not configured"
        @unknown default:   return "Unknown"
        }
    }
}
