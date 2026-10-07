import CMySQL
import Foundation
import Synchronization

/// One MySQL session. Calls are serialized on a dedicated thread; cancelling the
/// calling Task stops a running query with `KILL QUERY` from a side connection.
public final class MySQLConnection: @unchecked Sendable {
    public let options: ConnectionOptions
    public let serverVersion: String

    private let thread: ConnectionThread
    private let session = Mutex(SessionState())
    private let isClosed = Mutex(false)

    // Only touched on `thread`.
    private var handle: UnsafeMutablePointer<MYSQL>?
    private var currentDatabase: String?
    private var lastActivity = ContinuousClock.now

    private struct SessionState {
        var serverThreadID: UInt = 0
        var runningQuery: UInt64?
        var nextQueryToken: UInt64 = 0
    }

    /// `mysql_library_init` is not thread-safe, so it must run once before any
    /// connection thread calls `mysql_init`. Static lets are initialized once.
    private static let isLibraryInitialized: Bool = mysql_server_init(0, nil, nil) == 0

    /// Idle time after which the session is pinged (and reopened if the server
    /// dropped it) before running the next statement.
    private static let idlePingInterval: Duration = .seconds(30)

    private init(options: ConnectionOptions, thread: ConnectionThread, serverVersion: String) {
        self.options = options
        self.thread = thread
        self.serverVersion = serverVersion
        currentDatabase = options.database
    }

    public static func connect(_ options: ConnectionOptions) async throws -> MySQLConnection {
        guard isLibraryInitialized else {
            throw MySQLError(message: "No se pudo inicializar libmysqlclient")
        }
        let thread = ConnectionThread(name: "MySQL \(options.host):\(options.port)")
        let opened = try await thread.run { () throws -> OpenedHandle in
            try OpenedHandle(options: options, database: options.database)
        }
        let connection = MySQLConnection(options: options, thread: thread, serverVersion: opened.serverVersion)
        // Hand the handle over on the owning thread.
        try await thread.run { connection.adopt(opened) }
        return connection
    }

    // MARK: - Public API

    public func query(_ sql: String, maxRows: Int = 10_000) async throws -> [QueryResult] {
        try await perform(maxRows: maxRows) { _ in sql }
    }

    public func execute(_ parts: [SQLPart], maxRows: Int = 10_000) async throws -> [QueryResult] {
        try await perform(maxRows: maxRows) { handle in
            try parts.map { part in
                switch part {
                case .raw(let sql): sql
                case .value(nil): "NULL"
                case .value(let value?): "'" + (try Self.escape(value, on: handle)) + "'"
                }
            }.joined()
        }
    }

    public func selectDatabase(_ name: String) async throws {
        try await thread.run {
            let handle = try self.liveHandle()
            defer { self.lastActivity = .now }
            guard mysql_select_db(handle, name) == 0 else { throw MySQLError(handle) }
            self.currentDatabase = name
        }
    }

    public func close() {
        guard markClosed() else { return }
        thread.submit { self.closeHandle() }
        thread.stop()
    }

    deinit {
        guard markClosed() else { return }
        // No job can still reference `self` here, so reading `handle` is safe.
        nonisolated(unsafe) let handle = handle
        thread.submit { if let handle { mysql_close(handle) } }
        thread.stop()
    }

    // MARK: - Execution

    private func perform(
        maxRows: Int,
        buildSQL: @escaping @Sendable (UnsafeMutablePointer<MYSQL>) throws -> String
    ) async throws -> [QueryResult] {
        try Task.checkCancellation()
        let token = session.withLock { state in
            state.nextQueryToken += 1
            return state.nextQueryToken
        }
        return try await withTaskCancellationHandler {
            try await thread.run {
                let handle = try self.liveHandle()
                defer { self.lastActivity = .now }
                let sql = try buildSQL(handle)
                self.session.withLock { $0.runningQuery = token }
                defer { self.session.withLock { $0.runningQuery = nil } }
                return try Self.run(sql, on: handle, maxRows: maxRows)
            }
        } onCancel: {
            Task { await self.killQuery(token: token) }
        }
    }

    private static func run(_ sql: String, on handle: UnsafeMutablePointer<MYSQL>, maxRows: Int) throws -> [QueryResult] {
        let status = sql.withCString { mysql_real_query(handle, $0, UInt(sql.utf8.count)) }
        guard status == 0 else { throw MySQLError(handle) }

        // A single statement can still yield several results (e.g. CALL).
        var results: [QueryResult] = []
        while true {
            if let resultSet = mysql_use_result(handle) {
                results.append(try readResultSet(resultSet, on: handle, maxRows: maxRows))
            } else if mysql_field_count(handle) == 0 {
                results.append(QueryResult(affectedRows: mysql_affected_rows(handle), insertID: mysql_insert_id(handle)))
            } else {
                throw MySQLError(handle)
            }
            let next = mysql_next_result(handle)
            if next == -1 { break }
            if next > 0 { throw MySQLError(handle) }
        }
        return results
    }

