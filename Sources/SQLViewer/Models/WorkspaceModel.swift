import Foundation
import MySQLClient
import Observation

struct TableEntry: Hashable, Identifiable {
    let name: String
    let isView: Bool
    var id: String { name }
}

/// State for one open connection window: schema browser + data + SQL editor.
///
/// Browsing (sidebar, table data, structure) shares one session; the SQL editor
/// gets its own so a long query never blocks navigation.
@MainActor @Observable
final class WorkspaceModel: Identifiable {
    enum Mode: Hashable {
        case data, structure, query
    }

    let saved: SavedConnection
    let connection: MySQLConnection
    let editor: QueryEditorModel

    private(set) var databases: [String] = []
    private(set) var tables: [TableEntry] = []
    private(set) var selectedDatabase: String?
    private(set) var dataModel: TableDataModel?
    private(set) var isLoadingTables = false
    var mode: Mode = .data
    var error: String?

    var selectedTable: String? {
        didSet {
            guard selectedTable != oldValue else { return }
            dataModel = selectedTable.flatMap { table in
                selectedDatabase.map { TableDataModel(connection: connection, database: $0, table: table) }
            }
            if selectedTable != nil, mode == .query { mode = .data }
        }
    }

    static func open(_ saved: SavedConnection) async throws -> WorkspaceModel {
        try await open(connection: saved, password: Keychain.password(for: saved.id) ?? "")
    }

    static func open(connection: SavedConnection, password: String) async throws -> WorkspaceModel {
        let options = connection.options(password: password)
        let conn = try await MySQLConnection.connect(options)
        let model = WorkspaceModel(saved: connection, connection: conn)
        await model.reloadDatabases()
        if let database = options.database {
            await model.selectDatabase(database)
        }
        return model
    }

    private init(saved: SavedConnection, connection: MySQLConnection) {
        self.saved = saved
        self.connection = connection
        editor = QueryEditorModel(options: connection.options, storageKey: "editor.\(saved.id.uuidString)")
    }

    func close() {
        editor.close()
        connection.close()
    }

    func reloadDatabases() async {
        do {
            let result = try await connection.query("SHOW DATABASES").first
            databases = result?.rows.compactMap { $0.first ?? nil } ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func selectDatabase(_ name: String) async {
        do {
            try await connection.selectDatabase(name)
            selectedDatabase = name
            selectedTable = nil
            editor.targetDatabase = name
            await reloadTables()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func reloadTables() async {
        guard let selectedDatabase else { return }
        isLoadingTables = true
        defer { isLoadingTables = false }
        do {
            let result = try await connection.execute([
                "SELECT TABLE_NAME, TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = ",
                .value(selectedDatabase),
                " ORDER BY TABLE_NAME",
            ]).first
            tables = result?.rows.map { row in
                TableEntry(name: row[0] ?? "", isView: row[1] == "VIEW")
            } ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }
}
