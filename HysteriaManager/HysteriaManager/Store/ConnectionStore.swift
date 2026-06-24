import Foundation
import Combine

/// Owns the persisted document (connections, groups, settings) and writes it to
/// Application Support as JSON. Pure data — no networking or process control.
@MainActor
final class ConnectionStore: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var groups: [ConnectionGroup] = []
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL
    private var saveCancellable: AnyCancellable?
    private var isLoading = false

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HysteriaManager", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("store.json")
        load()

        // Debounced autosave whenever any published property changes.
        saveCancellable = objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
    }

    /// Directory used for generated configs, logs, etc.
    var supportDirectory: URL { fileURL.deletingLastPathComponent() }

    // MARK: Load / save

    func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let doc = try? JSONDecoder().decode(StoreDocument.self, from: data) else { return }
        connections = doc.connections
        groups = doc.groups
        settings = doc.settings
    }

    func save() {
        guard !isLoading else { return }
        let doc = StoreDocument(connections: connections, groups: groups, settings: settings)
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

    func deleteConnection(_ id: UUID) {
        connections.removeAll { $0.id == id }
        for i in groups.indices { groups[i].memberIDs.removeAll { $0 == id } }
        if settings.lastConnectionID == id { settings.lastConnectionID = nil }
    }

    func upsert(_ group: ConnectionGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
        } else {
            groups.append(group)
        }
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
    }

    func members(of group: ConnectionGroup) -> [Connection] {
        group.memberIDs.compactMap { id in connections.first { $0.id == id } }
    }
}
