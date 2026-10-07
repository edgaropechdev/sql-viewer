import CMySQL
import Foundation

public struct ConnectionOptions: Sendable, Hashable {
    public enum SSLMode: String, Sendable, Codable, CaseIterable {
        case disabled, preferred, required

        var cValue: UInt32 {
            switch self {
            case .disabled: SSL_MODE_DISABLED.rawValue
            case .preferred: SSL_MODE_PREFERRED.rawValue
            case .required: SSL_MODE_REQUIRED.rawValue
            }
        }
    }

    public var host: String
    public var port: UInt32
    public var user: String
    public var password: String
    public var database: String?
    public var sslMode: SSLMode
    public var sslCAPath: String?
    public var connectTimeout: UInt32

    public init(
        host: String,
        port: UInt32 = 3306,
        user: String,
        password: String = "",
        database: String? = nil,
        sslMode: SSLMode = .preferred,
        sslCAPath: String? = nil,
        connectTimeout: UInt32 = 10
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.database = database
        self.sslMode = sslMode
        self.sslCAPath = sslCAPath
        self.connectTimeout = connectTimeout
    }

    public static func parse(uri: String) throws -> ConnectionOptions {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ConnectionURLError.invalidURL
        }

        let normalized: String
        if trimmed.contains("://") {
            normalized = trimmed
        } else {
            normalized = "mysql://" + trimmed
        }

        guard let components = URLComponents(string: normalized) else {
            throw ConnectionURLError.invalidURL
        }

        if let scheme = components.scheme?.lowercased(), scheme != "mysql" && scheme != "mariadb" {
            throw ConnectionURLError.unsupportedScheme(scheme)
        }

        guard let host = components.host, !host.isEmpty else {
            throw ConnectionURLError.missingHost
        }

        let port = UInt32(components.port ?? 3306)
        let user = components.user?.removingPercentEncoding ?? "root"
        let password = components.password?.removingPercentEncoding ?? ""

        var database: String? = nil
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty {
            database = path.removingPercentEncoding ?? path
        }

        var sslMode: SSLMode = .preferred
        var sslCAPath: String? = nil
        var timeout: UInt32 = 10

        if let queryItems = components.queryItems {
            for item in queryItems {
                let name = item.name.lowercased()
                let value = item.value?.lowercased() ?? ""
                switch name {
                case "ssl-mode", "sslmode", "ssl_mode", "ssl":
                    if value == "disabled" || value == "false" || value == "0" {
                        sslMode = .disabled
                    } else if value == "required" || value == "true" || value == "1" {
                        sslMode = .required
                    } else if value == "preferred" {
                        sslMode = .preferred
                    }
                case "ssl-ca", "sslca", "ssl_ca":
                    if let rawValue = item.value, !rawValue.isEmpty {
                        sslCAPath = rawValue.removingPercentEncoding ?? rawValue
                    }
                case "connect-timeout", "connecttimeout", "timeout":
                    if let t = UInt32(value), t > 0 {
                        timeout = t
                    }
                default:
                    break
                }
            }
        }

        return ConnectionOptions(
            host: host,
            port: port,
            user: user,
            password: password,
            database: database,
            sslMode: sslMode,
            sslCAPath: sslCAPath,
            connectTimeout: timeout
        )
    }
}

public enum ConnectionURLError: LocalizedError, Sendable {
    case invalidURL
    case unsupportedScheme(String)
    case missingHost

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "La URL de conexión no es válida."
        case .unsupportedScheme(let scheme):
            "Esquema no soportado: '\(scheme)'. Se espera 'mysql://' o 'mariadb://'."
        case .missingHost:
            "La URL no especifica un host."
        }
    }
}

public struct MySQLError: LocalizedError, Sendable {
    public let code: UInt32
    public let sqlState: String
    public let message: String

    init(_ handle: UnsafeMutablePointer<MYSQL>) {
        code = mysql_errno(handle)
        sqlState = String(cString: mysql_sqlstate(handle))
        message = String(cString: mysql_error(handle))
    }

    init(message: String) {
        code = 0
        sqlState = ""
        self.message = message
    }

    /// ER_QUERY_INTERRUPTED: the query was stopped with `KILL QUERY`.
    public var isQueryInterrupted: Bool { code == 1317 }

    public var errorDescription: String? {
        code == 0 ? message : "\(message) (\(code))"
    }
}

public struct Column: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case numeric, text, temporal, json, bit, binary
    }

    public let name: String
    /// Underlying column name when `name` is an alias.
    public let originalName: String
    public let table: String
    public let kind: Kind
    public let isPrimaryKey: Bool
    public let isNullable: Bool

    init(_ field: MYSQL_FIELD) {
        name = String(cString: field.name)
        originalName = String(cString: field.org_name)
        table = String(cString: field.org_table)
        kind = Self.kind(of: field.type, charset: field.charsetnr)
        isPrimaryKey = field.flags & UInt32(PRI_KEY_FLAG) != 0
        isNullable = field.flags & UInt32(NOT_NULL_FLAG) == 0
    }

    private static let binaryCharset: UInt32 = 63

    private static func kind(of type: enum_field_types, charset: UInt32) -> Kind {
        switch type {
        case MYSQL_TYPE_DECIMAL, MYSQL_TYPE_NEWDECIMAL, MYSQL_TYPE_TINY, MYSQL_TYPE_SHORT,
             MYSQL_TYPE_LONG, MYSQL_TYPE_LONGLONG, MYSQL_TYPE_INT24, MYSQL_TYPE_FLOAT,
             MYSQL_TYPE_DOUBLE, MYSQL_TYPE_YEAR:
            .numeric
        case MYSQL_TYPE_DATE, MYSQL_TYPE_NEWDATE, MYSQL_TYPE_TIME, MYSQL_TYPE_TIME2,
             MYSQL_TYPE_DATETIME, MYSQL_TYPE_DATETIME2, MYSQL_TYPE_TIMESTAMP, MYSQL_TYPE_TIMESTAMP2:
            .temporal
        case MYSQL_TYPE_JSON:
            .json
        case MYSQL_TYPE_BIT:
            .bit
        case MYSQL_TYPE_GEOMETRY:
            .binary
        default:
            // Numeric and temporal types also report the binary charset, so this
            // check is only meaningful for string/blob types.
            charset == binaryCharset ? .binary : .text
        }
    }
}

public struct QueryResult: Sendable {
    public var columns: [Column]
    public var rows: [[String?]]
    /// True when the server returned more rows than the requested `maxRows`.
    public var isTruncated: Bool
    public var affectedRows: UInt64
    public var insertID: UInt64

    public var hasResultSet: Bool { !columns.isEmpty }

    init(columns: [Column], rows: [[String?]], isTruncated: Bool) {
        self.columns = columns
        self.rows = rows
        self.isTruncated = isTruncated
        affectedRows = UInt64(rows.count)
        insertID = 0
    }

    init(affectedRows: UInt64, insertID: UInt64) {
        columns = []
        rows = []
        isTruncated = false
        self.affectedRows = affectedRows
        self.insertID = insertID
    }
}

/// A piece of SQL built on the connection thread, so values are escaped with
/// the connection's charset and `sql_mode` (e.g. NO_BACKSLASH_ESCAPES).
public enum SQLPart: Sendable, ExpressibleByStringLiteral {
    case raw(String)
    case value(String?)

    public init(stringLiteral value: String) {
        self = .raw(value)
    }

    public static func identifier(_ name: String) -> SQLPart {
        .raw(quoteIdentifier(name))
    }
}

public func quoteIdentifier(_ name: String) -> String {
    "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
}
