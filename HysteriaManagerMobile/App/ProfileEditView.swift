import SwiftUI

struct ProfileEditView: View {
    @EnvironmentObject var store: MobileStore
    @EnvironmentObject var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss

    let connectionID: UUID
    let isNew: Bool
    @State var draft: Connection

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $draft.name)
                TextField("Server (host:port)", text: $draft.server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Auth password", text: $draft.auth)
            }
            Section("TLS") {
                TextField("SNI", text: $draft.sni, prompt: Text("defaults to host"))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Allow insecure", isOn: $draft.insecure)
            }
            Section("Obfuscation") {
                Picker("Type", selection: $draft.obfsType) {
                    ForEach(ObfsType.allCases) { Text($0.displayName).tag($0) }
                }
                if draft.obfsType == .salamander {
                    SecureField("Obfs password", text: $draft.obfsPassword)
                }
            }
            Section("Bandwidth (optional)") {
                Stepper("Up: \(draft.upMbps) Mbps", value: $draft.upMbps, in: 0...10000, step: 10)
                Stepper("Down: \(draft.downMbps) Mbps", value: $draft.downMbps, in: 0...10000, step: 10)
            }
            Section("Routing") {
                Picker("Mode", selection: $draft.routingMode) {
                    ForEach(RoutingMode.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Include in fastest selection", isOn: $draft.enabled)
                Text("On iOS, routing is applied app-wide (set on the main screen). This per-profile mode is used if this becomes the single active profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !isNew {
                Section {
                    Button {
                        store.settings.selectionMode = .manual
                        store.settings.selectedConnectionID = draft.id
                        save()
                    } label: { Label("Use this connection", systemImage: "checkmark.circle") }
                    Button(role: .destructive) {
                        store.delete(draft.id)
                        Task { await vpn.reload(store: store) }
                        dismiss()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle(isNew ? "New Connection" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(draft.server.isEmpty)
            }
        }
    }

    private func save() {
        store.upsert(draft)
        Task { await vpn.reload(store: store) }
        dismiss()
    }
}
