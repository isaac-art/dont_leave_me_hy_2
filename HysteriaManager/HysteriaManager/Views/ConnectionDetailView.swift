import SwiftUI
import AppKit

struct ConnectionDetailView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var manager: ProxyManager
    @Environment(\.openWindow) private var openWindow
    let connectionID: UUID

    @State private var showLog = false
    @State private var showRawConfig = false

    private var conn: Connection { store.connection(connectionID) ?? Connection() }
    private var isActive: Bool { manager.activeConnectionID == connectionID && manager.state.isActive }

    private var bound: Binding<Connection> {
        Binding(
            get: { store.connection(connectionID) ?? Connection() },
            set: { store.upsert($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            Form {
                generalSection
                tlsSection
                obfsSection
                bandwidthSection
                routingSection
                advancedSection
                if isActive { monitorSection }
            }
            .formStyle(.grouped)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    if isActive { manager.disconnect() }
                    store.deleteConnection(connectionID)
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .sheet(isPresented: $showRawConfig) {
            RawConfigSheet(yaml: ConfigBuilder.makeConfig(for: conn, settings: store.settings))
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            StatusDot(state: isActive ? manager.state : .disconnected)
            VStack(alignment: .leading, spacing: 2) {
                Text(conn.name).font(.title3.weight(.semibold))
                Text(conn.server).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            LatencyBadge(ms: manager.latencies[connectionID])
            if isActive {
                Button("Disconnect") { manager.disconnect() }
            } else {
                Button("Connect") { manager.connect(conn) }
                    .keyboardShortcut(.defaultAction)
            }
            Button("Test") { connectAndProbe() }
                .disabled(manager.isTestingGroup)
            Button {
                showRawConfig = true
            } label: { Image(systemName: "doc.text") }
                .help("Preview generated YAML")
            Button {
                openWindow(id: "log")
            } label: { Image(systemName: "doc.text.magnifyingglass") }
                .help("Show log")
        }
        .padding(12)
    }

    // MARK: Form sections

    private var generalSection: some View {
        Section("General") {
            TextField("Name", text: bound.name)
            TextField("Server (host:port)", text: bound.server, prompt: Text("example.com:443"))
            SecureField("Auth password", text: bound.auth)
        }
    }

    private var tlsSection: some View {
        Section("TLS") {
            TextField("SNI", text: bound.sni, prompt: Text("defaults to server host"))
            Toggle("Allow insecure (skip cert verification)", isOn: bound.insecure)
            TextField("Pin SHA-256", text: bound.pinSHA256, prompt: Text("optional"))
        }
    }

    private var obfsSection: some View {
        Section("Obfuscation") {
            Picker("Type", selection: bound.obfsType) {
                ForEach(ObfsType.allCases) { Text($0.displayName).tag($0) }
            }
            if conn.obfsType == .salamander {
                SecureField("Obfs password", text: bound.obfsPassword)
            }
        }
    }

    private var bandwidthSection: some View {
        Section("Bandwidth (optional)") {
            HStack {
                Text("Up")
                TextField("Mbps", value: bound.upMbps, format: .number)
                    .multilineTextAlignment(.trailing)
                Text("Mbps").foregroundStyle(.secondary)
            }
            HStack {
                Text("Down")
                TextField("Mbps", value: bound.downMbps, format: .number)
                    .multilineTextAlignment(.trailing)
                Text("Mbps").foregroundStyle(.secondary)
            }
            Text("Leave at 0 to let hysteria's BBR auto-detect.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var routingSection: some View {
        Section("Routing") {
            Picker("Mode", selection: bound.routingMode) {
                ForEach(RoutingMode.allCases) { Text($0.displayName).tag($0) }
            }
            if conn.routingMode == .ruleBased {
                Text("China (geoip:cn / geosite:cn) and private ranges stay direct; everything else is tunneled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Extra ACL rules (one per line)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: extraACLBinding)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("e.g.  reject(geosite:category-ads-all)   ·   proxy(domain:example.com)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Fast Open", isOn: bound.fastOpen)
            Toggle("Lazy (connect on first use)", isOn: bound.lazy)
            DisclosureGroup("Notes", isExpanded: .constant(true)) {
                TextEditor(text: bound.notes).frame(height: 50)
            }
        }
    }

    private var monitorSection: some View {
        Section("Live") {
            TrafficLabel(up: manager.traffic.upBytesPerSec, down: manager.traffic.downBytesPerSec)
            Text("Session  ↑ \(TrafficMonitor.formatBytes(manager.sessionUpBytes))   ↓ \(TrafficMonitor.formatBytes(manager.sessionDownBytes))")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Log", isExpanded: $showLog) {
                ScrollView {
                    Text(manager.logLines.joined(separator: "\n"))
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 140)
                HStack {
                    Spacer()
                    Button("Clear") { manager.clearLog() }.controlSize(.small)
                }
            }
        }
    }

    // MARK: Bindings / actions

    private var extraACLBinding: Binding<String> {
        Binding(
            get: { conn.extraACL.joined(separator: "\n") },
            set: { newValue in
                var c = conn
                c.extraACL = newValue.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                store.upsert(c)
            }
        )
    }

    private func connectAndProbe() {
        if isActive {
            manager.probeActiveNow()
        } else {
            manager.connect(conn)
        }
    }
}

/// Read-only preview of the generated YAML.
struct RawConfigSheet: View {
    let yaml: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading) {
            Text("Generated hysteria config").font(.headline)
            ScrollView {
                Text(yaml)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(width: 520, height: 360)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(yaml, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
