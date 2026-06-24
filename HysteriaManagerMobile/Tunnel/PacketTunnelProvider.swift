import Foundation
import Libbox
import NetworkExtension

/// The packet-tunnel extension. Sets up Libbox, starts the sing-box command server,
/// and loads the config the container app wrote to the App Group. Adapted (iOS-only)
/// from SagerNet/sing-box-for-apple's `ExtensionProvider.swift`.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private lazy var platformInterface = PlatformInterface(self)

    struct OverridePreferences {
        var includeAllNetworks = false
        var systemProxyEnabled = false
    }
    var overridePreferences: OverridePreferences? = OverridePreferences()

    override func startTunnel(options _: [String: NSObject]?) async throws {
        AppGroup.ensureDirectories()

        let setup = LibboxSetupOptions()
        setup.basePath = AppGroup.basePath
        setup.workingPath = AppGroup.workingURL.path
        setup.tempPath = AppGroup.cacheURL.path
        setup.logMaxLines = 3000

        var setupError: NSError?
        LibboxSetup(setup, &setupError)
        if let setupError {
            throw ExtensionStartupError("setup service: \(setupError.localizedDescription)")
        }

        let stderrPath = AppGroup.cacheURL.appendingPathComponent("stderr.log").path
        var stderrError: NSError?
        LibboxRedirectStderr(stderrPath, &stderrError)

        LibboxSetMemoryLimit(true)

        var error: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &error)
        if let error {
            throw ExtensionStartupError("create command server: \(error.localizedDescription)")
        }
        try commandServer!.start()

        writeMessage("(packet-tunnel) starting")
        try await startService()
    }

    private func startService() async throws {
        guard let data = try? Data(contentsOf: AppGroup.configURL),
              let content = String(data: data, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtensionStartupError("missing config at \(AppGroup.configURL.path)")
        }
        let options = LibboxOverrideOptions()
        do {
            try commandServer!.startOrReloadService(content, options: options)
        } catch {
            throw ExtensionStartupError("start service: \(error.localizedDescription)")
        }
    }

    func writeMessage(_ message: String) {
        commandServer?.writeMessage(2, message: message)
    }

    func stopService() {
        do { try commandServer?.closeService() }
        catch { writeMessage("stop service: \(error.localizedDescription)") }
        platformInterface.reset()
    }

    func reloadService() async throws {
        writeMessage("(packet-tunnel) reloading")
        reasserting = true
        defer { reasserting = false }
        try await startService()
    }

    override func stopTunnel(with _: NEProviderStopReason) async {
        stopService()
        if let server = commandServer {
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
            server.close()
            commandServer = nil
        }
    }

    override func handleAppMessage(_: Data) async -> Data? {
        // Any message means "reload from the App Group config file".
        do { try await reloadService(); return nil }
        catch { return error.localizedDescription.data(using: .utf8) }
    }

    override func sleep() async { commandServer?.pause() }
    override func wake() { commandServer?.wake() }
}
