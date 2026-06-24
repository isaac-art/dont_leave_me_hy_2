import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: MobileStore
    @EnvironmentObject var vpn: VPNManager
    @Environment(\.dismiss) private var dismiss

    private var s: Binding<MobileSettings> {
        Binding(get: { store.settings }, set: { store.settings = $0 })
    }

    var body: some View {
        Form {
            Section("Routing") {
                Picker("Default routing", selection: s.routingMode) {
                    ForEach(RoutingMode.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Rule-based keeps China (geoip:cn / geosite:cn) and private addresses direct and tunnels everything else.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Fastest selection") {
                TextField("Test URL", text: s.testURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Stepper("Test every \(store.settings.testIntervalSec)s",
                        value: s.testIntervalSec, in: 60...3600, step: 60)
                Text("Used by the URL-test that auto-picks the fastest connection.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Connect on launch", isOn: s.connectOnLaunch)
                Toggle("Reconnect automatically (on-demand)", isOn: onDemandBinding)
                Text("On-demand keeps the VPN active across network changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Engine") {
                LabeledContent("Tunnel", value: "sing-box (Libbox)")
                LabeledContent("Protocol", value: "hysteria2")
                Text("Routing runs inside sing-box: hysteria2 outbound + geoip/geosite rule-sets. Requires Libbox.xcframework bundled at build time.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Tailscale") {
                Toggle("Join Tailscale", isOn: tailscaleBinding)
                if store.settings.tailscaleEnabled {
                    SecureField("Auth key (tskey-…)", text: s.tailscaleAuthKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Accept subnet routes", isOn: s.tailscaleAcceptRoutes)
                }
                Text("Joins your tailnet inside this tunnel — reach your other devices by their 100.x address while the internet still goes out through hysteria2. Get a key from the Tailscale admin console → Settings → Keys. Reconnect after changing the key or routes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                Button {
                    let data = SingboxConfigBuilder.build(connections: store.connections, settings: store.settings)
                    UIPasteboard.general.string = String(data: data, encoding: .utf8) ?? ""
                } label: {
                    Label("Copy generated sing-box config", systemImage: "doc.on.clipboard")
                }
                Text("Paste it into a file and run Tools/check-config.sh on your Mac to validate it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private var tailscaleBinding: Binding<Bool> {
        Binding(
            get: { store.settings.tailscaleEnabled },
            set: { store.settings.tailscaleEnabled = $0; Task { await vpn.reload(store: store) } }
        )
    }

    private var onDemandBinding: Binding<Bool> {
        Binding(
            get: { store.settings.onDemandEnabled },
            set: { store.settings.onDemandEnabled = $0; Task { await vpn.reload(store: store) } }
        )
    }
}
