import Foundation
import Testing
@testable import MySQLClient

@Suite struct ConnectionURLTests {
    @Test func parsesStandardMySQLURL() throws {
        let uri = "mysql://root:secret@127.0.0.1:3306/mydb"
        let options = try ConnectionOptions.parse(uri: uri)
        #expect(options.host == "127.0.0.1")
        #expect(options.port == 3306)
        #expect(options.user == "root")
        #expect(options.password == "secret")
        #expect(options.database == "mydb")
        #expect(options.sslMode == .preferred)
    }

    @Test func parsesRemoteURLWithEncodedCharactersAndQueryParams() throws {
        let uri = "mysql://admin:p%40ss%23w0rd@db.remote.com:3307/app_prod?ssl-mode=REQUIRED&ssl-ca=%2Fetc%2Fssl%2Fca.pem&connect-timeout=25"
        let options = try ConnectionOptions.parse(uri: uri)
        #expect(options.host == "db.remote.com")
        #expect(options.port == 3307)
        #expect(options.user == "admin")
        #expect(options.password == "p@ss#w0rd")
        #expect(options.database == "app_prod")
        #expect(options.sslMode == .required)
        #expect(options.sslCAPath == "/etc/ssl/ca.pem")
        #expect(options.connectTimeout == 25)
    }

    @Test func parsesURLWithoutScheme() throws {
        let uri = "root:myPass@192.168.1.100:3306/staging"
        let options = try ConnectionOptions.parse(uri: uri)
        #expect(options.host == "192.168.1.100")
        #expect(options.port == 3306)
        #expect(options.user == "root")
        #expect(options.password == "myPass")
        #expect(options.database == "staging")
    }

    @Test func parsesMinimalURL() throws {
        let uri = "mysql://developer@remote-host"
        let options = try ConnectionOptions.parse(uri: uri)
        #expect(options.host == "remote-host")
        #expect(options.port == 3306)
        #expect(options.user == "developer")
        #expect(options.password == "")
        #expect(options.database == nil)
    }

    @Test func rejectsUnsupportedScheme() {
        let uri = "postgres://user:pass@localhost:5432/db"
        #expect(throws: ConnectionURLError.self) {
            try ConnectionOptions.parse(uri: uri)
        }
    }
}
