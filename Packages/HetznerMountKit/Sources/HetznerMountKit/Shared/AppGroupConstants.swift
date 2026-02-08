import Foundation

public enum AppGroupConstants {
    public static let groupIdentifier = "group.com.danielgtmn.hetznermount"

    // UserDefaults keys
    public static let configHostKey = "sftp_host"
    public static let configPortKey = "sftp_port"
    public static let configUsernameKey = "sftp_username"
    public static let configAuthMethodKey = "sftp_auth_method"
    public static let configBasePathKey = "sftp_base_path"

    // Keychain
    public static let keychainServiceName = "com.danielgtmn.hetznermount.sftp"
}
