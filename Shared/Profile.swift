import Foundation

// Platform-agnostic connection profile shared by the macOS and iOS apps.
// (Compiled into each app target directly — no module import needed.)

// MARK: - Routing

enum RoutingMode: String, Codable, CaseIterable, Identifiable {
    /// CN destinations direct, everything else through the proxy.
    case ruleBased
    /// Everything through the proxy.
    case global
    /// Bypass — nothing proxied.
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

/// A single hysteria2 (or compatible) outbound profile.
struct Connection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Connection"

    /// "host:port" (port optional → 443). May include port hopping, "host:443,5000-6000".
    var server: String = ""
    var auth: String = ""

    // TLS
    var sni: String = ""
    var insecure: Bool = false
    var pinSHA256: String = ""

    // Obfuscation (Salamander)
    var obfsType: ObfsType = .none
    var obfsPassword: String = ""

    // Bandwidth hints (Mbps). 0 = unset.
    var upMbps: Int = 0
    var downMbps: Int = 0

    // Routing (used by macOS per-connection; iOS uses a global policy).
    var routingMode: RoutingMode = .ruleBased
    /// Extra rule lines (macOS: hysteria ACL; ignored on iOS).
    var extraACL: [String] = []

    // hysteria-YAML specific (ignored by the sing-box/iOS engine).
    var fastOpen: Bool = true
    var lazy: Bool = true
    var notes: String = ""
    var rawConfigOverride: String? = nil

    /// Whether the profile participates in the iOS group / fastest selection.
    var enabled: Bool = true

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
    case urlTest
    case failover
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

struct ConnectionGroup: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Group"
    var memberIDs: [UUID] = []
    var policy: GroupPolicy = .urlTest
    var testURL: String = "http://cp.cloudflare.com/generate_204"
    var autoSwitch: Bool = true
}
