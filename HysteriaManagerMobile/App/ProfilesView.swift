import SwiftUI
import NetworkExtension

struct ProfilesView: View {
    @EnvironmentObject var store: MobileStore
    @EnvironmentObject var vpn: VPNManager

    @State private var showImport = false
    @State private var showScanner = false
    @State private var showSettings = false
    @State private var showLog = false
    @State private var editing: Connection?

    var body: some View {
        NavigationStack {
            List {
                Section { statusCard }

                Section("Selection") {
                    Picker("Mode", selection: selectionBinding) {
                        ForEach(SelectionMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Routing", selection: routingBinding) {
                        ForEach(RoutingMode.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section("Connections") {
                    if store.connections.isEmpty {
                        ContentUnavailableView {
                            Label("No connections", systemImage: "bolt.horizontal.circle")
                        } description: {
                            Text("Add one with a hysteria2 link or QR code.")
                        } actions: {
                            Button("Paste Link") { showImport = true }
                            Button("Scan QR") { showScanner = true }
                        }
                    }
                    ForEach(store.connections) { conn in
                        row(conn)
                    }
                    .onDelete { idx in
                        idx.map { store.connections[$0].id }.forEach(store.delete)
                        Task { await vpn.reload(store: store) }
                    }
                }
            }
            .navigationTitle("Hysteria")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    Button { showLog = true } label: { Image(systemName: "doc.text.magnifyingglass") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = Connection() } label: { Label("Add Manually", systemImage: "square.and.pencil") }
                        Button { showImport = true } label: { Label("Paste Link", systemImage: "doc.on.clipboard") }
                        Button { showScanner = true } label: { Label("Scan QR Code", systemImage: "qrcode.viewfinder") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportView { imported in
                    store.add(imported)
                    Task { await vpn.reload(store: store) }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scanned in
                    let imported = URIParser.parseMany(scanned)
                    store.add(imported)
                    Task { await vpn.reload(store: store) }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $showLog) { TunnelLogView() }
            .sheet(item: $editing) { conn in
                NavigationStack {
                    ProfileEditView(connectionID: conn.id, isNew: store.connection(conn.id) == nil, draft: conn)
                }
            }
            .alert("VPN Error", isPresented: errorBinding) {
                Button("OK") { vpn.lastError = nil }
            } message: { Text(vpn.lastError ?? "") }
        }
    }

    // MARK: Status card

    private var statusCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                StatusBadge(status: vpn.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vpn.statusText).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button {
                Task { await vpn.toggle(store: store) }
            } label: {
                HStack {
                    if vpn.isBusy { ProgressView().tint(.white) }
                    Text(vpn.isActive ? "Disconnect" : "Connect").bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(vpn.isActive ? .red : .accentColor)
            .disabled(vpn.isBusy)

            HStack {
                Button {
                    Task { await vpn.ping(urlString: store.settings.testURL) }
                } label: {
                    HStack(spacing: 6) {
                        if vpn.isPinging { ProgressView().controlSize(.small) }
                        else { Image(systemName: "wave.3.right") }
                        Text("Ping")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(vpn.isPinging)
                Spacer()
                if let ms = vpn.lastPingMs {
                    Text("\(ms) ms")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(ms < 200 ? .green : (ms < 500 ? .orange : .red))
                } else if !vpn.isPinging {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        if store.settings.selectionMode == .auto {
            return "Auto (fastest) · \(store.settings.routingMode.displayName)"
        }
        let name = store.activeConnection?.name ?? "none"
        return "\(name) · \(store.settings.routingMode.displayName)"
    }

    // MARK: Row

    private func row(_ conn: Connection) -> some View {
        HStack {
            Toggle("", isOn: enabledBinding(conn.id)).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(conn.name)
                Text("\(conn.host)  ·  \(conn.routingMode == .global ? "global" : "rule")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isActive(conn) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Button { editing = conn } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
        }
        .contextMenu {
            Button {
                store.settings.selectionMode = .manual
                store.settings.selectedConnectionID = conn.id
                Task { await vpn.reload(store: store) }
            } label: { Label("Use this connection", systemImage: "checkmark.circle") }
            Button {
                var copy = conn; copy.id = UUID(); copy.name += " copy"
                store.upsert(copy)
            } label: { Label("Duplicate", systemImage: "doc.on.doc") }
            Button(role: .destructive) {
                store.delete(conn.id)
                Task { await vpn.reload(store: store) }
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func isActive(_ conn: Connection) -> Bool {
        store.settings.selectionMode == .manual && store.settings.selectedConnectionID == conn.id
    }

    // MARK: Bindings

    private var selectionBinding: Binding<SelectionMode> {
        Binding(
            get: { store.settings.selectionMode },
            set: { store.settings.selectionMode = $0; Task { await vpn.reload(store: store) } }
        )
    }
    private var routingBinding: Binding<RoutingMode> {
        Binding(
            get: { store.settings.routingMode },
            set: { store.settings.routingMode = $0; Task { await vpn.reload(store: store) } }
        )
    }
    private func enabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.connection(id)?.enabled ?? false },
            set: { newValue in
                guard var c = store.connection(id) else { return }
                c.enabled = newValue; store.upsert(c)
                Task { await vpn.reload(store: store) }
            }
        )
    }
    private var errorBinding: Binding<Bool> {
        Binding(get: { vpn.lastError != nil }, set: { if !$0 { vpn.lastError = nil } })
    }
}

/// Colored status indicator from NEVPNStatus.
struct StatusBadge: View {
    let status: NEVPNStatus
    var body: some View {
        Circle().fill(color).frame(width: 12, height: 12)
    }
    private var color: Color {
        switch status {
        case .connected:                return .green
        case .connecting, .reasserting: return .yellow
        case .disconnecting:            return .orange
        default:                        return .secondary
        }
    }
}
