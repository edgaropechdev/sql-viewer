import Foundation
import Testing
@testable import MySQLClient

/// Runs against a real server. Enable with:
///   SQLVIEWER_TEST_MYSQL=1 swift test
/// Optional: SQLVIEWER_TEST_HOST / _USER / _PASSWORD (defaults: localhost / root / "").
/// Creates and drops a scratch database named `sqlviewer_test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SQLVIEWER_TEST_MYSQL"] == "1"), .serialized)
struct MySQLConnectionTests {
    static let database = "sqlviewer_test"

    static var options: ConnectionOptions {
        let env = ProcessInfo.processInfo.environment
        return ConnectionOptions(
            host: env["SQLVIEWER_TEST_HOST"] ?? "localhost",
            user: env["SQLVIEWER_TEST_USER"] ?? "root",
            password: env["SQLVIEWER_TEST_PASSWORD"] ?? ""
        )
    }

    func withScratchDatabase(_ body: (MySQLConnection) async throws -> Void) async throws {
        let connection = try await MySQLConnection.connect(Self.options)
        defer { connection.close() }
        _ = try await connection.query("DROP DATABASE IF EXISTS \(Self.database); CREATE DATABASE \(Self.database)")
        try await connection.selectDatabase(Self.database)
        do {
            try await body(connection)
        } catch {
            _ = try? await connection.query("DROP DATABASE \(Self.database)")
            throw error
        }
        _ = try await connection.query("DROP DATABASE \(Self.database)")
    }

    @Test func decodesTypesAndNulls() async throws {
        try await withScratchDatabase { connection in
            _ = try await connection.query("""
                CREATE TABLE t (
                  id INT PRIMARY KEY, name VARCHAR(20), note TEXT NULL, flags BIT(8),
                  raw VARBINARY(4), doc JSON, created DATETIME(3)
                );
                INSERT INTO t VALUES (1, 'ñandú 🙂', NULL, b'00000101', 0xDEADBEEF, '{"a": 1}', '2026-10-02 10:11:12.345')
                """)
            let result = try #require(try await connection.query("SELECT * FROM t").first)
            #expect(result.columns.map(\.name) == ["id", "name", "note", "flags", "raw", "doc", "created"])
            #expect(result.columns.map(\.kind) == [.numeric, .text, .text, .bit, .binary, .json, .temporal])
            #expect(result.columns[0].isPrimaryKey && !result.columns[0].isNullable)
            #expect(result.rows == [["1", "ñandú 🙂", nil, "5", "0xDEADBEEF", #"{"a": 1}"#, "2026-10-02 10:11:12.345"]])
        }
    }

    @Test func escapesValues() async throws {
        try await withScratchDatabase { connection in
            _ = try await connection.query("CREATE TABLE t (v TEXT)")
            let nasty = #"O'Reilly \ "quoted" ; DROP TABLE t; --"#
            let insert = try await connection.execute(["INSERT INTO t VALUES (", .value(nasty), "), (", .value(nil), ")"])
            #expect(insert.first?.affectedRows == 2)
            let rows = try await connection.query("SELECT v FROM t").first?.rows
            #expect(rows == [[nasty], [nil]])
        }
    }

    @Test func returnsEveryResultOfAMultiStatement() async throws {
        let connection = try await MySQLConnection.connect(Self.options)
        defer { connection.close() }
        let results = try await connection.query("SELECT 1 AS a; DO 0; SELECT 2 AS b, 3 AS c")
        #expect(results.map(\.columns.count) == [1, 0, 2])
        #expect(results[2].rows == [["2", "3"]])
    }

    @Test func truncatesAtMaxRowsAndStaysUsable() async throws {
        let connection = try await MySQLConnection.connect(Self.options)
        defer { connection.close() }
        let result = try #require(try await connection.query("SELECT * FROM information_schema.COLUMNS", maxRows: 5).first)
        #expect(result.rows.count == 5 && result.isTruncated)
        let after = try await connection.query("SELECT 42").first?.rows
        #expect(after == [["42"]])
    }

    @Test func cancellingTheTaskKillsTheQuery() async throws {
        let connection = try await MySQLConnection.connect(Self.options)
        defer { connection.close() }
        let started = ContinuousClock.now
        let task = Task { try await connection.query("SELECT SLEEP(20)") }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        _ = try? await task.value
        #expect(ContinuousClock.now - started < .seconds(5))
        let after = try await connection.query("SELECT 1").first?.rows
        #expect(after == [["1"]])
    }

    @Test func reportsServerErrors() async throws {
        let connection = try await MySQLConnection.connect(Self.options)
        defer { connection.close() }
        await #expect {
            try await connection.query("SELECT * FROM no_such_db.no_such_table")
        } throws: { ($0 as? MySQLError)?.code == 1049 || ($0 as? MySQLError)?.code == 1146 }
    }
}
