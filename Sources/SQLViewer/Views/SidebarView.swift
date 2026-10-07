import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var model: WorkspaceModel
    @State private var search = ""

    var body: some View {
        // Picker and filter sit above the list, not in a safe-area inset or a
        // system search bar, so nothing overlaps the scrolled table names.
        VStack(spacing: 0) {
            header
            tableList
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            databaseRow
            filterField
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var databaseRow: some View {
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
    }

    private var filterField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filtrar tablas", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button("Limpiar filtro", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary, in: .rect(cornerRadius: 7))
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
