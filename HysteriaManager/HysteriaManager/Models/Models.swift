import Foundation

// MARK: - Routing

/// How traffic that enters the local proxy is routed.
enum RoutingMode: String, Codable, CaseIterable, Identifiable {
    /// Clash-style split: mainland-China destinations stay direct, everything else
    /// is sent through the hysteria tunnel. Implemented via hysteria's built-in ACL.
    case ruleBased
    /// Send absolutely everything through the tunnel.
    case global
    /// Don't tunnel anything (proxy stays up but routes all traffic direct). Useful
    /// for temporarily bypassing while keeping the connection warm.
    case direct

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ruleBased: return "Rule-based (CN direct)"
        case .global:    return "Global (everything proxied)"
        case .direct:    return "Direct (bypass)"
        }
    }
}

// MARK: - Obfuscation

enum ObfsType: String, Codable, CaseIterable, Identifiable {
    case none
    case salamander
    var id: String { rawValue }
    var displayName: String { self == .none ? "None" : "Salamander" }
}

// MARK: - Connection

/// A single hysteria2 (or compatible) outbound connection profile.
struct Connection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Connection"

    /// "host:port" (port optional, defaults to 443). May contain a port-hopping
    /// range, e.g. "example.com:443,5000-6000".
    var server: String = ""
    /// hysteria2 auth password.
    var auth: String = ""

    // TLS
    var sni: String = ""
    var insecure: Bool = false
    var pinSHA256: String = ""

    // Obfuscation (Salamander)
    var obfsType: ObfsType = .none
    var obfsPassword: String = ""

    // Bandwidth hints (Mbps). 0 = unset (let BBR auto-detect).
    var upMbps: Int = 0
    var downMbps: Int = 0

    // Routing
    var routingMode: RoutingMode = .ruleBased
    /// Extra ACL lines appended verbatim before the catch-all, e.g. "reject(geosite:ads)".
    var extraACL: [String] = []

    // Misc
    var fastOpen: Bool = true
    var lazy: Bool = true
    /// Optional notes shown in the UI.
    var notes: String = ""

    /// Optional override of the imported raw YAML. When set, the app uses this
    /// verbatim instead of generating config from the structured fields. Lets power
    /// users paste a hand-tuned config while still managing it from the UI.
    var rawConfigOverride: String? = nil

    var host: String {
        let base = server.split(separator: ",").first.map(String.init) ?? server
        if let idx = base.lastIndex(of: ":") { return String(base[..<idx]) }
        return base
    }

    var port: Int {
        let base = server.split(separator: ",").first.map(String.init) ?? server
        if let idx = base.lastIndex(of: ":"), let p = Int(base[base.index(after: idx)...]) {
            return p
        }
        return 443
    }
}

// MARK: - Group / policy

enum GroupPolicy: String, Codable, CaseIterable, Identifiable {
    /// Pick whichever member currently has the lowest latency (URL test).
    case urlTest
    /// Stay on the chosen member; only switch on failure.
    case failover
    /// Never switch automatically.
    case manual
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .urlTest:  return "URL test (fastest)"
        case .failover: return "Failover"
        case .manual:   return "Manual"
        }
    }
}

/// A policy group bundling several connections with an automatic selection policy.
struct ConnectionGroup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Group"
    var memberIDs: [UUID] = []
    var policy: GroupPolicy = .urlTest
    /// URL fetched through each member to measure latency / health.
    var testURL: String = "http://cp.cloudflare.com/generate_204"
    /// When true the manager will auto-switch the active connection to keep the
    /// group healthy (fastest for urlTest, next-healthy for failover).
    var autoSwitch: Bool = true
}

// MARK: - Settings

struct AppSettings: Codable {
    /// Explicit path to the hysteria binary. When empty the app auto-detects.
    var hysteriaPath: String = ""

    var socksPort: Int = 1080
    var httpPort: Int = 8080

    /// Toggle the macOS system proxy when connecting/disconnecting.
    var setSystemProxy: Bool = true

    var startOnBoot: Bool = false
    var showInDock: Bool = false
    var autoConnectLast: Bool = false

    /// Optional custom geoip/geosite database paths. Empty = let hysteria
    /// auto-download and cache them.
    var geoipPath: String = ""
    var geositePath: String = ""

    /// Latency / health probe.
    var testURL: String = "http://cp.cloudflare.com/generate_204"
    var monitorIntervalSec: Int = 30

    /// Number of consecutive failed probes before failover kicks in.
    var failoverThreshold: Int = 2

    var lastConnectionID: UUID? = nil
}

// MARK: - Persisted document

/// The whole persisted state, written as a single JSON file.
struct StoreDocument: Codable {
    var connections: [Connection] = []
    var groups: [ConnectionGroup] = []
    var settings: AppSettings = AppSettings()
}
