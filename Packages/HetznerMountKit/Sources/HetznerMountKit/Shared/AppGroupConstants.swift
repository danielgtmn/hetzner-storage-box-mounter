import Foundation

public enum AppGroupConstants {
    public static let groupIdentifier = "group.com.hetzner.mount"

    // UserDefaults keys
    public static let configHostKey = "sftp_host"
    public static let configPortKey = "sftp_port"
    public static let configUsernameKey = "sftp_username"
    public static let configAuthMethodKey = "sftp_auth_method"
    public static let configBasePathKey = "sftp_base_path"

    // Keychain
    public static let keychainServiceName = "com.hetzner.mount.sftp"
}
