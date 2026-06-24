import SwiftUI

@main
struct HysteriaManagerApp: App {
    @StateObject private var store: ConnectionStore
    @StateObject private var manager: ProxyManager

    init() {
        let store = ConnectionStore()
        _store = StateObject(wrappedValue: store)
        _manager = StateObject(wrappedValue: ProxyManager(store: store))
    }

    var body: some Scene {
        // Menu bar dropdown — the primary surface.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(manager)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        // Full management window, opened on demand from the menu.
        Window("Hysteria Manager", id: "main") {
            MainView()
                .environmentObject(store)
                .environmentObject(manager)
                .frame(minWidth: 820, minHeight: 540)
        }
        .windowResizability(.contentSize)

        Window("Hysteria Log", id: "log") {
            LogView()
                .environmentObject(manager)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(manager)
                .frame(width: 480)
        }
    }

    private var menuBarSymbol: String {
        switch manager.state {
        case .connected:   return "bolt.horizontal.circle.fill"
        case .connecting:  return "bolt.horizontal.circle"
        case .error:       return "exclamationmark.triangle.fill"
        case .disconnected: return "bolt.horizontal.circle"
        }
    }
}
