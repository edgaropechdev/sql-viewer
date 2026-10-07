import SwiftUI

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    let sessions: SessionsModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 400)
        } detail: {
            VStack(spacing: 0) {
                SessionTabBar(model: sessions)
                Divider()
                // Fill the column: an empty-state view is only as tall as its
                // text, and would otherwise pull the tabs to the middle.
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
                Button("Desconectar", systemImage: "eject") { sessions.close(model) }
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
        [model.selectedDatabase, model.mode == .query ? nil : model.selectedTable ?? model.selectedRoutine?.name]
            .compactMap(\.self)
            .joined(separator: " › ")
    }

    @ViewBuilder
    private var detail: some View {
        if model.mode != .query, let database = model.selectedDatabase, let routine = model.selectedRoutine {
            RoutineView(connection: model.connection, database: database, routine: routine)
                .id(routine)
        } else {
            modeDetail
        }
    }

    @ViewBuilder
    private var modeDetail: some View {
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
