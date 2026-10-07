import Foundation
import MySQLClient
import Observation

struct TableEntry: Hashable, Identifiable {
    let name: String
    let isView: Bool
    var id: String { name }
}

/// Stored procedures and functions; the raw value is information_schema's ROUTINE_TYPE.
enum RoutineKind: String, Hashable, Sendable {
    case procedure = "PROCEDURE"
    case function = "FUNCTION"
}

struct RoutineRef: Hashable, Sendable {
    let kind: RoutineKind
    let name: String
}

/// What the sidebar can select. Tables, procedures and functions live in
/// separate namespaces in MySQL, so a bare name isn't enough.
enum SidebarItem: Hashable {
    case table(String)
    case routine(RoutineRef)
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
    private(set) var procedures: [String] = []
    private(set) var functions: [String] = []
    private(set) var selectedDatabase: String?
    private(set) var dataModel: TableDataModel?
    private(set) var isLoadingTables = false
    var mode: Mode = .data
    var error: String?

    var selection: SidebarItem? {
        didSet {
            guard selection != oldValue else { return }
            dataModel = selectedTable.flatMap { table in
                selectedDatabase.map { TableDataModel(connection: connection, database: $0, table: table) }
            }
            switch selection {
            case .table: if mode == .query { mode = .data }
            // A routine has no rows to show; its definition is its structure.
            case .routine: mode = .structure
            case nil: break
            }
        }
    }

    var selectedTable: String? {
        if case .table(let name) = selection { name } else { nil }
    }

    var selectedRoutine: RoutineRef? {
        if case .routine(let routine) = selection { routine } else { nil }
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
            selection = nil
            editor.targetDatabase = name
            await reloadObjects()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Reloads the tables, stored procedures and functions of the selected database.
    func reloadObjects() async {
        guard let selectedDatabase else { return }
        isLoadingTables = true
        defer { isLoadingTables = false }
        do {
            let tableResult = try await connection.execute([
                "SELECT TABLE_NAME, TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = ",
                .value(selectedDatabase),
                " ORDER BY TABLE_NAME",
            ]).first
            tables = tableResult?.rows.map { row in
                TableEntry(name: row[0] ?? "", isView: row[1] == "VIEW")
            } ?? []
            // information_schema only lists routines the user has some privilege on.
            let routineRows = try await connection.execute([
                "SELECT ROUTINE_NAME, ROUTINE_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = ",
                .value(selectedDatabase),
                " ORDER BY ROUTINE_NAME",
            ]).first?.rows ?? []
            func names(_ kind: RoutineKind) -> [String] {
                routineRows.filter { $0[1] == kind.rawValue }.compactMap { $0[0] }
            }
            procedures = names(.procedure)
            functions = names(.function)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
