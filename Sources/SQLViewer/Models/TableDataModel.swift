import Foundation
import MySQLClient
import Observation

/// Paged, filterable, sortable view of one table, with inline edits by primary key.
@MainActor @Observable
final class TableDataModel {
    struct Sort: Equatable {
        var column: String
        var ascending: Bool
    }

    let connection: MySQLConnection
    let database: String
    let table: String
    let pageSize = 300

    private(set) var result: QueryResult?
    private(set) var page = 0
    private(set) var isLoading = false
    private(set) var appliedFilter = ""
    private(set) var lastDuration: Duration?
    var sort: Sort?
    var filter = ""
    var error: String?

    private var loadGeneration = 0

    init(connection: MySQLConnection, database: String, table: String) {
        self.connection = connection
        self.database = database
        self.table = table
    }

    var hasNextPage: Bool { (result?.rows.count ?? 0) == pageSize }
    var firstRowNumber: Int { page * pageSize + 1 }

    /// Indexes of the primary-key columns, or empty when edits can't be targeted
    /// safely (no PK, or a PK we only have as a lossy display string).
    var primaryKeyIndexes: [Int] {
        guard let columns = result?.columns else { return [] }
        let indexes = columns.indices.filter { columns[$0].isPrimaryKey }
        let isAddressable = indexes.allSatisfy { ![.binary, .bit].contains(columns[$0].kind) }
        return isAddressable ? indexes : []
    }

    func canEdit(column: Int) -> Bool {
        guard let kind = result?.columns[column].kind else { return false }
        return !primaryKeyIndexes.isEmpty && kind != .binary && kind != .bit
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        error = nil
        var parts: [SQLPart] = ["SELECT * FROM ", .identifier(database), ".", .identifier(table)]
        if !appliedFilter.isEmpty {
            parts += [" WHERE ", .raw(appliedFilter)]
        }
        if let sort {
            parts += [" ORDER BY ", .identifier(sort.column), .raw(sort.ascending ? " ASC" : " DESC")]
        }
        parts.append(.raw(" LIMIT \(pageSize) OFFSET \(page * pageSize)"))

        let started = ContinuousClock.now
        do {
            let loaded = try await connection.execute(parts).first
            guard generation == loadGeneration else { return }
            result = loaded
            lastDuration = ContinuousClock.now - started
        } catch {
            guard generation == loadGeneration else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func applyFilter() async {
        appliedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        page = 0
        await load()
    }

    func setSort(_ newSort: Sort?) async {
        sort = newSort
        page = 0
        await load()
    }

    func goToPage(_ newPage: Int) async {
        page = max(0, newPage)
        await load()
    }

    /// Writes one cell, then re-reads the row so the grid shows what the server
    /// actually stored (type coercion, triggers, ON UPDATE columns).
    func update(row: Int, column: Int, to value: String?) async {
        guard let current = result, canEdit(column: column) else { return }
        let keyIndexes = primaryKeyIndexes
        let columnName = current.columns[column].originalName
        var keyValues = current.rows[row]

        var update: [SQLPart] = [
            "UPDATE ", .identifier(database), ".", .identifier(table),
            " SET ", .identifier(columnName), " = ", .value(value),
        ]
        update += whereClause(keyIndexes, values: keyValues, columns: current.columns)
        update.append(" LIMIT 1")

        do {
            let affected = try await connection.execute(update).first?.affectedRows ?? 0
            if keyIndexes.contains(column) { keyValues[column] = value }

            var select: [SQLPart] = ["SELECT * FROM ", .identifier(database), ".", .identifier(table)]
            select += whereClause(keyIndexes, values: keyValues, columns: current.columns)
            select.append(" LIMIT 1")
            if let fresh = try await connection.execute(select).first?.rows.first,
               result?.columns == current.columns, row < (result?.rows.count ?? 0) {
                result?.rows[row] = fresh
            }
            if affected == 0, value != current.rows[row][column] {
                error = "El servidor no modificó la fila (¿cambió desde que se cargó?)."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func whereClause(_ keyIndexes: [Int], values: [String?], columns: [Column]) -> [SQLPart] {
        var parts: [SQLPart] = [" WHERE "]
        for (position, index) in keyIndexes.enumerated() {
            if position > 0 { parts.append(" AND ") }
            parts += [.identifier(columns[index].originalName), " = ", .value(values[index])]
        }
        return parts
    }
}
