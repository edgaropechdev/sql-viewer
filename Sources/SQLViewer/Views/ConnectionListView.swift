import SwiftUI

struct ConnectionListView: View {
    let sessions: SessionsModel

    @Environment(ConnectionStore.self) private var store
    @State private var selection: SavedConnection.ID?
    @State private var editing: SavedConnection?
    @State private var isNew = false
    @State private var connectingID: SavedConnection.ID?
    @State private var connectError: String?

    var body: some View {
        Group {
            if store.connections.isEmpty {
                ContentUnavailableView {
                    Label("Sin conexiones", systemImage: "cylinder.split.1x2")
                } description: {
                    Text("Agrega o conéctate manualmente a una base de datos MySQL local o remota.")
                } actions: {
                    Button("Nueva conexión") { create() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(store.connections, selection: $selection) { connection in
                    row(connection)
                        .tag(connection.id)
                        .contextMenu { menu(for: connection) }
                }
                .contextMenu(forSelectionType: SavedConnection.ID.self) { _ in
                } primaryAction: { ids in
                    if let id = ids.first, let connection = store.connections.first(where: { $0.id == id }) {
                        connect(connection)
                    }
                }
            }
        }
        .navigationTitle("Conexiones")
        .toolbar {
            ToolbarItemGroup {
                Button("Conectar", systemImage: "bolt.horizontal") {
                    if let connection = selected { connect(connection) }
                }
                .disabled(selected == nil || connectingID != nil)
                .keyboardShortcut(.return, modifiers: [])

                Button("Nueva conexión", systemImage: "plus") { create() }
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $editing) { connection in
            ConnectionFormView(connection: connection, isNew: isNew, onConnect: sessions.add)
        }
        .alert("No se pudo conectar", isPresented: .constant(connectError != nil)) {
            Button("OK") { connectError = nil }
        } message: {
            Text(connectError ?? "")
        }
    }

    private var selected: SavedConnection? {
        store.connections.first { $0.id == selection }
    }

    private func row(_ connection: SavedConnection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cylinder.split.1x2")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName).font(.headline)
                Text(connection.database.isEmpty ? connection.summary : "\(connection.summary) / \(connection.database)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if connectingID == connection.id {
                ProgressView().controlSize(.small)
            } else if sessions.session(for: connection.id) != nil {
                Text("Abierta")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func menu(for connection: SavedConnection) -> some View {
        Button("Conectar") { connect(connection) }
        Button("Editar…") {
            isNew = false
            editing = connection
        }
        Button("Duplicar") {
            var copy = connection
            copy.id = UUID()
            copy.name = "\(connection.displayName) copia"
            try? store.save(copy, password: Keychain.password(for: connection.id) ?? "")
        }
        Divider()
        Button("Eliminar", role: .destructive) { store.delete(connection) }
    }

    private func create() {
        isNew = true
        editing = SavedConnection()
    }

    /// Switches to the session if this connection is already open.
    private func connect(_ connection: SavedConnection) {
        if let open = sessions.session(for: connection.id) {
            sessions.select(open)
            return
        }
        guard connectingID == nil else { return }
        connectingID = connection.id
        Task {
            defer { connectingID = nil }
            do {
                sessions.add(try await WorkspaceModel.open(connection))
            } catch {
                connectError = error.localizedDescription
            }
        }
    }
}
