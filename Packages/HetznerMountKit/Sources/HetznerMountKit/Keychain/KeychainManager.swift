import Foundation
import Security

public enum KeychainError: Error, LocalizedError, Sendable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status): return "Keychain save failed: \(status)"
        case .loadFailed(let status): return "Keychain load failed: \(status)"
        case .deleteFailed(let status): return "Keychain delete failed: \(status)"
        }
    }
}

public final class KeychainManager: Sendable {
    private let service: String
    private let accessGroup: String

    public init(
        service: String = AppGroupConstants.keychainServiceName,
        accessGroup: String = AppGroupConstants.groupIdentifier
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - Config-scoped methods (multi-box)

    public func savePassword(_ password: String, for account: String, configID: UUID) throws {
        try savePassword(password, for: Self.accountKey(account, configID: configID))
    }

    public func loadPassword(for account: String, configID: UUID) throws -> String? {
        try loadPassword(for: Self.accountKey(account, configID: configID))
    }

    public func deletePassword(for account: String, configID: UUID) throws {
        try deletePassword(for: Self.accountKey(account, configID: configID))
    }

    private static func accountKey(_ account: String, configID: UUID) -> String {
        "\(configID.uuidString)-\(account)"
    }

    // MARK: - Legacy methods (kept for migration)

    public func savePassword(_ password: String, for account: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public func loadPassword(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func deletePassword(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
