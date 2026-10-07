import Foundation
import MySQLClient

struct SavedConnection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var host = "127.0.0.1"
    var port = 3306
    var user = "root"
    /// Database selected on connect; empty means none.
    var database = ""
    var sslMode: ConnectionOptions.SSLMode = .preferred
    var sslCAPath = ""
    var connectTimeout = 10

    var displayName: String { name.isEmpty ? host : name }
    var summary: String { "\(user)@\(host):\(port)" }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, user, database, sslMode, sslCAPath, connectTimeout
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "127.0.0.1",
        port: Int = 3306,
        user: String = "root",
        database: String = "",
        sslMode: ConnectionOptions.SSLMode = .preferred,
        sslCAPath: String = "",
        connectTimeout: Int = 10
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.database = database
        self.sslMode = sslMode
        self.sslCAPath = sslCAPath
        self.connectTimeout = connectTimeout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 3306
        user = try container.decodeIfPresent(String.self, forKey: .user) ?? "root"
        database = try container.decodeIfPresent(String.self, forKey: .database) ?? ""
        sslMode = try container.decodeIfPresent(ConnectionOptions.SSLMode.self, forKey: .sslMode) ?? .preferred
        sslCAPath = try container.decodeIfPresent(String.self, forKey: .sslCAPath) ?? ""
        connectTimeout = try container.decodeIfPresent(Int.self, forKey: .connectTimeout) ?? 10
    }

    func options(password: String) -> ConnectionOptions {
        ConnectionOptions(
            host: host,
            port: UInt32(clamping: port),
            user: user,
            password: password,
            database: database.isEmpty ? nil : database,
            sslMode: sslMode,
            sslCAPath: sslCAPath.isEmpty ? nil : sslCAPath,
            connectTimeout: UInt32(clamping: max(1, connectTimeout))
        )
    }

    static func from(url: String) throws -> (connection: SavedConnection, password: String) {
        let options = try ConnectionOptions.parse(uri: url)
        let connection = SavedConnection(
            name: options.database ?? options.host,
            host: options.host,
            port: Int(options.port),
            user: options.user,
            database: options.database ?? "",
            sslMode: options.sslMode,
            sslCAPath: options.sslCAPath ?? "",
            connectTimeout: Int(options.connectTimeout)
        )
        return (connection, options.password)
    }
}
