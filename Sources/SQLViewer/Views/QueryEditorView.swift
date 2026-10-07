import MySQLClient
import SwiftUI

struct QueryEditorView: View {
    @Bindable var model: QueryEditorModel

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                actionBar
                Divider()
                SQLTextView(text: $model.text, controller: model.editor)
            }
            .frame(minHeight: 120, idealHeight: 260)

            VStack(spacing: 0) {
                if model.results.count > 1 {
                    resultPicker
                    Divider()
                }
                results
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar
            }
            .frame(minHeight: 160)
        }
        .onAppear { model.editor.focus() }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Ejecutar", systemImage: "play.fill") { model.runCurrent() }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Ejecuta la selección o la sentencia bajo el cursor (⌘↩)")
                .disabled(model.isRunning)
            Button("Ejecutar todo", systemImage: "forward.fill") { model.runAll() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help("Ejecuta todas las sentencias (⇧⌘↩)")
                .disabled(model.isRunning)
            Button("Cancelar", systemImage: "stop.fill") { model.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .help("Detiene la consulta en curso (⌘.)")
                .disabled(!model.isRunning)
            Spacer()
            if model.isRunning {
                ProgressView().controlSize(.small)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var resultPicker: some View {
        Picker("Resultado", selection: $model.selectedResult) {
            ForEach(model.results.indices, id: \.self) { index in
                Text("Resultado \(index + 1)").tag(index)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(6)
    }

    @ViewBuilder
    private var results: some View {
        if let result = model.currentResult {
            if result.hasResultSet {
                ResultGridView(columns: result.columns, rows: result.rows)
            } else {
                ContentUnavailableView(
                    "\(result.affectedRows.formatted()) filas afectadas",
                    systemImage: "checkmark.circle"
                )
            }
        } else {
            Color.clear
        }
    }

    private var statusBar: some View {
        HStack {
            if let failure = model.failure {
                Label(
                    failure.total > 1 ? "Sentencia \(failure.statement) de \(failure.total): \(failure.message)" : failure.message,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .lineLimit(2)
                .help(failure.message)
            } else if let status = model.status {
                Text(status)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
    }
}
