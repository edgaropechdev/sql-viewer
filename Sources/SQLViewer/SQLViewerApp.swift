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
        Group {
            if let active = sessions.active {
                // The split view must sit at the top of the window: macOS 26
                // draws the toolbar's scroll-edge blur over its top, so anything
                // stacked above it pushed that blur onto the content. The tabs
                // go inside the detail column instead.
                WorkspaceView(model: active, sessions: sessions)
                    .id(active.id)  // Fresh view state per session; what must survive lives in the model.
            } else {
                VStack(spacing: 0) {
                    if !sessions.sessions.isEmpty {
                        SessionTabBar(model: sessions)
                        Divider()
                    }
                    ConnectionListView(sessions: sessions)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onDisappear { sessions.closeAll() }
    }
}
