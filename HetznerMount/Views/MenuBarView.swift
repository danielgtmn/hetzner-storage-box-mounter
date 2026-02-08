import Sparkle
import SwiftUI
import FileProvider
import HetznerMountKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var domainManager = DomainManager.shared
    @StateObject private var updateViewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        _updateViewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if domainManager.boxes.isEmpty {
                Text("No Storage Boxes configured.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(domainManager.boxes) { box in
                    StorageBoxRow(box: box, domainManager: domainManager)
                }
            }

            Divider()

            Button("Add Storage Box...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .addStorageBox, object: nil)
            }

            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Check for Updates...") {
                updateViewModel.checkForUpdates()
            }
            .disabled(!updateViewModel.canCheckForUpdates)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 280)
    }
}

private struct StorageBoxRow: View {
    let box: ManagedStorageBox
    let domainManager: DomainManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(box.isMounted ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(box.config.effectiveDisplayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { box.isMounted },
                    set: { newValue in
                        Task {
                            if newValue {
                                await domainManager.mount(configID: box.id)
                            } else {
                                await domainManager.unmount(configID: box.id)
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if let error = box.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            if box.isMounted {
                HStack(spacing: 12) {
                    Button("Open in Finder") {
                        openInFinder(configID: box.id)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Button("Refresh") {
                        Task { await domainManager.signalEnumerator(configID: box.id) }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func openInFinder(configID: UUID) {
        let domainID = DomainManager.domainIdentifier(for: configID)
        Task {
            let domains = (try? await NSFileProviderManager.domains()) ?? []
            guard let domain = domains.first(where: { $0.identifier == domainID }),
                  let manager = NSFileProviderManager(for: domain) else { return }
            do {
                let url = try await manager.getUserVisibleURL(for: .rootContainer)
                let didAccess = url.startAccessingSecurityScopedResource()
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if didAccess { url.stopAccessingSecurityScopedResource() }
            } catch {
                print("[MenuBar] Failed to get user-visible URL: \(error)")
            }
        }
    }
}

extension Notification.Name {
    static let addStorageBox = Notification.Name("addStorageBox")
}
