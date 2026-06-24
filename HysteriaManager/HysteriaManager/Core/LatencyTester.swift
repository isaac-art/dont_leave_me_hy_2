import Foundation

/// Measures round-trip latency by fetching a small URL *through* a local proxy.
enum LatencyTester {

    /// Returns latency in milliseconds, or nil on failure/timeout.
    /// Routes the request through the local HTTP proxy so the measurement reflects
    /// the actual tunnel (a non-CN test URL goes through the proxy under rule mode).
    static func measure(httpProxyPort: Int, urlString: String, timeout: TimeInterval = 5) async -> Int? {
        guard let url = URL(string: urlString) else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = timeout
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 1,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: httpProxyPort,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": httpProxyPort,
        ]
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let start = DispatchTime.now()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
                return nil
            }
            return Int(elapsed / 1_000_000)
        } catch {
            return nil
        }
    }

    /// Directly probe TCP reachability of the local proxy port (is hysteria up?).
    static func proxyPortReachable(_ port: Int) -> Bool {
        let result = Shell.run("/usr/bin/nc", ["-z", "-G", "1", "127.0.0.1", "\(port)"])
        return result.status == 0
    }
}
