import Foundation

/// Builds a sing-box JSON config from the user's hysteria2 profiles.
///
/// Targets sing-box 1.13.x. The routing brain:
///   • a `tun` inbound captures all device traffic (auto_route),
///   • each profile becomes a `hysteria2` outbound,
///   • ONE server → route straight to it; MANY → a `urltest` picks the fastest,
///   • `route` sends geoip:cn + geosite:cn + private IPs to `direct`, the rest to
///     the proxy  →  "China direct, everything else through hysteria".
enum SingboxConfigBuilder {

    static let geoipCNURL   = "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
    static let geositeCNURL = "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"

    static func build(connections: [Connection], settings: MobileSettings) -> Data {
        let enabled = connections.filter { $0.enabled && !$0.server.isEmpty }
        let proxyTags = enabled.map { tag(for: $0) }
        let hasProxies = !proxyTags.isEmpty

        var outbounds: [[String: Any]] = enabled.map { hysteria2Outbound($0) }

        // What "the proxy" resolves to.
        let proxyTag: String
        if proxyTags.count > 1 {
            outbounds.append([
                "type": "urltest",
                "tag": "auto",
                "outbounds": proxyTags,
                "url": settings.testURL,
                "interval": "\(max(60, settings.testIntervalSec))s",
                "tolerance": 50,
            ])
            let defaultTag: String
            if settings.selectionMode == .manual,
               let id = settings.selectedConnectionID,
               let picked = enabled.first(where: { $0.id == id }) {
                defaultTag = tag(for: picked)
            } else {
                defaultTag = "auto"
            }
            outbounds.append([
                "type": "selector",
                "tag": "proxy",
                "outbounds": ["auto"] + proxyTags,
                "default": defaultTag,
            ])
            proxyTag = "proxy"
        } else if let only = proxyTags.first {
            proxyTag = only          // single server → no selector/urltest indirection
        } else {
            proxyTag = "direct"
        }
        outbounds.append(["type": "direct", "tag": "direct"])

        let finalOutbound = (settings.routingMode == .direct || !hasProxies) ? "direct" : proxyTag

        let tsEnabled = settings.tailscaleEnabled &&
            !settings.tailscaleAuthKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        var root: [String: Any] = [
            // Write sing-box's own logs to a file the app can read (its structured logs
            // do NOT go to stderr, so without this the log viewer looks empty).
            "log": ["level": "info", "timestamp": true,
                    "output": AppGroup.cacheURL.appendingPathComponent("box.log").path],
            "dns": dnsConfig(mode: settings.routingMode, proxyTag: proxyTag, hasProxies: hasProxies),
            "inbounds": [tunInbound()],
            "outbounds": outbounds,
            "route": routeConfig(mode: settings.routingMode, hasProxies: hasProxies,
                                 proxyTag: proxyTag, finalOutbound: finalOutbound, tailscale: tsEnabled),
        ]
        root["experimental"] = ["cache_file": ["enabled": true]]

        if tsEnabled {
            // Tailscale endpoint — joins the tailnet in this same tunnel. Requires
            // Libbox built with the `with_tailscale` tag (it is, by default).
            root["endpoints"] = [[
                "type": "tailscale",
                "tag": "ts",
                "auth_key": settings.tailscaleAuthKey.trimmingCharacters(in: .whitespacesAndNewlines),
                "accept_routes": settings.tailscaleAcceptRoutes,
            ]]
        }

        let opts: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: root, options: opts)) ?? Data("{}".utf8)
    }

    // MARK: - Outbounds

    static func tag(for c: Connection) -> String {
        "px-" + c.id.uuidString.prefix(8).lowercased()
    }

    private static func hysteria2Outbound(_ c: Connection) -> [String: Any] {
        var o: [String: Any] = [
            "type": "hysteria2",
            "tag": tag(for: c),
            "server": c.host,
            "password": c.auth,
        ]
        applyPort(&o, server: c.server, fallback: c.port)

        o["tls"] = [
            "enabled": true,
            "insecure": c.insecure,
            "server_name": c.sni.isEmpty ? c.host : c.sni,
        ]
        if c.obfsType == .salamander, !c.obfsPassword.isEmpty {
            o["obfs"] = ["type": "salamander", "password": c.obfsPassword]
        }
        if c.upMbps > 0 { o["up_mbps"] = c.upMbps }
        if c.downMbps > 0 { o["down_mbps"] = c.downMbps }
        return o
    }

    private static func applyPort(_ o: inout [String: Any], server: String, fallback: Int) {
        guard let first = server.split(separator: ",").first.map(String.init),
              let colon = first.lastIndex(of: ":") else {
            o["server_port"] = fallback
            return
        }
        let portPart = String(first[first.index(after: colon)...])
        if portPart.contains("-") {
            o["server_ports"] = [portPart.replacingOccurrences(of: "-", with: ":")]
            o["hop_interval"] = "30s"
        } else if let p = Int(portPart) {
            o["server_port"] = p
        } else {
            o["server_port"] = fallback
        }
    }

    // MARK: - Inbound

    private static func tunInbound() -> [String: Any] {
        [
            "type": "tun",
            "tag": "tun-in",
            "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
            "auto_route": true,
            "strict_route": false,   // strict_route can break routing inside an iOS NE
            "stack": "system",
            "mtu": 9000,
        ]
    }

    // MARK: - Route

    private static func ruleSets(proxyTag: String) -> [[String: Any]] {
        [
            ["type": "remote", "tag": "geoip-cn", "format": "binary",
             "url": geoipCNURL, "download_detour": proxyTag],
            ["type": "remote", "tag": "geosite-cn", "format": "binary",
             "url": geositeCNURL, "download_detour": proxyTag],
        ]
    }

    private static func routeConfig(mode: RoutingMode, hasProxies: Bool,
                                    proxyTag: String, finalOutbound: String,
                                    tailscale: Bool) -> [String: Any] {
        var rules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
        ]
        if tailscale {
            // Tailnet (CGNAT range) → Tailscale. Must precede ip_is_private, which
            // would otherwise catch 100.64.0.0/10 and send it direct.
            rules.append(["ip_cidr": ["100.64.0.0/10"], "outbound": "ts"])
        }
        rules.append(["ip_is_private": true, "outbound": "direct"])
        if mode == .ruleBased, hasProxies {
            rules.append(["rule_set": ["geoip-cn", "geosite-cn"], "outbound": "direct"])
        }
        var route: [String: Any] = [
            "rules": rules,
            "final": finalOutbound,
            "auto_detect_interface": true,
            // Resolve outbound server domains (the proxy's hostname) via DIRECT DNS, not
            // through the proxy — otherwise connecting deadlocks (resolve needs proxy,
            // proxy needs resolve) and the tunnel times out.
            "default_domain_resolver": ["server": "local"],
        ]
        if mode == .ruleBased, hasProxies {
            route["rule_set"] = ruleSets(proxyTag: proxyTag)
        }
        return route
    }

    // MARK: - DNS

    // Legacy DNS format — proven to connect on-device. (The new 1.12 format broke
    // runtime connect even though `sing-box check` accepted it, so we avoid it.)
    private static func dnsConfig(mode: RoutingMode, proxyTag: String, hasProxies: Bool) -> [String: Any] {
        var servers: [[String: Any]] = [
            ["tag": "local", "address": "https://223.5.5.5/dns-query", "detour": "direct"],
        ]
        if hasProxies, mode != .direct {
            servers.insert(["tag": "remote", "address": "https://1.1.1.1/dns-query", "detour": proxyTag], at: 0)
        }
        var rules: [[String: Any]] = []
        if mode == .ruleBased, hasProxies {
            rules.append(["rule_set": ["geosite-cn"], "server": "local"])
        }
        let finalServer = (hasProxies && mode != .direct) ? "remote" : "local"
        return ["servers": servers, "rules": rules, "final": finalServer, "strategy": "prefer_ipv4"]
    }
}
