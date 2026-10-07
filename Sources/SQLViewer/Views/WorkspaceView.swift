import SwiftUI

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    let onDisconnect: () -> Void

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
        } detail: {
            detail
        }
        .navigationTitle(model.saved.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Vista", selection: $model.mode) {
                    Text("Datos").tag(WorkspaceModel.Mode.data)
                    Text("Estructura").tag(WorkspaceModel.Mode.structure)
                    Text("SQL").tag(WorkspaceModel.Mode.query)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            ToolbarItem {
                Button("Desconectar", systemImage: "eject", action: onDisconnect)
                    .help("Cerrar esta sesión")
            }
        }
        .alert("Error", isPresented: .constant(model.error != nil)) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    private var subtitle: String {
        [model.selectedDatabase, model.mode == .query ? nil : model.selectedTable]
            .compactMap(\.self)
            .joined(separator: " › ")
    }

    @ViewBuilder
    private var detail: some View {
        switch model.mode {
        case .query:
            QueryEditorView(model: model.editor)
        case .data:
            if let dataModel = model.dataModel {
                TableDataView(model: dataModel)
                    .id(ObjectIdentifier(dataModel))
            } else {
                noTable
            }
        case .structure:
            if let database = model.selectedDatabase, let table = model.selectedTable {
                StructureView(connection: model.connection, database: database, table: table)
                    .id("\(database).\(table)")
            } else {
                noTable
            }
        }
    }

    private var noTable: some View {
        ContentUnavailableView(
            model.selectedDatabase == nil ? "Elige una base de datos" : "Elige una tabla",
            systemImage: "tablecells",
            description: Text("O abre la pestaña SQL para escribir una consulta.")
        )
    }
}
