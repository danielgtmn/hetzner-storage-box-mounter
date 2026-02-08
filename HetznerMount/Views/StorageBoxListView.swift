import SwiftUI
import ServiceManagement
import HetznerMountKit

struct StorageBoxListView: View {
    @StateObject private var domainManager = DomainManager.shared
    @State private var selectedID: UUID?
    @State private var configs: [StorageBoxConfig] = []
    @State private var draftConfig: StorageBoxConfig?

    private let store = StorageBoxConfigStore()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(configs) { config in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(config.effectiveDisplayName)
                                .font(.headline)
                            Text(config.host)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if let box = domainManager.boxes.first(where: { $0.id == config.id }),
                           box.isMounted {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .tag(config.id)
                }
            }
            .frame(minWidth: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addBox) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: selectedID) { _, newValue in
                if newValue != nil {
                    draftConfig = nil
                }
            }
        } detail: {
            if draftConfig != nil {
                StorageBoxDetailView(
                    config: Binding(
                        get: { draftConfig ?? StorageBoxConfig() },
                        set: { draftConfig = $0 }
                    ),
                    isNew: true,
                    onSave: { saveDraft() },
                    onDelete: { draftConfig = nil }
                )
                .id("draft")
            } else if let id = selectedID, configs.contains(where: { $0.id == id }) {
                StorageBoxDetailView(
                    config: bindingForConfig(id: id),
                    isNew: false,
                    onSave: { saveConfigByID(id) },
                    onDelete: { deleteBox(id: id) }
                )
                .id(id)
            } else {
                Text("Select or add a Storage Box")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 650, minHeight: 400)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .addStorageBox)) { _ in
            addBox()
        }
    }

    private func reload() {
        configs = store.loadAll()
        if selectedID == nil && draftConfig == nil {
            selectedID = configs.first?.id
        }
    }

    private func addBox() {
        selectedID = nil
        draftConfig = StorageBoxConfig()
    }

    private func saveDraft() {
        guard let draft = draftConfig else { return }
        store.add(draft)
        draftConfig = nil
        configs = store.loadAll()
        selectedID = draft.id
        Task { await domainManager.refreshAll() }
    }

    private func deleteBox(id: UUID) {
        Task {
            await domainManager.removeBox(configID: id)
            configs = store.loadAll()
            selectedID = configs.first?.id
        }
    }

    private func bindingForConfig(id: UUID) -> Binding<StorageBoxConfig> {
        Binding(
            get: { configs.first(where: { $0.id == id }) ?? StorageBoxConfig(id: id) },
            set: { newValue in
                if let i = configs.firstIndex(where: { $0.id == id }) {
                    configs[i] = newValue
                }
            }
        )
    }

    private func saveConfigByID(_ id: UUID) {
        guard let config = configs.first(where: { $0.id == id }) else { return }
        store.update(config)
        configs = store.loadAll()
        Task {
            await domainManager.refreshAll()
            await domainManager.remount(configID: id)
        }
    }
}

struct StorageBoxDetailView: View {
    @Binding var config: StorageBoxConfig
    var isNew: Bool
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var password = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    @State private var connectionTestSuccess = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showDeleteAlert = false

    private let keychainManager = KeychainManager()

    var body: some View {
        Form {
            Section("Display") {
                TextField("Name", text: $config.displayName)
                    .help("Friendly name shown in the menu bar and Finder")
            }

            Section("Connection") {
                TextField("Username", text: $config.username)
                    .textContentType(.username)
                    .onChange(of: config.username) { _, newValue in
                        if config.host.isEmpty || config.host.hasSuffix(".your-storagebox.de") {
                            config.host = "\(newValue).your-storagebox.de"
                        }
                    }
                TextField("Host", text: $config.host)
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $config.port, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Base Path", text: $config.basePath)
                    .help("Root directory on the storage box, e.g. /")
            }

            Section("Authentication") {
                Picker("Method", selection: $config.authMethod) {
                    Text("Password").tag(AuthMethod.password)
                    Text("SSH Key").tag(AuthMethod.sshKey)
                }
                .pickerStyle(.segmented)

                if config.authMethod == .password {
                    SecureField("Password", text: $password)
                } else {
                    Text("SSH Key auth will be available in a future version.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(!config.isValid || isTestingConnection)

                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let result = connectionTestResult {
                        Image(systemName: connectionTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(connectionTestSuccess ? .green : .red)
                        Text(result)
                            .font(.caption)
                            .foregroundColor(connectionTestSuccess ? .green : .red)
                    }

                    Spacer()

                    if isNew {
                        Button("Cancel") {
                            onDelete()
                        }
                    } else {
                        Button("Delete", role: .destructive) {
                            showDeleteAlert = true
                        }
                    }
                }

                Button(isNew ? "Add" : "Save") {
                    save()
                }
                .disabled(!config.isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadPassword() }
        .onChange(of: config.id) { _, _ in loadPassword() }
        .alert("Delete Storage Box", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Are you sure you want to delete \"\(config.effectiveDisplayName)\"? This will unmount the storage box and remove its configuration.")
        }
    }

    private func loadPassword() {
        guard !isNew, !config.username.isEmpty else {
            password = ""
            return
        }
        password = (try? keychainManager.loadPassword(for: config.username, configID: config.id)) ?? ""
        connectionTestResult = nil
    }

    private func save() {
        onSave()
        if config.authMethod == .password && !password.isEmpty {
            do {
                try keychainManager.savePassword(password, for: config.username, configID: config.id)
                connectionTestResult = "Saved"
                connectionTestSuccess = true
            } catch {
                connectionTestResult = "Config saved, but password failed: \(error.localizedDescription)"
                connectionTestSuccess = false
            }
        } else {
            connectionTestResult = "Saved"
            connectionTestSuccess = true
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil
        Task {
            do {
                let manager = SFTPConnectionManager(config: config, password: password)
                let sftp = try await manager.getSFTP(retryCount: 1)
                _ = try await sftp.listDirectory(atPath: config.basePath)
                await manager.disconnect()
                await MainActor.run {
                    connectionTestResult = "Connection successful"
                    connectionTestSuccess = true
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = UserFacingError.message(for: error)
                    connectionTestSuccess = false
                    isTestingConnection = false
                }
            }
        }
    }
}
