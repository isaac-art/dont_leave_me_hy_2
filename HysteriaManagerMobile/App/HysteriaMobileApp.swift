import SwiftUI
import NetworkExtension

@main
struct HysteriaMobileApp: App {
    @StateObject private var store = MobileStore()
    @StateObject private var vpn = VPNManager()

    var body: some Scene {
        WindowGroup {
            ProfilesView()
                .environmentObject(store)
                .environmentObject(vpn)
                .task {
                    if store.settings.connectOnLaunch, !vpn.isActive {
                        await vpn.connect(store: store)
                    }
                }
                .onOpenURL { url in
                    // Allow importing via hysteria2:// links opened from elsewhere.
                    let imported = URIParser.parseMany(url.absoluteString)
                    if !imported.isEmpty { store.add(imported) }
                }
        }
    }
}
