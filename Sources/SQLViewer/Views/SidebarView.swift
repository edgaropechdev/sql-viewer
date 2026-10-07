import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: WorkspaceModel
    @State private var search = ""

    var body: some View {
        // The picker sits above the list rather than in a safe-area inset, so
        // scrolled table names never show through behind it.
        VStack(spacing: 0) {
            databaseBar
            tableList
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Filtrar tablas")
    }

    private var databaseBar: some View {
        HStack {
            Picker("Base de datos", selection: databaseBinding) {
                Text("Elegir base de datos…").tag(String?.none)
                ForEach(model.databases, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .labelsHidden()

            Button("Recargar", systemImage: "arrow.clockwise") {
                Task {
                    await model.reloadDatabases()
                    await model.reloadTables()
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Recargar bases de datos y tablas")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var tableList: some View {
        List(selection: $model.selectedTable) {
            Section(model.selectedDatabase == nil ? "" : "Tablas (\(filtered.count))") {
                ForEach(filtered) { table in
                    Label(table.name, systemImage: table.isView ? "eye" : "tablecells")
                        .tag(table.name)
                        .contextMenu {
                            Button("Copiar nombre") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(table.name, forType: .string)
                            }
                            Button("Ver estructura") {
                                model.selectedTable = table.name
                                model.mode = .structure
                            }
                        }
                }
            }
        }
        .overlay {
            if model.isLoadingTables, model.tables.isEmpty {
                ProgressView()
            }
        }
    }

    private var filtered: [TableEntry] {
        search.isEmpty ? model.tables : model.tables.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var databaseBinding: Binding<String?> {
        Binding(
            get: { model.selectedDatabase },
            set: { name in
                guard let name else { return }
                Task { await model.selectDatabase(name) }
            }
        )
    }
}
