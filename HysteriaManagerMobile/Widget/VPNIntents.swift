import AppIntents
import NetworkExtension
import WidgetKit

private func loadManager() async -> NETunnelProviderManager? {
    let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
    return managers.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppGroup.tunnelBundleID
    }
}

/// Connect if off, disconnect if on. Tapped from the widget.
struct ToggleVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle VPN"
    static var description = IntentDescription("Connect or disconnect the Hysteria VPN.")

    func perform() async throws -> some IntentResult {
        guard let mgr = await loadManager() else {
            // Not installed yet — the user must open the app once to set it up.
            return .result()
        }
        let status = mgr.connection.status
        let active = (status == .connected || status == .connecting || status == .reasserting)
        if active {
            (mgr.connection as? NETunnelProviderSession)?.stopVPNTunnel()
        } else {
            mgr.isEnabled = true
            try? await mgr.saveToPreferences()
            try? await mgr.loadFromPreferences()
            try (mgr.connection as? NETunnelProviderSession)?.startVPNTunnel()
        }
        var snap = SharedState.load()
        snap.connecting = !active
        snap.connected = false
        SharedState.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Measure latency through the (active) tunnel and store it for the widget.
struct PingIntent: AppIntent {
    static var title: LocalizedStringResource = "Ping"
    static var description = IntentDescription("Measure latency through the proxy.")

    func perform() async throws -> some IntentResult {
        let url = URL(string: "http://www.gstatic.com/generate_204")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = Date()
        var ms: Int? = nil
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
            ms = Int(Date().timeIntervalSince(start) * 1000)
        }
        var snap = SharedState.load()
        snap.lastPingMs = ms
        SharedState.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
