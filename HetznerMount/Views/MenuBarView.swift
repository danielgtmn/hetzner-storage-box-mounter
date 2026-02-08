import SwiftUI
import HetznerMountKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var domainManager = DomainManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(domainManager.isMounted ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(domainManager.isMounted ? "Mounted" : "Not Mounted")
                    .font(.headline)
            }

            if let error = domainManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            Divider()

            if StorageBoxConfig.load() != nil {
                Toggle("Mount Storage Box", isOn: Binding(
                    get: { domainManager.isMounted },
                    set: { newValue in
                        Task {
                            if newValue {
                                await domainManager.mount()
                            } else {
                                await domainManager.unmount()
                            }
                        }
                    }
                ))

                if domainManager.isMounted {
                    Button("Open in Finder") {
                        openInFinder()
                    }

                    Button("Refresh") {
                        Task { await domainManager.signalEnumerator() }
                    }
                }
            } else {
                Text("Configure your Storage Box in Settings to get started.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            Task { await domainManager.checkCurrentState() }
        }
    }

    private func openInFinder() {
        let cloudStoragePath = NSHomeDirectory() + "/Library/CloudStorage"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: cloudStoragePath),
           let mount = contents.first(where: { $0.contains("HetznerMount") || $0.contains("StorageBox") }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: cloudStoragePath + "/" + mount))
        }
    }
}
