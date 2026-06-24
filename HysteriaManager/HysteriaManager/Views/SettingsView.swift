import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var manager: ProxyManager

    @State private var detectedPath: String?
    @State private var version: String?
    @State private var showBinaryImporter = false
    @State private var passwordless = false
    @State private var proxyError: String?
    @State private var working = false

    private var s: Binding<AppSettings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            proxyTab.tabItem { Label("Proxy", systemImage: "network") }
            routingTab.tabItem { Label("Routing", systemImage: "arrow.triangle.branch") }
        }
        .padding()
        .onAppear(perform: detect)
        .task { await refreshPasswordless() }
    }

    private func refreshPasswordless() async {
        passwordless = await Task.detached { ProxyController.isPasswordlessEnabled }.value
    }

    private func setPasswordless(_ enable: Bool) {
        working = true
        proxyError = nil
        Task {
            let result = await Task.detached {
                enable ? ProxyController.installPasswordlessRule() : ProxyController.removePasswordlessRule()
            }.value
            if case .failure(let e) = result { proxyError = e.localizedDescription }
            await refreshPasswordless()
            working = false
        }
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Section("hysteria binary") {
                HStack {
                    TextField("Path", text: s.hysteriaPath, prompt: Text(detectedPath ?? "auto-detect"))
                    Button("Browse…") { showBinaryImporter = true }
                }
                if let v = version {
                    Label(v, systemImage: "checkmark.seal").font(.caption).foregroundStyle(.green)
                } else if detectedPath == nil && store.settings.hysteriaPath.isEmpty {
                    Label("Not found — run `brew install hysteria`", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("Re-detect") { detect() }.controlSize(.small)
            }

            Section("Startup") {
                Toggle("Start on login", isOn: s.startOnBoot)
                    .onChange(of: store.settings.startOnBoot) { _, _ in manager.applyLoginItem() }
                Toggle("Auto-connect last connection on launch", isOn: s.autoConnectLast)
                Toggle("Show icon in Dock", isOn: s.showInDock)
                    .onChange(of: store.settings.showInDock) { _, _ in manager.applyDockPolicy() }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showBinaryImporter,
            allowedContentTypes: [.unixExecutable, .executable, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.settings.hysteriaPath = url.path
                detect()
            }
        }
    }

    // MARK: Proxy

    private var proxyTab: some View {
        Form {
            Section("Local listeners") {
                HStack {
                    Text("SOCKS5 port")
                    TextField("", value: s.socksPort, format: .number).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("HTTP port")
                    TextField("", value: s.httpPort, format: .number).multilineTextAlignment(.trailing)
                }
            }
            Section("System proxy") {
                Toggle("Set macOS system proxy when connecting", isOn: s.setSystemProxy)
                if passwordless {
                    Label("Passwordless switching is on — no more prompts.", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                    Button("Turn off passwordless switching") { setPasswordless(false) }
                        .controlSize(.small).disabled(working)
                } else {
                    Text("By default macOS asks for your password each time the proxy changes. Authorize once to stop the prompts.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        setPasswordless(true)
                    } label: {
                        Label("Enable passwordless switching (asks once)", systemImage: "key")
                    }
                    .disabled(working)
                }
                if working { ProgressView().controlSize(.small) }
                if let proxyError {
                    Text(proxyError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Monitoring") {
                HStack {
                    Text("Probe interval (sec)")
                    TextField("", value: s.monitorIntervalSec, format: .number).multilineTextAlignment(.trailing)
                }
                TextField("Test URL", text: s.testURL)
                HStack {
                    Text("Failover after N failed probes")
                    TextField("", value: s.failoverThreshold, format: .number).multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Routing

    private var routingTab: some View {
        Form {
            Section("GeoIP / GeoSite databases") {
                Text("Leave empty to let hysteria download and cache geoip.dat / geosite.dat automatically on first use.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("geoip.dat path", text: s.geoipPath, prompt: Text("auto-download"))
                TextField("geosite.dat path", text: s.geositePath, prompt: Text("auto-download"))
            }
            Section {
                Text("Per-connection routing mode (rule-based CN-direct vs. global) is set on each connection. Rule-based uses hysteria's ACL to keep geoip:cn / geosite:cn and private ranges direct, tunneling the rest.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Detect

    private func detect() {
        let path = BinaryLocator.locate(custom: store.settings.hysteriaPath)
        detectedPath = path
        version = path.flatMap { BinaryLocator.version(at: $0) }
    }
}
