import Foundation

public enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case password
    case sshKey
}

public struct StorageBoxConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var displayName: String
    public var host: String
    public var port: Int
    public var username: String
    public var authMethod: AuthMethod
    public var basePath: String

    public init(
        id: UUID = UUID(),
        displayName: String = "",
        host: String = "",
        port: Int = 23,
        username: String = "",
        authMethod: AuthMethod = .password,
        basePath: String = "/"
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.basePath = basePath
    }

    public var isValid: Bool {
        !host.isEmpty && !username.isEmpty && port > 0
    }

    /// Effective display name: uses displayName if set, otherwise username
    public var effectiveDisplayName: String {
        displayName.isEmpty ? username : displayName
    }

    // MARK: - Legacy persistence (kept for migration)

    public func saveLegacy() {
        guard let defaults = UserDefaults(suiteName: AppGroupConstants.groupIdentifier) else { return }
        defaults.set(host, forKey: AppGroupConstants.configHostKey)
        defaults.set(port, forKey: AppGroupConstants.configPortKey)
        defaults.set(username, forKey: AppGroupConstants.configUsernameKey)
        defaults.set(authMethod.rawValue, forKey: AppGroupConstants.configAuthMethodKey)
        defaults.set(basePath, forKey: AppGroupConstants.configBasePathKey)
    }

    public static func loadLegacy() -> StorageBoxConfig? {
        guard let defaults = UserDefaults(suiteName: AppGroupConstants.groupIdentifier) else { return nil }
        guard let host = defaults.string(forKey: AppGroupConstants.configHostKey),
              let username = defaults.string(forKey: AppGroupConstants.configUsernameKey),
              !host.isEmpty, !username.isEmpty else {
            return nil
        }
        let port = defaults.integer(forKey: AppGroupConstants.configPortKey)
        let authMethodRaw = defaults.string(forKey: AppGroupConstants.configAuthMethodKey) ?? AuthMethod.password.rawValue
        let basePath = defaults.string(forKey: AppGroupConstants.configBasePathKey) ?? "/"

        return StorageBoxConfig(
            id: UUID(),
            displayName: username,
            host: host,
            port: port > 0 ? port : 23,
            username: username,
            authMethod: AuthMethod(rawValue: authMethodRaw) ?? .password,
            basePath: basePath.isEmpty ? "/" : basePath
        )
    }

    public static func clearLegacy() {
        guard let defaults = UserDefaults(suiteName: AppGroupConstants.groupIdentifier) else { return }
        defaults.removeObject(forKey: AppGroupConstants.configHostKey)
        defaults.removeObject(forKey: AppGroupConstants.configPortKey)
        defaults.removeObject(forKey: AppGroupConstants.configUsernameKey)
        defaults.removeObject(forKey: AppGroupConstants.configAuthMethodKey)
        defaults.removeObject(forKey: AppGroupConstants.configBasePathKey)
    }
}
