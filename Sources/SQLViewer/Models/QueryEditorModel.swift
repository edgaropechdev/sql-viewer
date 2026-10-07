import AppKit
import Foundation
import MySQLClient
import Observation

/// The SQL editor tab. Owns a dedicated session, opened on first run.
@MainActor @Observable
final class QueryEditorModel {
    struct Failure {
        let statement: Int
        let total: Int
        let message: String
    }

    var text: String {
        didSet { UserDefaults.standard.set(text, forKey: storageKey) }
    }
    private(set) var results: [QueryResult] = []
    var selectedResult = 0
    private(set) var isRunning = false
    private(set) var status: String?
    private(set) var failure: Failure?

    /// Database chosen in the sidebar; applied before the next run.
    @ObservationIgnored var targetDatabase: String?
    @ObservationIgnored let editor = SQLEditorController()

    @ObservationIgnored private let options: ConnectionOptions
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private var connection: MySQLConnection?
    @ObservationIgnored private var syncedDatabase: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let maxRows = 10_000

    init(options: ConnectionOptions, storageKey: String) {
        self.options = options
        self.storageKey = storageKey
        text = UserDefaults.standard.string(forKey: storageKey) ?? "SELECT 1;\n"
    }

    var currentResult: QueryResult? {
        results.indices.contains(selectedResult) ? results[selectedResult] : nil
    }

    /// Runs the selection if there is one, otherwise the statement at the cursor.
    func runCurrent() {
        let selection = editor.selectedRange
        let source = selection.length > 0 ? (text as NSString).substring(with: selection) : nil
        if let source {
            run(SQLStatements.statements(in: source))
        } else if let range = SQLStatements.range(at: selection.location, in: text) {
            let nsRange = NSRange(location: range.lowerBound, length: range.count)
            editor.flash(nsRange)
            run([(text as NSString).substring(with: nsRange)])
        }
    }

    func runAll() {
        run(SQLStatements.statements(in: text))
    }

    func cancel() {
        task?.cancel()
    }

    func close() {
        task?.cancel()
        connection?.close()
    }

    private func run(_ statements: [String]) {
        guard !isRunning, !statements.isEmpty else { return }
        isRunning = true
        failure = nil
        status = statements.count == 1 ? "Ejecutando…" : "Ejecutando \(statements.count) sentencias…"

        task = Task {
            defer { isRunning = false }
            let started = ContinuousClock.now
            var collected: [QueryResult] = []
            var index = 0
            do {
                let connection = try await liveConnection()
                for statement in statements {
                    collected += try await connection.query(statement, maxRows: Self.maxRows)
                    index += 1
                }
                show(collected)
                status = summary(of: collected) + " · " + format(ContinuousClock.now - started)
            } catch {
                show(collected)
                if Task.isCancelled || (error as? MySQLError)?.isQueryInterrupted == true {
                    status = "Consulta cancelada"
                } else {
                    status = nil
                    failure = Failure(statement: index + 1, total: statements.count, message: error.localizedDescription)
                }
            }
        }
    }

    private func liveConnection() async throws -> MySQLConnection {
        let connection: MySQLConnection
        if let existing = self.connection {
            connection = existing
        } else {
            connection = try await MySQLConnection.connect(options)
            self.connection = connection
            syncedDatabase = options.database
        }
        if let targetDatabase, targetDatabase != syncedDatabase {
            try await connection.selectDatabase(targetDatabase)
            syncedDatabase = targetDatabase
        }
        return connection
    }

    private func show(_ collected: [QueryResult]) {
        results = collected
        selectedResult = collected.lastIndex(where: \.hasResultSet) ?? max(collected.count - 1, 0)
    }

    private func summary(of results: [QueryResult]) -> String {
        guard let shown = currentResult else { return "Sin resultados" }
        if shown.hasResultSet {
            let rows = "\(shown.rows.count.formatted()) filas"
            return shown.isTruncated ? "\(rows) (límite de \(Self.maxRows.formatted()))" : rows
        }
        let affected = "\(shown.affectedRows.formatted()) filas afectadas"
        return shown.insertID > 0 ? "\(affected) · último ID \(shown.insertID)" : affected
    }
}

func format(_ duration: Duration) -> String {
    let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    return ms < 1000 ? "\(Int(ms.rounded())) ms" : String(format: "%.2f s", ms / 1000)
}
