import AppKit
import MySQLClient
import SwiftUI

struct RoutineView: View {
    let connection: MySQLConnection
    let database: String
    let routine: RoutineRef

    private enum Section: Hashable {
        case definition, parameters
    }

    @State private var section: Section = .definition
    @State private var detail: RoutineDetail?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Sección", selection: $section) {
                    Text("Definición").tag(Section.definition)
                    Text("Parámetros").tag(Section.parameters)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                Spacer()

                Button("Copiar definición", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(detail?.definition ?? "", forType: .string)
                }
                .disabled(detail?.definition == nil)
            }
            .padding(8)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let detail {
                Divider()
                footer(detail)
            }
        }
        .task {
            do {
                detail = try await RoutineDetail.load(connection: connection, database: database, routine: routine)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            ContentUnavailableView(routine.kind == .procedure ? "No se pudo leer el procedimiento" : "No se pudo leer la función", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let detail {
            switch section {
            case .definition:
                if let definition = detail.definition {
                    SQLTextView(text: .constant(definition), isEditable: false)
                } else {
                    ContentUnavailableView(
                        "Definición no disponible",
                        systemImage: "lock",
                        description: Text("El servidor solo la muestra al definer (\(detail.definer)) o a usuarios con el privilegio SHOW_ROUTINE.")
                    )
                }
            case .parameters:
                if let parameters = detail.parameters, !parameters.rows.isEmpty {
                    ResultGridView(columns: parameters.columns, rows: parameters.rows)
                } else {
                    ContentUnavailableView("Sin parámetros", systemImage: "list.bullet")
                }
            }
        } else {
            ProgressView()
        }
    }

    private func footer(_ detail: RoutineDetail) -> some View {
        HStack {
            Text([
                detail.returns.map { "Devuelve \($0)" },
                "Definer: \(detail.definer)",
                "SQL SECURITY \(detail.securityType)",
                "Modificado: \(detail.lastAltered)",
                detail.comment.isEmpty ? nil : detail.comment,
            ].compactMap(\.self).joined(separator: " · "))
            .lineLimit(1)
            .truncationMode(.tail)
            .textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
