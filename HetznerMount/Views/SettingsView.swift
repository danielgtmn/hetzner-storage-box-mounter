import SwiftUI
import ServiceManagement
import HetznerMountKit

struct SettingsView: View {
    @State private var config: StorageBoxConfig
    @State private var password = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    @State private var connectionTestSuccess = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let keychainManager = KeychainManager()

    init() {
        _config = State(initialValue: StorageBoxConfig.load() ?? StorageBoxConfig())
    }

    var body: some View {
        Form {
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
                }

                Button("Save") {
                    save()
                }
                .disabled(!config.isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 450, height: 380)
        .onAppear {
            loadPassword()
        }
    }

    private func loadPassword() {
        guard !config.username.isEmpty else { return }
        password = (try? keychainManager.loadPassword(for: config.username)) ?? ""
    }

    private func save() {
        config.save()
        if config.authMethod == .password && !password.isEmpty {
            do {
                try keychainManager.savePassword(password, for: config.username)
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
                    connectionTestResult = error.localizedDescription
                    connectionTestSuccess = false
                    isTestingConnection = false
                }
            }
        }
    }
}
