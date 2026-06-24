import Foundation
import Combine

enum SelectionMode: String, Codable, CaseIterable, Identifiable {
    case auto       // urltest — fastest wins
    case manual     // pinned to a chosen profile
    var id: String { rawValue }
    var displayName: String { self == .auto ? "Auto (fastest)" : "Manual" }
}

struct MobileSettings: Codable {
    /// Global routing policy (iOS routes the whole device, so this is app-wide).
    var routingMode: RoutingMode = .ruleBased
    var selectionMode: SelectionMode = .auto
    var selectedConnectionID: UUID? = nil

    var testURL: String = "https://www.gstatic.com/generate_204"
    var testIntervalSec: Int = 300

    var connectOnLaunch: Bool = false
    var onDemandEnabled: Bool = false   // reconnect automatically on network change

    /// Join a Tailscale tailnet inside the same tunnel (tailnet traffic → Tailscale,
    /// everything else still routes via hysteria2 / CN-direct).
    var tailscaleEnabled: Bool = false
    var tailscaleAuthKey: String = ""
    /// Accept subnet routes advertised by tailnet routers (reach LANs behind peers).
    var tailscaleAcceptRoutes: Bool = true
}

struct MobileStoreDocument: Codable {
    var connections: [Connection] = []
    var settings: MobileSettings = MobileSettings()
}

/// Persists profiles + settings to the App Group container (JSON), so the data is
/// reachable from the app (and any future widget/control).
@MainActor
final class MobileStore: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var settings: MobileSettings = MobileSettings()

    private let fileURL = AppGroup.container.appendingPathComponent("store.json")
    private var saveCancellable: AnyCancellable?
    private var isLoading = false

    init() {
        load()
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let doc = try? JSONDecoder().decode(MobileStoreDocument.self, from: data) else { return }
        connections = doc.connections
        settings = doc.settings
    }

    func save() {
        guard !isLoading else { return }
        let doc = MobileStoreDocument(connections: connections, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(doc) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Mutations

    func connection(_ id: UUID?) -> Connection? {
        guard let id else { return nil }
        return connections.first { $0.id == id }
    }

    func upsert(_ connection: Connection) {
        if let idx = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[idx] = connection
        } else {
            connections.append(connection)
        }
    }

    func delete(_ id: UUID) {
        connections.removeAll { $0.id == id }
        if settings.selectedConnectionID == id { settings.selectedConnectionID = nil }
    }

    func add(_ imported: [Connection]) {
        for c in imported { connections.append(c) }
    }

    /// The currently-targeted connection (manual pick, or first enabled for display).
    var activeConnection: Connection? {
        if settings.selectionMode == .manual {
            return connection(settings.selectedConnectionID) ?? connections.first
        }
        return connections.first { $0.enabled }
    }
}
