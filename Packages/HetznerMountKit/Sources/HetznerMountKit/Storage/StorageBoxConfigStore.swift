import Foundation

public final class StorageBoxConfigStore: Sendable {
    private static let storageKey = "storage_boxes_v2"
    private static let migrationDoneKey = "storage_boxes_migrated"

    private let defaults: UserDefaults?

    public init() {
        self.defaults = UserDefaults(suiteName: AppGroupConstants.groupIdentifier)
    }

    // MARK: - CRUD

    public func loadAll() -> [StorageBoxConfig] {
        guard let defaults,
              let data = defaults.data(forKey: Self.storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([StorageBoxConfig].self, from: data)) ?? []
    }

    public func save(_ configs: [StorageBoxConfig]) {
        guard let defaults,
              let data = try? JSONEncoder().encode(configs) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public func add(_ config: StorageBoxConfig) {
        var configs = loadAll()
        configs.append(config)
        save(configs)
    }

    public func update(_ config: StorageBoxConfig) {
        var configs = loadAll()
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            save(configs)
        }
    }

    public func delete(id: UUID) {
        var configs = loadAll()
        configs.removeAll(where: { $0.id == id })
        save(configs)
    }

    public func get(id: UUID) -> StorageBoxConfig? {
        loadAll().first(where: { $0.id == id })
    }

    // MARK: - Migration

    /// Migrates legacy single-config to new multi-config format.
    /// Returns the migrated config's ID if migration occurred, nil otherwise.
    @discardableResult
    public func migrateFromLegacyIfNeeded() -> UUID? {
        guard let defaults else { return nil }
        guard !defaults.bool(forKey: Self.migrationDoneKey) else { return nil }

        defer { defaults.set(true, forKey: Self.migrationDoneKey) }

        guard loadAll().isEmpty,
              let legacy = StorageBoxConfig.loadLegacy() else {
            return nil
        }

        add(legacy)

        // Migrate keychain: copy old password to new key format
        let keychain = KeychainManager()
        if let password = try? keychain.loadPassword(for: legacy.username) {
            try? keychain.savePassword(password, for: legacy.username, configID: legacy.id)
        }

        StorageBoxConfig.clearLegacy()
        return legacy.id
    }
}
