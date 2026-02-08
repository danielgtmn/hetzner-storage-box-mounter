import Foundation
import Citadel
import NIO

public actor SFTPOperations {
    private let connectionManager: SFTPConnectionManager

    public init(connectionManager: SFTPConnectionManager) {
        self.connectionManager = connectionManager
    }

    /// List contents of a remote directory
    public func listDirectory(at path: String) async throws -> [RemoteItem] {
        let sftp = try await connectionManager.getSFTP()
        let entries = try await sftp.listDirectory(atPath: path)
        var items: [RemoteItem] = []
        for entry in entries {
            for component in entry.components {
                let filename = component.filename
                guard filename != "." && filename != ".." else { continue }
                let fullPath = path == "/"
                    ? "/\(filename)"
                    : "\(path)/\(filename)"
                let attrs = component.attributes
                let isDir = attrs.permissions.map { ($0 & 0o40000) != 0 } ?? false
                items.append(RemoteItem(
                    path: fullPath,
                    filename: filename,
                    isDirectory: isDir,
                    size: attrs.size ?? 0,
                    modificationDate: attrs.accessModificationTime?.modificationTime,
                    permissions: attrs.permissions
                ))
            }
        }
        return items
    }

    /// Download a file to a local temporary URL
    public func downloadFile(remotePath: String, progress: Progress) async throws -> URL {
        let sftp = try await connectionManager.getSFTP()
        let attrs = try await sftp.getAttributes(at: remotePath)
        let totalSize = attrs.size ?? 0
        progress.totalUnitCount = Int64(totalSize)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        let buffer = try await sftp.withFile(filePath: remotePath, flags: .read) { file in
            try await file.readAll()
        }

        let data = Data(buffer: buffer, byteTransferStrategy: .noCopy)
        try data.write(to: tempURL)
        progress.completedUnitCount = Int64(totalSize)
        return tempURL
    }

    /// Upload a local file to the remote path
    public func uploadFile(localURL: URL, remotePath: String, progress: Progress) async throws {
        let sftp = try await connectionManager.getSFTP()
        let data = try Data(contentsOf: localURL)
        progress.totalUnitCount = Int64(data.count)

        var buf = ByteBufferAllocator().buffer(capacity: data.count)
        buf.writeBytes(data)
        let buffer = buf

        try await sftp.withFile(
            filePath: remotePath,
            flags: [.write, .create, .truncate]
        ) { file in
            try await file.write(buffer, at: 0)
        }
        progress.completedUnitCount = Int64(data.count)
    }

    /// Create a remote directory
    public func createDirectory(at path: String) async throws {
        let sftp = try await connectionManager.getSFTP()
        try await sftp.createDirectory(atPath: path)
    }

    /// Delete a remote file
    public func deleteFile(at path: String) async throws {
        let sftp = try await connectionManager.getSFTP()
        try await sftp.remove(at: path)
    }

    /// Delete a remote directory (must be empty)
    public func deleteDirectory(at path: String) async throws {
        let sftp = try await connectionManager.getSFTP()
        try await sftp.rmdir(at: path)
    }

    /// Rename/move a remote item
    public func rename(from oldPath: String, to newPath: String) async throws {
        let sftp = try await connectionManager.getSFTP()
        try await sftp.rename(at: oldPath, to: newPath)
    }

    /// Get attributes of a single item
    public func getAttributes(at path: String) async throws -> RemoteItem {
        let sftp = try await connectionManager.getSFTP()
        let attrs = try await sftp.getAttributes(at: path)
        let filename = (path as NSString).lastPathComponent
        let isDir = attrs.permissions.map { ($0 & 0o40000) != 0 } ?? false
        return RemoteItem(
            path: path,
            filename: filename,
            isDirectory: isDir,
            size: attrs.size ?? 0,
            modificationDate: attrs.accessModificationTime?.modificationTime,
            permissions: attrs.permissions
        )
    }
}
