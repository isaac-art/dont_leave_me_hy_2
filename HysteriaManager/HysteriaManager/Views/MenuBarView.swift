import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var manager: ProxyManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.connections.isEmpty {
                emptyState
            } else if store.connections.count + store.groups.count > 8 {
                // Many items: scroll, but a ScrollView needs an explicit height inside
                // a MenuBarExtra window or it collapses to nothing.
                ScrollView { connectionsStack }
                    .frame(height: 380)
            } else {
                // Few items: lay them out directly so the menu sizes to fit them all.
                connectionsStack
            }

            Divider()
            footer
        }
        .frame(width: 320)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusDot(state: manager.state)
                Text(statusTitle).font(.headline)
                Spacer()
                if manager.state.isActive {
                    Button("Disconnect") { manager.disconnect() }
                        .controlSize(.small)
                }
            }
            if manager.state == .connected {
                TrafficLabel(up: manager.traffic.upBytesPerSec, down: manager.traffic.downBytesPerSec)
                Text("Session ↑ \(TrafficMonitor.formatBytes(manager.sessionUpBytes))  ↓ \(TrafficMonitor.formatBytes(manager.sessionDownBytes))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let err = manager.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(3)
                Button {
                    openWindow(id: "log")
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Label("Show Log", systemImage: "doc.text.magnifyingglass") }
                    .controlSize(.small)
            }
        }
        .padding(12)
    }

    private var statusTitle: String {
        switch manager.state {
        case .connected:    return manager.activeConnection?.name ?? "Connected"
        case .connecting:   return "Connecting…"
        case .error:        return "Error"
        case .disconnected: return "Not connected"
        }
    }

    // MARK: Rows

    /// The full stack of connection rows (active first) + groups.
    @ViewBuilder
    private var connectionsStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader("Connections")
            ForEach(orderedConnections) { conn in
                connectionRow(conn)
            }
            if !store.groups.isEmpty {
                Divider().padding(.vertical, 4)
                sectionHeader("Groups")
                ForEach(store.groups) { group in
                    groupRow(group)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func connectionRow(_ conn: Connection) -> some View {
        let active = isActive(conn)
        let connecting = manager.activeConnectionID == conn.id && manager.state == .connecting
        return Button {
            // Click a connection to connect/switch to it; click the active one to disconnect.
            manager.toggle(conn)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(conn.name).fontWeight(active ? .semibold : .regular)
                    Text(conn.host).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if connecting {
                    ProgressView().controlSize(.small)
                } else {
                    LatencyBadge(ms: manager.latencies[conn.id])
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(active ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(active ? "Connected — click to disconnect" : "Click to connect to \(conn.name)")
    }

    private func groupRow(_ group: ConnectionGroup) -> some View {
        HStack {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                Text("\(group.memberIDs.count) members · \(group.policy.displayName)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Test") { manager.testGroup(group) }
                .controlSize(.small)
                .disabled(manager.isTestingGroup)
        }
        .padding(.vertical, 3)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Manage", systemImage: "slider.horizontal.3")
            }
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                openWindow(id: "log")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Log", systemImage: "doc.text.magnifyingglass")
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No connections yet").foregroundStyle(.secondary)
            Button("Add a Connection") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func isActive(_ conn: Connection) -> Bool {
        manager.activeConnectionID == conn.id && manager.state.isActive
    }

    /// All connections, with the active one pinned to the top of the stack.
    private var orderedConnections: [Connection] {
        let conns = store.connections
        guard let activeID = manager.activeConnectionID, manager.state.isActive else { return conns }
        return conns.filter { $0.id == activeID } + conns.filter { $0.id != activeID }
    }
}
