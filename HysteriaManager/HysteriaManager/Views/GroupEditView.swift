import SwiftUI

struct GroupEditView: View {
    @EnvironmentObject var store: ConnectionStore
    @EnvironmentObject var manager: ProxyManager
    let groupID: UUID

    private var group: ConnectionGroup { store.groups.first { $0.id == groupID } ?? ConnectionGroup() }

    private var bound: Binding<ConnectionGroup> {
        Binding(
            get: { store.groups.first { $0.id == groupID } ?? ConnectionGroup() },
            set: { store.upsert($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "rectangle.3.group").font(.title2)
                Text(group.name).font(.title3.weight(.semibold))
                Spacer()
                Button("Test Group") { manager.testGroup(group) }
                    .disabled(manager.isTestingGroup || group.memberIDs.isEmpty)
                if manager.isTestingGroup { ProgressView().controlSize(.small) }
            }
            .padding(12)
            Divider()

            Form {
                Section("Group") {
                    TextField("Name", text: bound.name)
                    Picker("Policy", selection: bound.policy) {
                        ForEach(GroupPolicy.allCases) { Text($0.displayName).tag($0) }
                    }
                    TextField("Test URL", text: bound.testURL)
                    Toggle("Auto-switch to keep healthy", isOn: bound.autoSwitch)
                    Text(policyHelp).font(.caption).foregroundStyle(.secondary)
                }

                Section("Members") {
                    if store.connections.isEmpty {
                        Text("No connections to add.").foregroundStyle(.secondary)
                    }
                    ForEach(store.connections) { conn in
                        Toggle(isOn: memberBinding(conn.id)) {
                            HStack {
                                Text(conn.name)
                                Spacer()
                                LatencyBadge(ms: manager.latencies[conn.id])
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) { store.deleteGroup(groupID) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var policyHelp: String {
        switch group.policy {
        case .urlTest:  return "“Test Group” connects each member, measures the test URL, and switches to the fastest."
        case .failover: return "Stays on the current member; auto-switches to the next when health probes fail."
        case .manual:   return "Never switches automatically. Use the menu/list to pick a member."
        }
    }

    private func memberBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { group.memberIDs.contains(id) },
            set: { isOn in
                var g = group
                if isOn { if !g.memberIDs.contains(id) { g.memberIDs.append(id) } }
                else { g.memberIDs.removeAll { $0 == id } }
                store.upsert(g)
            }
        )
    }
}
