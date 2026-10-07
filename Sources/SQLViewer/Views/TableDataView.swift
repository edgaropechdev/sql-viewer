import MySQLClient
import SwiftUI

struct TableDataView: View {
    @Bindable var model: TableDataModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            ZStack {
                if let result = model.result {
                    ResultGridView(
                        columns: result.columns,
                        rows: result.rows,
                        sort: gridSort(in: result),
                        onSort: { sort in
                            let name = result.columns[sort.column].originalName
                            Task { await model.setSort(.init(column: name, ascending: sort.ascending)) }
                        },
                        canEdit: { model.canEdit(column: $0) },
                        onEdit: { row, column, value in
                            Task { await model.update(row: row, column: column, to: value) }
                        }
                    )
                } else if model.isLoading {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            statusBar
        }
        .task {
            if model.result == nil { await model.load() }
        }
    }

    private func gridSort(in result: QueryResult) -> ResultGridView.Sort? {
        guard let sort = model.sort,
              let index = result.columns.firstIndex(where: { $0.originalName == sort.column }) else { return nil }
        return .init(column: index, ascending: sort.ascending)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Text("WHERE")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField("id > 100 AND status = 'active'", text: $model.filter)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { Task { await model.applyFilter() } }
            if !model.appliedFilter.isEmpty {
                Button("Quitar filtro", systemImage: "xmark.circle.fill") {
                    model.filter = ""
                    Task { await model.applyFilter() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        }
        .padding(8)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
                    .textSelection(.enabled)
            } else if let result = model.result {
                Text(rangeDescription(result))
                if let duration = model.lastDuration {
                    Text(format(duration)).foregroundStyle(.secondary)
                }
                if model.primaryKeyIndexes.isEmpty {
                    Label("Solo lectura: sin llave primaria", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button("Recargar", systemImage: "arrow.clockwise") { Task { await model.load() } }
                .keyboardShortcut("r")
            ControlGroup {
                Button("Anterior", systemImage: "chevron.left") { Task { await model.goToPage(model.page - 1) } }
                    .disabled(model.page == 0)
                Button("Siguiente", systemImage: "chevron.right") { Task { await model.goToPage(model.page + 1) } }
                    .disabled(!model.hasNextPage)
            }
            .frame(width: 70)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private func rangeDescription(_ result: QueryResult) -> String {
        guard !result.rows.isEmpty else { return model.page == 0 ? "Sin filas" : "Sin más filas" }
        let first = model.firstRowNumber
        return "Filas \(first.formatted())–\((first + result.rows.count - 1).formatted())"
    }
}
