import Foundation
import MySQLClient
import Testing
@testable import SQLViewer

/// Same opt-in as MySQLClientTests: SQLVIEWER_TEST_MYSQL=1 swift test
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SQLVIEWER_TEST_MYSQL"] == "1"))
@MainActor
struct SessionsModelTests {
    func openSessions(_ count: Int) async throws -> SessionsModel {
        let model = SessionsModel()
        for index in 0..<count {
            let saved = SavedConnection(name: "s\(index)", host: "localhost", user: "root")
            model.add(try await WorkspaceModel.open(connection: saved, password: ""))
        }
        return model
    }

    @Test func addingSelectsTheNewSession() async throws {
        let model = try await openSessions(2)
        defer { model.closeAll() }
        #expect(model.active === model.sessions[1])
        model.showConnectionList()
        #expect(model.active == nil)
        #expect(model.sessions.count == 2)
    }

    @Test func closingActiveSelectsNeighbour() async throws {
        let model = try await openSessions(3)
        defer { model.closeAll() }
        let (first, middle, last) = (model.sessions[0], model.sessions[1], model.sessions[2])

        model.select(middle)
        model.close(middle)
        #expect(model.active === last)

        model.close(last)
        #expect(model.active === first)

        model.close(first)
        #expect(model.active == nil)
        #expect(model.sessions.isEmpty)
    }

    @Test func closingInactiveKeepsSelection() async throws {
        let model = try await openSessions(2)
        defer { model.closeAll() }
        let (first, second) = (model.sessions[0], model.sessions[1])
        model.close(first)
        #expect(model.active === second)
    }

    @Test func cycleWraps() async throws {
        let model = try await openSessions(3)
        defer { model.closeAll() }
        model.cycle(by: 1)
        #expect(model.active === model.sessions[0])
        model.cycle(by: -1)
        #expect(model.active === model.sessions[2])
    }

    /// Background sessions stay usable: switching away and back doesn't close them.
    @Test func inactiveSessionStillQueries() async throws {
        let model = try await openSessions(2)
        defer { model.closeAll() }
        let first = model.sessions[0]
        model.select(model.sessions[1])
        model.select(first)
        let result = try await first.connection.query("SELECT 1").first
        #expect(result?.rows == [["1"]])
    }
}
