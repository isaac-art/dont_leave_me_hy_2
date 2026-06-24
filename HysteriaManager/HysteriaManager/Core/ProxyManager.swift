import Foundation
import AppKit
import Combine

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isActive: Bool { self == .connecting || self == .connected }
}

/// The runtime engine: owns the hysteria subprocess, drives the system proxy,
/// runs health/latency/traffic monitoring, and exposes everything the UI binds to.
@MainActor
final class ProxyManager: ObservableObject {
    let store: ConnectionStore

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var activeConnectionID: UUID?
    /// Latest measured latency per connection (ms). nil = unknown, missing key = never tested.
    @Published private(set) var latencies: [UUID: Int?] = [:]
    @Published private(set) var traffic: TrafficMonitor.Sample = .init(upBytesPerSec: 0, downBytesPerSec: 0)
    @Published private(set) var sessionUpBytes: UInt64 = 0
    @Published private(set) var sessionDownBytes: UInt64 = 0
    @Published private(set) var logLines: [String] = []
    @Published var lastError: String?
    /// True while a group "Test all" sweep is running.
    @Published private(set) var isTestingGroup = false

    private let hysteria = HysteriaProcess()
    private var monitorTimer: Timer?
    private var proxyWasSet = false
    private var consecutiveFailures = 0
    private var launchObserver: NSObjectProtocol?

    var activeConnection: Connection? { store.connection(activeConnectionID) }

