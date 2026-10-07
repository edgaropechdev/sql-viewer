import SwiftUI

/// One tab per open connection, plus "+" to open another from the list.
struct SessionTabBar: View {
    let model: SessionsModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                        SessionTab(
                            session: session,
                            isActive: model.activeID == session.id,
                            shortcut: index < 9 ? KeyEquivalent(Character("\(index + 1)")) : nil,
                            onSelect: { model.select(session) },
                            onClose: { model.close(session) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)

            Button("Nueva sesión", systemImage: "plus") { model.showConnectionList() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut("t")
                .help("Nueva sesión (⌘T)")
                .padding(.horizontal, 10)
        }
        .padding(.vertical, 5)
        .background(.bar)
        .background {
            // Safari-style tab cycling without visible controls.
            Group {
                Button("Sesión siguiente") { model.cycle(by: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Sesión anterior") { model.cycle(by: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            .hidden()
        }
    }
}

private struct SessionTab: View {
    let session: WorkspaceModel
    let isActive: Bool
    let shortcut: KeyEquivalent?
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    if session.editor.isRunning {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundStyle(.orange)
                    }
                    Text(session.saved.displayName)
                        .fontWeight(isActive ? .semibold : .regular)
                    if let database = session.selectedDatabase {
                        Text(database).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .modifier(OptionalShortcut(key: shortcut))

            Button("Cerrar sesión", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .imageScale(.small)
                .opacity(isActive || isHovering ? 1 : 0)
                .help("Cerrar sesión")
        }
        .font(.callout)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(isActive ? AnyShapeStyle(.selection.opacity(0.25)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .help(shortcut.map { "\(session.saved.summary) · ⌘\($0.character)" } ?? session.saved.summary)
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}
