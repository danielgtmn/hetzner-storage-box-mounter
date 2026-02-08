import FileProvider
import HetznerMountKit

@MainActor
class DomainManager: ObservableObject {
    static let shared = DomainManager()

    @Published var isMounted = false
    @Published var error: String?

    private let domainIdentifier = NSFileProviderDomainIdentifier("com.hetzner.mount.storagebox")
    private let displayName = "StorageBox"

    private init() {
        Task { await checkCurrentState() }
    }

    func mount() async {
        let domain = NSFileProviderDomain(
            identifier: domainIdentifier,
            displayName: displayName
        )
        do {
            try await NSFileProviderManager.add(domain)
            isMounted = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            isMounted = false
        }
    }

    func unmount() async {
        do {
            let domains = try await NSFileProviderManager.domains()
            if let domain = domains.first(where: { $0.identifier == domainIdentifier }) {
                try await NSFileProviderManager.remove(domain)
            }
            isMounted = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signalEnumerator() async {
        do {
            let domains = try await NSFileProviderManager.domains()
            guard let domain = domains.first(where: { $0.identifier == domainIdentifier }),
                  let manager = NSFileProviderManager(for: domain) else { return }
            try await manager.signalEnumerator(for: .workingSet)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func checkCurrentState() async {
        let domains = (try? await NSFileProviderManager.domains()) ?? []
        isMounted = domains.contains(where: { $0.identifier == domainIdentifier })
    }
}
