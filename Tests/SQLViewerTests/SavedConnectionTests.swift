import Foundation
import Testing
@testable import SQLViewer

@Suite struct SavedConnectionTests {
    @Test func decodesLegacyJSONWithoutNewFields() throws {
        let legacyJSON = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "name": "Local Test",
            "host": "127.0.0.1",
            "port": 3306,
            "user": "root",
            "database": "classicmodels",
            "sslMode": "preferred"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SavedConnection.self, from: legacyJSON)
        #expect(decoded.name == "Local Test")
        #expect(decoded.host == "127.0.0.1")
        #expect(decoded.sslCAPath == "")
        #expect(decoded.connectTimeout == 10)
    }

    @Test func createsSavedConnectionFromURL() throws {
        let url = "mysql://myuser:mypass@db.example.com:3307/my_remote_db?ssl-mode=REQUIRED&connect-timeout=15"
        let (conn, password) = try SavedConnection.from(url: url)

        #expect(conn.host == "db.example.com")
        #expect(conn.port == 3307)
        #expect(conn.user == "myuser")
        #expect(password == "mypass")
        #expect(conn.database == "my_remote_db")
        #expect(conn.connectTimeout == 15)
        #expect(conn.sslMode == .required)
    }
}
