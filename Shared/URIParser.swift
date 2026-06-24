import Foundation

/// Parses hysteria2 share URIs into `Connection` values.
/// Format: `hysteria2://[auth@]host[:port]/?sni=..&insecure=1&obfs=salamander&obfs-password=..&pinSHA256=..#name`
/// (`hy2://` is an accepted alias.)
enum URIParser {

    static func parseMany(_ text: String) -> [Connection] {
        text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == " " || $0 == "\t" })
            .map(String.init)
            .compactMap { parse($0) }
    }

    static func parse(_ raw: String) -> Connection? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("hysteria2://") || trimmed.hasPrefix("hy2://") else { return nil }

        let normalized = trimmed.replacingOccurrences(of: "hy2://", with: "hysteria2://")
        guard let comps = URLComponents(string: normalized), let host = comps.host else { return nil }

        var c = Connection()

        if let user = comps.user {
            if let pass = comps.password {
                c.auth = decode(user) + ":" + decode(pass)
            } else {
                c.auth = decode(user)
            }
        }

        if let port = comps.port {
            c.server = "\(host):\(port)"
        } else if let range = portRange(in: normalized) {
            c.server = "\(host):\(range)"
        } else {
            c.server = "\(host):443"
        }

        var obfsPassword = ""
        for item in comps.queryItems ?? [] {
            let value = item.value ?? ""
            switch item.name.lowercased() {
            case "sni":           c.sni = value
            case "insecure":      c.insecure = (value == "1" || value.lowercased() == "true")
            case "pinsha256":     c.pinSHA256 = value
            case "obfs":          if value.lowercased() == "salamander" { c.obfsType = .salamander }
            case "obfs-password": obfsPassword = value
            default:              break
            }
        }
        if c.obfsType == .salamander { c.obfsPassword = obfsPassword }

        if let frag = comps.fragment, !frag.isEmpty {
            c.name = decode(frag)
        } else {
            c.name = host
        }
        return c
    }

    private static func decode(_ s: String) -> String { s.removingPercentEncoding ?? s }

    private static func portRange(in uri: String) -> String? {
        guard let schemeRange = uri.range(of: "://") else { return nil }
        var authority = String(uri[schemeRange.upperBound...])
        for sep in ["/", "?", "#"] {
            if let r = authority.range(of: sep) { authority = String(authority[..<r.lowerBound]) }
        }
        if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
        guard let colon = authority.lastIndex(of: ":") else { return nil }
        let portPart = String(authority[authority.index(after: colon)...])
        return portPart.contains("-") || portPart.contains(",") ? portPart : nil
    }
}
