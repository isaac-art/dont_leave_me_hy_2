import SwiftUI

enum SidebarItem: Hashable {
    case connection(UUID)
    case group(UUID)
}

struct MainView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var manager: ProxyManager
    @State private var selection: SidebarItem?
    @State private var showingImport = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 240)
        } detail: {
            detail
        }
        .sheet(isPresented: $showingImport) {
            ImportView { imported in
                for c in imported { store.upsert(c) }
                if let first = imported.first { selection = .connection(first.id) }
            }
            .environmentObject(store)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Connections") {
                ForEach(store.connections) { conn in
                    HStack {
                        StatusDot(state: rowState(conn))
                        Text(conn.name)
                        Spacer()
                        LatencyBadge(ms: manager.latencies[conn.id])
                    }
                    .tag(SidebarItem.connection(conn.id))
                    .contextMenu {
                        Button("Duplicate") { duplicate(conn) }
                        Button("Delete", role: .destructive) { store.deleteConnection(conn.id) }
                    }
                }
            }
            if !store.groups.isEmpty {
                Section("Groups") {
                    ForEach(store.groups) { group in
                        Label(group.name, systemImage: "rectangle.3.group")
                            .tag(SidebarItem.group(group.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.deleteGroup(group.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup {
                Button { showingImport = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                Menu {
                    Button("New Connection") { addConnection() }
                    Button("New Group") { addGroup() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .connection(let id):
            if store.connection(id) != nil {
                ConnectionDetailView(connectionID: id)
                    .id(id)
            } else { placeholder }
        case .group(let id):
            if store.groups.contains(where: { $0.id == id }) {
                GroupEditView(groupID: id)
                    .id(id)
            } else { placeholder }
        case .none:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Select a connection, or add one.").foregroundStyle(.secondary)
            HStack {
                Button("New Connection") { addConnection() }
                Button("Import…") { showingImport = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func rowState(_ conn: Connection) -> ConnectionState {
        manager.activeConnectionID == conn.id ? manager.state : .disconnected
    }

    private func addConnection() {
        var c = Connection()
        c.name = "New Connection"
        store.upsert(c)
        selection = .connection(c.id)
    }

    private func duplicate(_ conn: Connection) {
        var copy = conn
        copy.id = UUID()
        copy.name = conn.name + " copy"
        store.upsert(copy)
        selection = .connection(copy.id)
    }

    private func addGroup() {
        let g = ConnectionGroup()
        store.upsert(g)
        selection = .group(g.id)
    }
}
