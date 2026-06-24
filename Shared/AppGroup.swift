import Foundation

/// Shared App Group locations, used by BOTH the container app and the packet-tunnel
/// extension. The App Group ID must match the entitlement in both targets.
enum AppGroup {
    /// Must match `com.apple.security.application-groups` in both targets' entitlements.
    static let id = "group.com.isaacclarke.HysteriaManager"

    /// Bundle ID of the packet-tunnel extension (used to find the VPN manager).
    static let tunnelBundleID = "com.isaacclarke.HysteriaManagerMobile.tunnel"

    static var container: URL {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: id) else {
            // Misconfigured App Group — fall back to a temp dir so we don't crash.
            return FileManager.default.temporaryDirectory
        }
        return url
    }

    /// The generated sing-box config the extension loads on start/reload.
    static var configURL: URL { container.appendingPathComponent("config.json") }

    /// Libbox base / working / temp paths (all inside the shared container).
    static var basePath: String { container.path }
    static var workingURL: URL { container.appendingPathComponent("work", isDirectory: true) }
    static var cacheURL: URL { container.appendingPathComponent("temp", isDirectory: true) }

    static func ensureDirectories() {
        for url in [workingURL, cacheURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
