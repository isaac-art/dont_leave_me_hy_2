import Foundation

/// Tiny snapshot the app writes and the widget reads (via App Group UserDefaults).
/// Keeps the widget instant — it never has to talk to the Network Extension to draw.
struct VPNSnapshot: Codable {
    var connected: Bool = false
    var connecting: Bool = false
    var serverName: String = "—"
    var lastPingMs: Int? = nil
    var tailscaleOn: Bool = false
    var updated: Date = Date(timeIntervalSince1970: 0)
}

enum SharedState {
    private static let key = "vpnSnapshot"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }

    static func save(_ snapshot: VPNSnapshot) {
        guard let d = defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        d.set(data, forKey: key)
    }

    static func load() -> VPNSnapshot {
        guard let d = defaults, let data = d.data(forKey: key),
              let s = try? JSONDecoder().decode(VPNSnapshot.self, from: data) else { return VPNSnapshot() }
        return s
    }
}
