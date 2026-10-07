import Foundation
import MySQLClient
import Testing
@testable import SQLViewer

/// Same opt-in as MySQLClientTests: SQLVIEWER_TEST_MYSQL=1 swift test
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SQLVIEWER_TEST_MYSQL"] == "1"), .serialized)
@MainActor
struct TableDataModelTests {
    static let database = "sqlviewer_ui_test"

    func withTable(_ body: (MySQLConnection) async throws -> Void) async throws {
        let connection = try await MySQLConnection.connect(ConnectionOptions(host: "localhost", user: "root"))
        defer { connection.close() }
        _ = try await connection.query("""
            DROP DATABASE IF EXISTS \(Self.database); CREATE DATABASE \(Self.database);
            CREATE TABLE \(Self.database).people (
              id INT PRIMARY KEY, name VARCHAR(40) NOT NULL, age INT NULL,
              updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            );
            CREATE TABLE \(Self.database).nokey (v INT);
            INSERT INTO \(Self.database).people (id, name, age)
              WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 450)
              SELECT i, CONCAT('person ', i), i % 90 FROM n
            """)
        do { try await body(connection) } catch {
            _ = try? await connection.query("DROP DATABASE \(Self.database)")
            throw error
        }
        _ = try await connection.query("DROP DATABASE \(Self.database)")
    }

    @Test func pagesFiltersAndSorts() async throws {
        try await withTable { connection in
            let model = TableDataModel(connection: connection, database: Self.database, table: "people")
            await model.load()
            #expect(model.result?.rows.count == 300 && model.hasNextPage)
            await model.goToPage(1)
            #expect(model.result?.rows.count == 150 && !model.hasNextPage && model.firstRowNumber == 301)

            model.filter = "age >= 80"
            await model.applyFilter()
            #expect(model.page == 0 && model.result?.rows.allSatisfy { Int($0[2]!)! >= 80 } == true)

            await model.setSort(.init(column: "id", ascending: false))
            #expect(model.result?.rows.first?[0] == "449")

            model.filter = "nope = 1"
            await model.applyFilter()
            #expect(model.error?.contains("1054") == true)
        }
    }

    @Test func editsCellsByPrimaryKey() async throws {
        try await withTable { connection in
            let model = TableDataModel(connection: connection, database: Self.database, table: "people")
            await model.load()
            #expect(model.primaryKeyIndexes == [0] && model.canEdit(column: 1))

            await model.update(row: 4, column: 1, to: "O'Brien ñ")
            await model.update(row: 4, column: 2, to: nil)
            #expect(model.error == nil)
            #expect(model.result?.rows[4][1] == "O'Brien ñ" && model.result?.rows[4][2] == nil)

            // Editing the key itself must re-read the row under its new id.
            await model.update(row: 4, column: 0, to: "5000")
            #expect(model.result?.rows[4][0] == "5000" && model.result?.rows[4][1] == "O'Brien ñ")

            // Strict mode rejects the value; the grid keeps the stored one.
            await model.update(row: 0, column: 2, to: "not a number")
            #expect(model.error?.contains("1366") == true)
            #expect(model.result?.rows[0][2] == "1")

            let stored = try await connection.query("SELECT name, age FROM \(Self.database).people WHERE id = 5000").first?.rows
            #expect(stored == [["O'Brien ñ", nil]])
        }
    }

    @Test func tablesWithoutKeyAreReadOnly() async throws {
        try await withTable { connection in
            let model = TableDataModel(connection: connection, database: Self.database, table: "nokey")
            await model.load()
            #expect(model.primaryKeyIndexes.isEmpty && !model.canEdit(column: 0))
        }
    }
}