    private static func readResultSet(
        _ resultSet: UnsafeMutablePointer<MYSQL_RES>,
        on handle: UnsafeMutablePointer<MYSQL>,
        maxRows: Int
    ) throws -> QueryResult {
        // With mysql_use_result, freeing drains any rows we didn't read.
        defer { mysql_free_result(resultSet) }

        let fieldCount = Int(mysql_num_fields(resultSet))
        let fields = mysql_fetch_fields(resultSet)!
        let columns = (0..<fieldCount).map { Column(fields[$0]) }

        var rows: [[String?]] = []
        var isTruncated = false
        while let row = mysql_fetch_row(resultSet) {
            if rows.count == maxRows {
                isTruncated = true
                break
            }
            let lengths = mysql_fetch_lengths(resultSet)!
            rows.append((0..<fieldCount).map { index in
                guard let value = row[index] else { return nil }
                let bytes = UnsafeRawBufferPointer(start: value, count: Int(lengths[index]))
                return decode(bytes, as: columns[index].kind)
            })
        }
        if !isTruncated, mysql_errno(handle) != 0 {
            throw MySQLError(handle)
        }
        return QueryResult(columns: columns, rows: rows, isTruncated: isTruncated)
    }

    private static let binaryPreviewLength = 64

    private static func decode(_ bytes: UnsafeRawBufferPointer, as kind: Column.Kind) -> String {
        switch kind {
        case .binary:
            let hex = bytes.prefix(binaryPreviewLength).map { String(format: "%02X", $0) }.joined()
            return bytes.count > binaryPreviewLength ? "0x\(hex)… (\(bytes.count) bytes)" : "0x\(hex)"
        case .bit:
            return String(bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        default:
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    private static func escape(_ value: String, on handle: UnsafeMutablePointer<MYSQL>) throws -> String {
        let source = Array(value.utf8CString)  // NUL-terminated
        let length = source.count - 1
        var escaped = [CChar](repeating: 0, count: length * 2 + 1)
        let written = mysql_real_escape_string_quote(handle, &escaped, source, UInt(length), CChar(UInt8(ascii: "'")))
        guard written != UInt.max else { throw MySQLError(handle) }
        return escaped.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    // MARK: - Cancellation

    private func killQuery(token: UInt64) async {
        let threadID = session.withLock { $0.runningQuery == token ? $0.serverThreadID : nil }
        guard let threadID else { return }
        var killerOptions = options
        killerOptions.database = nil
        guard let killer = try? await MySQLConnection.connect(killerOptions) else { return }
        _ = try? await killer.query("KILL QUERY \(threadID)")
        killer.close()
    }

    // MARK: - Handle lifecycle (connection thread only)

    /// Returns the handle, transparently reopening a session the server dropped
    /// while idle (wait_timeout, network change). Never retries a statement.
    private func liveHandle() throws -> UnsafeMutablePointer<MYSQL> {
        guard let handle else { throw MySQLError(message: "La conexión está cerrada") }
        guard ContinuousClock.now - lastActivity > Self.idlePingInterval else { return handle }
        if mysql_ping(handle) == 0 { return handle }
        mysql_close(handle)
        self.handle = nil
        adopt(try OpenedHandle(options: options, database: currentDatabase))
        return self.handle!
    }

    private func adopt(_ opened: OpenedHandle) {
        handle = opened.handle
        lastActivity = .now
        session.withLock { $0.serverThreadID = opened.serverThreadID }
    }

    private func closeHandle() {
        if let handle { mysql_close(handle) }
        handle = nil
    }

    private func markClosed() -> Bool {
        isClosed.withLock { closed in
            defer { closed = true }
            return !closed
        }
    }
}

/// A freshly connected handle. Only crosses threads while ownership moves from
/// the connect job to the connection; it is never used concurrently.
private struct OpenedHandle: @unchecked Sendable {
    let handle: UnsafeMutablePointer<MYSQL>
    let serverVersion: String
    let serverThreadID: UInt

    init(options: ConnectionOptions, database: String?) throws {
        guard let handle = mysql_init(nil) else {
            throw MySQLError(message: "mysql_init falló")
        }
        var timeout = options.connectTimeout
        mysql_options(handle, MYSQL_OPT_CONNECT_TIMEOUT, &timeout)
        var sslMode = options.sslMode.cValue
        mysql_options(handle, MYSQL_OPT_SSL_MODE, &sslMode)
        if let caPath = options.sslCAPath, !caPath.isEmpty {
            _ = caPath.withCString { mysql_options(handle, MYSQL_OPT_SSL_CA, $0) }
        }
        _ = "utf8mb4".withCString { mysql_options(handle, MYSQL_SET_CHARSET_NAME, $0) }

        let connected = mysql_real_connect(
            handle, options.host, options.user, options.password, database,
            options.port, nil, UInt(CLIENT_MULTI_STATEMENTS)
        )
        guard connected != nil else {
            let error = MySQLError(handle)
            mysql_close(handle)
            throw error
        }
        self.handle = handle
        serverVersion = String(cString: mysql_get_server_info(handle))
        serverThreadID = mysql_thread_id(handle)
    }
}
