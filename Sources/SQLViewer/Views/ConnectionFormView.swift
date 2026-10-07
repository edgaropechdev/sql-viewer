import AppKit
import MySQLClient
import SwiftUI

struct ConnectionFormView: View {
    @Environment(ConnectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var connection: SavedConnection
    @State private var password: String
    @State private var shouldSave: Bool
    @State private var testState: TestState = .idle
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showingURLSheet = false
    @State private var urlInput = ""
    private let isNew: Bool
    private let onConnect: ((WorkspaceModel) -> Void)?

    private enum TestState {
        case idle, testing
        case success(String)
        case failure(String)
    }

    init(connection: SavedConnection, isNew: Bool, onConnect: ((WorkspaceModel) -> Void)? = nil) {
        _connection = State(initialValue: connection)
        _password = State(initialValue: isNew ? "" : Keychain.password(for: connection.id) ?? "")
        _shouldSave = State(initialValue: true)
        self.isNew = isNew
        self.onConnect = onConnect
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                HStack {
                    TextField("Nombre", text: $connection.name, prompt: Text(connection.host))
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Importar URL", systemImage: "link")
                    }
                    .buttonStyle(.borderless)
                    .help("Importar desde cadena de conexión (mysql://...)")
                }

                Section("Servidor") {
                    TextField("Host", text: $connection.host)
                    TextField("Puerto", value: $connection.port, format: .number.grouping(.never))
                    TextField("Usuario", text: $connection.user)
                    SecureField("Contraseña", text: $password)
                    TextField("Base de datos", text: $connection.database, prompt: Text("Opcional"))
                }

                Section {
                    Picker("Modo SSL", selection: $connection.sslMode) {
                        Text("Desactivado").tag(ConnectionOptions.SSLMode.disabled)
                        Text("Preferido").tag(ConnectionOptions.SSLMode.preferred)
                        Text("Requerido").tag(ConnectionOptions.SSLMode.required)
                    }

                    HStack {
                        TextField("Certificado CA (SSL)", text: $connection.sslCAPath, prompt: Text("Opcional (.pem / .crt)"))
                        Button("Examinar…") { chooseCACertificate() }
                    }

                    Stepper("Timeout de conexión: \(connection.connectTimeout) s", value: $connection.connectTimeout, in: 2...120)
                } header: {
                    Text("Seguridad & Red")
                } footer: {
                    Text("\"localhost\" usa el socket Unix; 127.0.0.1 o IPs remotas usan TCP.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Guardar en mis conexiones", isOn: $shouldSave)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 8) {
                testStatus
                Spacer()

                Button("Probar") { test() }
                    .disabled(isTesting || isConnecting)

                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isConnecting)

                if shouldSave {
                    Button("Guardar") { save() }
                        .disabled(connection.host.isEmpty || connection.user.isEmpty || isConnecting)
                }

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 4)
                    } else {
                        Text("Conectar")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(connection.host.isEmpty || connection.user.isEmpty || isConnecting)
            }
            .padding()
        }
        .frame(width: 500)
        .navigationTitle(isNew ? "Nueva conexión" : "Editar conexión")
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingURLSheet) {
            VStack(spacing: 16) {
                Text("Importar cadena de conexión")
                    .font(.headline)
                Text("Pega una URL MySQL con formato:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("mysql://usuario:clave@servidor:3306/basededatos?ssl-mode=REQUIRED")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                TextField("mysql://...", text: $urlInput)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Cancelar", role: .cancel) {
                        showingURLSheet = false
                        urlInput = ""
                    }
                    Button("Importar") {
                        applyURL(urlInput)
                        showingURLSheet = false
                        urlInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 480)
        }
    }

    private var isTesting: Bool {
        if case .testing = testState { true } else { false }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success(let version):
            Label("MySQL \(version)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(message)
        }
    }

    private func chooseCACertificate() {
        let panel = NSOpenPanel()
        panel.title = "Seleccionar certificado CA"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            connection.sslCAPath = url.path
        }
    }

    private func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("mysql://") || trimmed.hasPrefix("mariadb://") {
                applyURL(trimmed)
                return
            }
        }
        urlInput = ""
        showingURLSheet = true
    }

    private func applyURL(_ urlString: String) {
        do {
            let (imported, pass) = try SavedConnection.from(url: urlString)
            connection.host = imported.host
            connection.port = imported.port
            connection.user = imported.user
            connection.database = imported.database
            connection.sslMode = imported.sslMode
            if !imported.sslCAPath.isEmpty {
                connection.sslCAPath = imported.sslCAPath
            }
            if imported.connectTimeout > 0 {
                connection.connectTimeout = imported.connectTimeout
            }
            if connection.name.isEmpty || isNew {
                connection.name = imported.name
            }
            password = pass
            testState = .idle
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func test() {
        testState = .testing
        let options = connection.options(password: password)
        Task {
            do {
                let probe = try await MySQLConnection.connect(options)
                probe.close()
                testState = .success(probe.serverVersion)
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }

    private func save() {
        do {
            try store.save(connection, password: password)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        testState = .idle
        let currentConnection = connection
        let currentPassword = password
        let mustSave = shouldSave

        Task {
            do {
                if mustSave {
                    try store.save(currentConnection, password: currentPassword)
                }
                let model = try await WorkspaceModel.open(connection: currentConnection, password: currentPassword)
                await MainActor.run {
                    isConnecting = false
                    dismiss()
                    onConnect?(model)
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
