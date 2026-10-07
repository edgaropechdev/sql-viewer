import Foundation
import Observation

/// The open connections of one window, shown as tabs.
///
/// Inactive sessions keep their models (selection, loaded page, editor text and
/// results) but nothing renders them; their sessions just sit idle. MySQLConnection
/// pings and reopens a session the server dropped meanwhile, so switching back
/// never needs an explicit reconnect.
@MainActor @Observable
final class SessionsModel {
    private(set) var sessions: [WorkspaceModel] = []
    /// nil shows the connection list, to start a new session.
    var activeID: WorkspaceModel.ID?

    var active: WorkspaceModel? {
        sessions.first { $0.id == activeID }
    }

    func add(_ session: WorkspaceModel) {
        sessions.append(session)
        activeID = session.id
    }

    /// The open session for a saved connection, if any.
    func session(for savedID: SavedConnection.ID) -> WorkspaceModel? {
        sessions.first { $0.saved.id == savedID }
    }

    func select(_ session: WorkspaceModel) {
        activeID = session.id
    }

    func showConnectionList() {
        activeID = nil
    }

    /// Selects the session at `offset` from the active one, wrapping around.
    func cycle(by offset: Int) {
        guard !sessions.isEmpty else { return }
        let current = sessions.firstIndex { $0.id == activeID } ?? 0
        let next = (current + offset % sessions.count + sessions.count) % sessions.count
        select(sessions[next])
    }

    func close(_ session: WorkspaceModel) {
        guard let index = sessions.firstIndex(where: { $0 === session }) else { return }
        session.close()
        sessions.remove(at: index)
        if activeID == session.id {
            // Like browser tabs: the neighbour takes over, else back to the list.
            activeID = sessions.indices.contains(index) ? sessions[index].id : sessions.last?.id
        }
    }

    func closeAll() {
        sessions.forEach { $0.close() }
        sessions.removeAll()
        activeID = nil
    }
}
