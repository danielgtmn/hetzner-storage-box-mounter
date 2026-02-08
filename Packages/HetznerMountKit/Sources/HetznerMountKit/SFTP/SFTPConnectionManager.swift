import Foundation
import Citadel
import NIO

public enum SFTPError: Error, LocalizedError, Sendable {
    case notConnected
    case operationFailed(String)
    case fileNotFound(String)
    case configMissing

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to SFTP server"
        case .operationFailed(let msg): return "SFTP operation failed: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .configMissing: return "No connection configuration found"
        }
    }
}

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

public actor SFTPConnectionManager {
    private var sshClient: SSHClient?
    private var sftpClient: SFTPClient?
    private let config: StorageBoxConfig
    private let password: String?

    public private(set) var state: ConnectionState = .disconnected

    public init(config: StorageBoxConfig, password: String?) {
        self.config = config
        self.password = password
    }

    public func connect() async throws {
        state = .connecting
        do {
            let client = try await SSHClient.connect(
                host: config.host,
                port: config.port,
                authenticationMethod: .passwordBased(
                    username: config.username,
                    password: password ?? ""
                ),
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
            self.sshClient = client
            self.sftpClient = try await client.openSFTP()
            state = .connected
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    public func disconnect() async {
        if let sftp = sftpClient {
            try? await sftp.close()
        }
        if let ssh = sshClient {
            try? await ssh.close()
        }
        sftpClient = nil
        sshClient = nil
        state = .disconnected
    }

    /// Get an active SFTP client, reconnecting if necessary with retry
    public func getSFTP(retryCount: Int = 3) async throws -> SFTPClient {
        for attempt in 0..<retryCount {
            if let sftp = sftpClient, sftp.isActive {
                return sftp
            }
            do {
                try await connect()
                if let sftp = sftpClient {
                    return sftp
                }
            } catch {
                if attempt == retryCount - 1 { throw error }
                let delay = UInt64(pow(2.0, Double(attempt))) * 500_000_000
                try await Task.sleep(nanoseconds: delay)
            }
        }
        throw SFTPError.notConnected
    }
}