    init(store: ConnectionStore) {
        self.store = store
        hysteria.onTermination = { [weak self] status in
            guard let self else { return }
            if self.state.isActive {
                self.appendLog("[hysteria] exited unexpectedly (status \(status))\n")
                self.state = .error("hysteria exited (status \(status))")
                self.teardownProxyAndMonitoring()
            }
        }
        applyDockPolicy()

        // Run launch-time setup once the app has actually finished launching, so
        // "start on boot" + "auto-connect last" work even when nobody opens the menu.
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onLaunch() }
        }
    }

    private func onLaunch() {
        applyDockPolicy()
        applyLoginItem()
        autoConnectIfNeeded()
    }

    // MARK: - Connect / disconnect

    func toggle(_ connection: Connection) {
        if activeConnectionID == connection.id && state.isActive {
            disconnect()
        } else {
            connect(connection)
        }
    }

    func connect(_ connection: Connection) {
        lastError = nil
        consecutiveFailures = 0

        guard let binary = BinaryLocator.locate(custom: store.settings.hysteriaPath) else {
            let msg = "hysteria binary not found. Install it (brew install hysteria) or set a path in Settings."
            appendLog("[error] \(msg)\n")
            state = .error(msg); lastError = msg
            return
        }
        appendLog("[connect] \(connection.name) — \(connection.server) — binary: \(binary)\n")

        // If switching from another active connection, tear the old one down first.
        if state.isActive { hysteria.stop() }

        state = .connecting
        activeConnectionID = connection.id
        sessionUpBytes = 0
        sessionDownBytes = 0
        traffic = .init(upBytesPerSec: 0, downBytesPerSec: 0)

        let yaml = ConfigBuilder.makeConfig(for: connection, settings: store.settings)
        let configURL = configPath(for: connection)
        do {
            try yaml.data(using: .utf8)?.write(to: configURL, options: .atomic)
        } catch {
            failConnect("Could not write config: \(error.localizedDescription)")
            return
        }

        // Kill any leftover hysteria from a crashed/force-quit previous run that may
        // still be holding our SOCKS/HTTP ports (matched by our private config dir).
        reapOrphans()

        do {
            try hysteria.start(binaryPath: binary, configPath: configURL.path) { [weak self] line in
                self?.appendLog(line)
            }
        } catch {
            failConnect("Could not launch hysteria: \(error.localizedDescription)")
            return
        }

        store.settings.lastConnectionID = connection.id

        // Flip the system proxy (off main — may prompt for admin auth).
        let setProxy = store.settings.setSystemProxy
        let socks = store.settings.socksPort
        let http = store.settings.httpPort
        Task {
            if setProxy {
                let result = await Task.detached { ProxyController.enable(socksPort: socks, httpPort: http) }.value
                switch result {
                case .success:
                    self.proxyWasSet = true
                case .failure(let err):
                    self.appendLog("[proxy] \(err.localizedDescription)\n")
                    self.lastError = err.localizedDescription
                }
            }
            // Settle, then mark connected and start monitoring.
            try? await Task.sleep(nanoseconds: 600_000_000)
            if self.activeConnectionID == connection.id, self.hysteria.isRunning {
                self.state = .connected
                self.startMonitoring()
            }
        }
    }

    func disconnect() {
        teardownProxyAndMonitoring()
        hysteria.stop()
        state = .disconnected
        activeConnectionID = nil
        traffic = .init(upBytesPerSec: 0, downBytesPerSec: 0)
    }

    private func failConnect(_ message: String) {
        appendLog("[error] \(message)\n")
        hysteria.stop()
        state = .error(message)
        lastError = message
        activeConnectionID = nil
    }

    private func teardownProxyAndMonitoring() {
        stopMonitoring()
        if proxyWasSet {
            proxyWasSet = false
            Task.detached { _ = ProxyController.disable() }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        stopMonitoring()
        let interval = TimeInterval(max(5, store.settings.monitorIntervalSec))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
        Task { @MainActor in self.tick() }   // fire immediately
    }

    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func tick() {
        guard state == .connected, let id = activeConnectionID else { return }

        // Latency probe through the proxy.
        let http = store.settings.httpPort
        let url = store.settings.testURL
        Task {
            let ms = await LatencyTester.measure(httpProxyPort: http, urlString: url)
            self.latencies.updateValue(ms, forKey: id)   // store explicit nil = "timeout"
            if ms == nil { self.handleProbeFailure() } else { self.consecutiveFailures = 0 }
        }

        // Traffic sample.
        if let pid = hysteria.pid {
            let interval = UInt64(max(5, store.settings.monitorIntervalSec))
            Task.detached {
                let sample = TrafficMonitor.sample(pid: pid)
                if let sample {
                    await MainActor.run {
                        self.traffic = sample
                        self.sessionUpBytes += sample.upBytesPerSec * interval
                        self.sessionDownBytes += sample.downBytesPerSec * interval
                    }
                }
            }
        }
    }

    private func handleProbeFailure() {
        consecutiveFailures += 1
        guard consecutiveFailures >= max(1, store.settings.failoverThreshold) else { return }
        guard let id = activeConnectionID,
              let group = store.groups.first(where: { $0.autoSwitch && $0.memberIDs.contains(id) }),
              group.policy != .manual else { return }
        // Failover to the next member.
        let members = group.memberIDs
        guard let idx = members.firstIndex(of: id), members.count > 1 else { return }
        let next = members[(idx + 1) % members.count]
        if let nextConn = store.connection(next) {
            appendLog("[failover] \(group.name): switching to \(nextConn.name)\n")
            consecutiveFailures = 0
            connect(nextConn)
        }
    }

    // MARK: - Group testing (URL test)

    /// Sequentially connects each member, measures latency, then (for urlTest groups)
    /// reconnects to the fastest. Heavy but accurate; triggered manually.
    func testGroup(_ group: ConnectionGroup) {
        guard !isTestingGroup else { return }
        let members = store.members(of: group)
        guard !members.isEmpty else { return }
        isTestingGroup = true
        let resume = activeConnection

        Task {
            var best: (Connection, Int)?
            for member in members {
                connect(member)
                // Wait for it to come up.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let ms = await LatencyTester.measure(
                    httpProxyPort: store.settings.httpPort,
                    urlString: group.testURL
                )
                latencies.updateValue(ms, forKey: member.id)
                appendLog("[test] \(member.name): \(ms.map { "\($0) ms" } ?? "unreachable")\n")
                if let ms, best == nil || ms < best!.1 { best = (member, ms) }
            }

            isTestingGroup = false
            switch group.policy {
            case .urlTest:
                if let best { connect(best.0) }
                else if let resume { connect(resume) }
            case .failover, .manual:
                if let resume { connect(resume) } else { disconnect() }
            }
        }
    }

    /// Measure latency of just the active connection on demand.
    func probeActiveNow() {
        guard state == .connected, let id = activeConnectionID else { return }
        Task {
            let ms = await LatencyTester.measure(
                httpProxyPort: store.settings.httpPort,
                urlString: store.settings.testURL
            )
            latencies.updateValue(ms, forKey: id)
        }
    }

    // MARK: - System integration

    func applyDockPolicy() {
        NSApp.setActivationPolicy(store.settings.showInDock ? .regular : .accessory)
    }

    func applyLoginItem() {
        _ = LoginItemManager.setEnabled(store.settings.startOnBoot)
    }

    func autoConnectIfNeeded() {
        guard store.settings.autoConnectLast,
              let last = store.connection(store.settings.lastConnectionID) else { return }
        connect(last)
    }

    // MARK: - Helpers

    /// Terminates leftover hysteria processes spawned by this app (identified by our
    /// private config directory in their arguments). Safe — won't touch unrelated
    /// processes or a hysteria you run yourself elsewhere.
    private func reapOrphans() {
        let configsDir = store.supportDirectory.appendingPathComponent("configs").path
        let result = Shell.run("/usr/bin/pkill", ["-f", configsDir])
        if result.status == 0 {
            appendLog("[cleanup] terminated a leftover hysteria process holding the ports\n")
            // Give the OS a moment to release the sockets.
            usleep(250_000)
        }
    }

    private func configPath(for connection: Connection) -> URL {
        let dir = store.supportDirectory.appendingPathComponent("configs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(connection.id.uuidString).yaml")
    }

    /// Persistent log file: `~/Library/Application Support/HysteriaManager/hysteria.log`.
    var logFileURL: URL { store.supportDirectory.appendingPathComponent("hysteria.log") }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private func appendLog(_ text: String) {
        let ts = Self.timeFormatter.string(from: Date())
        var fileChunk = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = "\(ts)  \(raw)"
            logLines.append(line)
            fileChunk += line + "\n"
        }
        if logLines.count > 1000 { logLines.removeFirst(logLines.count - 1000) }
        if let data = fileChunk.data(using: .utf8) { appendToLogFile(data) }
    }

    private func appendToLogFile(_ data: Data) {
        let url = logFileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)   // file didn't exist yet
        }
    }

    func clearLog() {
        logLines.removeAll()
        try? Data().write(to: logFileURL)
    }

    /// Reveal the log file in Finder.
    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    /// Open the log file in the default text editor.
    func openLogFile() {
        NSWorkspace.shared.open(logFileURL)
    }
}
