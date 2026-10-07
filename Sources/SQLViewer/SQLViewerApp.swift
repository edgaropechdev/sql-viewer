import AppKit
import SwiftUI

@main
struct SQLViewerApp: App {
    @State private var store = ConnectionStore()

    init() {
        // Needed when launched as a bare executable (`swift run`); a no-op inside the .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .windowToolbarStyle(.unified)
    }
}

struct RootView: View {
    @State private var sessions = SessionsModel()

    var body: some View {
        VStack(spacing: 0) {
            if !sessions.sessions.isEmpty {
                SessionTabBar(model: sessions)
                Divider()
            }
            if let active = sessions.active {
                // Fresh view state per session; what must survive lives in the model.
                WorkspaceView(model: active) { sessions.close(active) }
                    .id(active.id)
            } else {
                ConnectionListView(sessions: sessions)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onDisappear { sessions.closeAll() }
    }
}
