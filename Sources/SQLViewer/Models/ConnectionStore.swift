import Foundation
import Observation

/// Saved connections, persisted as JSON in Application Support.
@MainActor @Observable
final class ConnectionStore {
    private(set) var connections: [SavedConnection] = []
    var lastError: String?

    private let fileURL: URL

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "SQLViewer", directoryHint: .isDirectory)
        fileURL = directory.appending(path: "connections.json")
        load()
    }

    func save(_ connection: SavedConnection, password: String) throws {
        try Keychain.setPassword(password, for: connection.id)
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        try persist()
    }

    func delete(_ connection: SavedConnection) {
        connections.removeAll { $0.id == connection.id }
        Keychain.deletePassword(for: connection.id)
        do { try persist() } catch { lastError = error.localizedDescription }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            connections = try JSONDecoder().decode([SavedConnection].self, from: Data(contentsOf: fileURL))
        } catch {
            lastError = "No se pudieron leer las conexiones guardadas: \(error.localizedDescription)"
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(connections).write(to: fileURL, options: .atomic)
    }
}
