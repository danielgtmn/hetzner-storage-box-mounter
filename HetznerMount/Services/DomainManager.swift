import FileProvider
import HetznerMountKit

struct ManagedStorageBox: Identifiable {
    var id: UUID { config.id }
    var config: StorageBoxConfig
    var isMounted: Bool
    var error: String?
}

@MainActor
class DomainManager: ObservableObject {
    static let shared = DomainManager()

    @Published var boxes: [ManagedStorageBox] = []

    private let store = StorageBoxConfigStore()

    /// Whether any box is currently mounted
    var anyMounted: Bool {
        boxes.contains(where: { $0.isMounted })
    }

    private init() {}

    // MARK: - Domain ID helpers

    static let domainPrefix = "com.danielgtmn.hetznermount.storagebox."

    static func domainIdentifier(for configID: UUID) -> NSFileProviderDomainIdentifier {
        NSFileProviderDomainIdentifier(domainPrefix + configID.uuidString)
    }

    static func configID(from domainIdentifier: NSFileProviderDomainIdentifier) -> UUID? {
        let raw = domainIdentifier.rawValue
        guard raw.hasPrefix(domainPrefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(domainPrefix.count)))
    }

    // MARK: - Mount / Unmount

    func mount(configID: UUID) async {
        guard let config = store.get(id: configID) else { return }

        let domain = NSFileProviderDomain(
            identifier: Self.domainIdentifier(for: configID),
            displayName: config.effectiveDisplayName
        )

        do {
            print("[DomainManager] Adding domain: \(domain.identifier.rawValue)")
            try await NSFileProviderManager.add(domain)
            print("[DomainManager] Domain added successfully")
            updateBox(configID: configID, isMounted: true, error: nil)
        } catch {
            print("[DomainManager] Mount failed: \(error)")
            updateBox(configID: configID, isMounted: false, error: UserFacingError.message(for: error))
        }
    }

    func unmount(configID: UUID) async {
        let domainID = Self.domainIdentifier(for: configID)
        do {
            let domains = try await NSFileProviderManager.domains()
            if let domain = domains.first(where: { $0.identifier == domainID }) {
                try await NSFileProviderManager.remove(domain)
            }
            updateBox(configID: configID, isMounted: false, error: nil)
        } catch {
            updateBox(configID: configID, isMounted: false, error: UserFacingError.message(for: error))
        }
    }

    /// Re-adds the domain to update its display name in Finder
    func remount(configID: UUID) async {
        guard let box = boxes.first(where: { $0.config.id == configID }),
              box.isMounted else { return }
        await unmount(configID: configID)
        await mount(configID: configID)
    }

    func signalEnumerator(configID: UUID) async {
        let domainID = Self.domainIdentifier(for: configID)
        do {
            let domains = try await NSFileProviderManager.domains()
            guard let domain = domains.first(where: { $0.identifier == domainID }),
                  let manager = NSFileProviderManager(for: domain) else { return }
            try await manager.signalEnumerator(for: .workingSet)
        } catch {
            updateBox(configID: configID, isMounted: nil, error: UserFacingError.message(for: error))
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        let configs = store.loadAll()
        let activeDomains = (try? await NSFileProviderManager.domains()) ?? []
        let mountedIDs = Set(activeDomains.compactMap { Self.configID(from: $0.identifier) })

        print("[DomainManager] refreshAll: \(configs.count) configs, \(activeDomains.count) domains")

        boxes = configs.map { config in
            ManagedStorageBox(
                config: config,
                isMounted: mountedIDs.contains(config.id),
                error: nil
            )
        }

        // Clean up orphaned domains (domains without a config) and legacy domains
        for domain in activeDomains {
            let raw = domain.identifier.rawValue
            let isLegacy = (raw == "com.danielgtmn.hetznermount.storagebox")
            let isOrphaned = Self.configID(from: domain.identifier).map { id in
                !configs.contains(where: { $0.id == id })
            } ?? false

            if isLegacy || isOrphaned {
                print("[DomainManager] Removing domain: \(raw) (legacy=\(isLegacy), orphaned=\(isOrphaned))")
                try? await NSFileProviderManager.remove(domain)
            }
        }
    }

    /// Removes a config and its domain
    func removeBox(configID: UUID) async {
        await unmount(configID: configID)
        let keychain = KeychainManager()
        if let config = store.get(id: configID) {
            try? keychain.deletePassword(for: config.username, configID: configID)
        }
        store.delete(id: configID)
        await refreshAll()
    }

    // MARK: - Migration (call once at app start)

    func migrateIfNeeded() async {
        if let migratedID = store.migrateFromLegacyIfNeeded() {
            print("[DomainManager] Migrated legacy config with id: \(migratedID)")
            // Remove old domain and re-mount with new domain ID
            let oldDomainID = NSFileProviderDomainIdentifier("com.danielgtmn.hetznermount.storagebox")
            let domains = (try? await NSFileProviderManager.domains()) ?? []
            if let oldDomain = domains.first(where: { $0.identifier == oldDomainID }) {
                try? await NSFileProviderManager.remove(oldDomain)
            }
            await refreshAll()
            await mount(configID: migratedID)
        } else {
            await refreshAll()
        }
    }

    // MARK: - Private

    private func updateBox(configID: UUID, isMounted: Bool?, error: String?) {
        if let index = boxes.firstIndex(where: { $0.config.id == configID }) {
            if let isMounted { boxes[index].isMounted = isMounted }
            boxes[index].error = error
        }
    }
}
