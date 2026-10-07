import Foundation
import MySQLClient
import Testing
@testable import SQLViewer

/// Same opt-in as MySQLClientTests: SQLVIEWER_TEST_MYSQL=1 swift test
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SQLVIEWER_TEST_MYSQL"] == "1"), .serialized)
@MainActor
struct RoutineTests {
    static let database = "sqlviewer_routine_test"
    static let procedure = RoutineRef(kind: .procedure, name: "orders")
    static let function = RoutineRef(kind: .function, name: "orders")

    /// A table, a procedure and a function all named `orders`: separate namespaces in MySQL.
    func withSchema(_ body: (WorkspaceModel) async throws -> Void) async throws {
        let setup = try await MySQLConnection.connect(ConnectionOptions(host: "localhost", user: "root"))
        defer { setup.close() }
        _ = try await setup.query("""
            DROP DATABASE IF EXISTS \(Self.database); CREATE DATABASE \(Self.database);
            CREATE TABLE \(Self.database).orders (id INT PRIMARY KEY);
            CREATE PROCEDURE \(Self.database).orders(IN since DATE, OUT total VARCHAR(10))
              COMMENT 'Cuenta pedidos'
              BEGIN SELECT COUNT(*) INTO total FROM \(Self.database).orders; END;
            CREATE PROCEDURE \(Self.database).cleanup() BEGIN END;
            CREATE FUNCTION \(Self.database).orders(since DATE, minimum INT) RETURNS DECIMAL(10,2)
              DETERMINISTIC READS SQL DATA
              RETURN 0
            """)
        let saved = SavedConnection(host: "localhost", user: "root", database: Self.database)
        let model = try await WorkspaceModel.open(connection: saved, password: "")
        defer { model.close() }
        do { try await body(model) } catch {
            _ = try? await setup.query("DROP DATABASE \(Self.database)")
            throw error
        }
        _ = try await setup.query("DROP DATABASE \(Self.database)")
    }

    @Test func listsRoutinesApartFromTables() async throws {
        try await withSchema { model in
            #expect(model.tables.map(\.name) == ["orders"])
            #expect(model.procedures == ["cleanup", "orders"])
            #expect(model.functions == ["orders"])
        }
    }

    @Test func selectingRoutineShowsStructureWithoutTableData() async throws {
        try await withSchema { model in
            model.mode = .query
            model.selection = .routine(Self.function)
            #expect(model.mode == .structure)
            #expect(model.selectedTable == nil)
            #expect(model.dataModel == nil)

            model.selection = .table("orders")
            #expect(model.selectedRoutine == nil)
            #expect(model.dataModel?.table == "orders")
        }
    }

    @Test func loadsProcedure() async throws {
        try await withSchema { model in
            let detail = try await RoutineDetail.load(connection: model.connection, database: Self.database, routine: Self.procedure)
            #expect(detail.definition?.contains("PROCEDURE `orders`") == true)
            #expect(detail.parameters?.rows == [["IN", "since", "date"], ["OUT", "total", "varchar(10)"]])
            #expect(detail.returns == nil)
            #expect(detail.comment == "Cuenta pedidos")
            #expect(detail.securityType == "DEFINER")

            let empty = RoutineRef(kind: .procedure, name: "cleanup")
            let cleanup = try await RoutineDetail.load(connection: model.connection, database: Self.database, routine: empty)
            #expect(cleanup.parameters?.rows.isEmpty == true)
        }
    }

    @Test func loadsFunctionWithoutReturnValueAsParameter() async throws {
        try await withSchema { model in
            let detail = try await RoutineDetail.load(connection: model.connection, database: Self.database, routine: Self.function)
            #expect(detail.definition?.contains("FUNCTION `orders`") == true)
            #expect(detail.parameters?.rows == [["IN", "since", "date"], ["IN", "minimum", "int"]])
            #expect(detail.returns == "decimal(10,2)")
        }
    }

    @Test func droppedRoutineReportsMissing() async throws {
        try await withSchema { model in
            let missing = RoutineRef(kind: .function, name: "nope")
            await #expect(throws: RoutineDetail.Missing.self) {
                try await RoutineDetail.load(connection: model.connection, database: Self.database, routine: missing)
            }
        }
    }
}
