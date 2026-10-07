import MySQLClient
import SwiftUI

struct StructureView: View {
    let connection: MySQLConnection
    let database: String
    let table: String

    private enum Section: Hashable {
        case columns, indexes, ddl
    }

    @State private var section: Section = .columns
    @State private var columns: QueryResult?
    @State private var indexes: QueryResult?
    @State private var ddl = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: $section) {
                Text("Columnas").tag(Section.columns)
                Text("Índices").tag(Section.indexes)
                Text("DDL").tag(Section.ddl)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 300)
            .padding(8)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            ContentUnavailableView("No se pudo leer la estructura", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            switch section {
            case .columns: grid(columns)
            case .indexes: grid(indexes)
            case .ddl:
                ScrollView {
                    Text(ddl)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func grid(_ result: QueryResult?) -> some View {
        if let result {
            ResultGridView(columns: result.columns, rows: result.rows)
        } else {
            ProgressView()
        }
    }

    private func load() async {
        let target: [SQLPart] = [.identifier(database), ".", .identifier(table)]
        do {
            columns = try await connection.execute(["SHOW FULL COLUMNS FROM "] + target).first
            indexes = try await connection.execute(["SHOW INDEX FROM "] + target).first
            // Column 1 holds "Create Table" or "Create View".
            ddl = try await connection.execute(["SHOW CREATE TABLE "] + target).first?.rows.first?[1] ?? ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
