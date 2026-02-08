import Foundation
import Citadel

public enum UserFacingError {
    /// Maps any error from Citadel/SFTP/SSH to a user-friendly message.
    public static func message(for error: Error) -> String {
        // Our own errors
        if let sftpError = error as? SFTPError {
            return sftpMessage(for: sftpError)
        }

        let typeName = String(describing: type(of: error))
        let desc = error.localizedDescription

        // Citadel: Authentication
        if typeName.contains("AuthenticationFailed")
            || desc.contains("allAuthenticationOptionsFailed") {
            return "Authentication failed. Please check your username and password."
        }

        // Citadel: SSHClientError
        if desc.contains("unsupportedPasswordAuthentication") {
            return "The server does not support password authentication."
        }
        if desc.contains("channelCreationFailed") || desc.contains("channelFailure") {
            return "Could not open a channel to the server. Please try again."
        }

        // Citadel: CitadelError
        if desc.contains("unauthorized") && typeName.contains("CitadelError") {
            return "Authentication failed. Please check your credentials."
        }

        // Citadel: SFTPError (library-level)
        if desc.contains("connectionClosed") {
            return "The connection to the server was closed unexpectedly."
        }

        // SFTP status codes from server
        if typeName.contains("Status") || desc.contains("errorStatus") {
            return sftpStatusMessage(desc)
        }

        // NIO / Network errors
        if desc.contains("connect(descriptor") || desc.contains("Connection refused") {
            return "Could not connect to the server. Please check the host and port."
        }
        if desc.contains("timed out") || desc.contains("timeout") {
            return "Connection timed out. The server may be unreachable."
        }
        if desc.contains("No route to host") || desc.contains("Network is unreachable") {
            return "The server is unreachable. Please check your network connection."
        }
        if desc.contains("Could not resolve") || desc.contains("nodename nor servname") || desc.contains("Name or service not known") {
            return "Could not resolve hostname. Please check the host address."
        }
        if desc.contains("reset by peer") || desc.contains("Broken pipe") {
            return "The connection was interrupted. Please try again."
        }

        // Keychain
        if let keychainError = error as? KeychainError {
            return keychainError.localizedDescription ?? "Keychain error."
        }

        // Fallback: keep it short, strip internal noise
        let cleaned = desc
            .replacingOccurrences(of: "The operation couldn't be completed. ", with: "")
            .replacingOccurrences(of: "(Citadel.SSHClientError error 0.)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.isEmpty {
            return "An unexpected error occurred. Please try again."
        }
        return cleaned
    }

    // MARK: - Private

    private static func sftpMessage(for error: SFTPError) -> String {
        switch error {
        case .notConnected:
            return "Not connected to the server. Please check your connection."
        case .operationFailed(let msg):
            return "Operation failed: \(msg)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .configMissing:
            return "No configuration found. Please set up your Storage Box first."
        }
    }

    private static func sftpStatusMessage(_ desc: String) -> String {
        let lower = desc.lowercased()
        if lower.contains("permission denied") || lower.contains("permissiondenied") {
            return "Permission denied. Please check your access rights."
        }
        if lower.contains("no such file") || lower.contains("nosuchfile") {
            return "The requested file or directory does not exist."
        }
        if lower.contains("connection lost") || lower.contains("connectionlost") {
            return "The connection to the server was lost."
        }
        if lower.contains("directory not empty") {
            return "The directory is not empty."
        }
        return "Server error: \(desc)"
    }
}
