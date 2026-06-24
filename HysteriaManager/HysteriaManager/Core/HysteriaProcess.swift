import Foundation

/// Wraps a running `hysteria client -c <config>` subprocess.
final class HysteriaProcess {
    private(set) var process: Process?
    private var logHandler: ((String) -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }
    var pid: Int32? { isRunning ? process?.processIdentifier : nil }

    /// Called when the process exits on its own (crash / kill). Runs on main.
    var onTermination: ((Int32) -> Void)?

    /// Launches hysteria with the given config file. Streams stdout+stderr to `log`.
    /// Throws if the binary can't be launched.
    func start(binaryPath: String, configPath: String, log: @escaping (String) -> Void) throws {
        stop()
        self.logHandler = log

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["client", "--config", configPath]

        // Give hysteria a sane PATH so geoip/geosite auto-download (which may shell
        // out) and DNS work as expected.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { log(text) }
        }

        proc.terminationHandler = { [weak self] p in
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = nil
            // Drain any final output (an instant crash often prints the reason here).
            let remaining = handle.availableData
            DispatchQueue.main.async {
                if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
                    log(text)
                }
                self?.onTermination?(p.terminationStatus)
            }
        }

        try proc.run()
        self.process = proc
        log("[hysteria] started (pid \(proc.processIdentifier))\n")
    }

    func stop() {
        guard let proc = process, proc.isRunning else { process = nil; return }
        proc.terminationHandler = nil
        proc.terminate()                       // SIGTERM
        // Give it a moment, then force kill if still alive.
        let deadline = Date().addingTimeInterval(2)
        while proc.isRunning && Date() < deadline { usleep(50_000) }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        process = nil
    }
}
