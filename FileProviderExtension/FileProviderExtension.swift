import FileProvider
import HetznerMountKit

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain
    private var connectionManager: SFTPConnectionManager?
    private var sftpOperations: SFTPOperations?
    private var config: StorageBoxConfig?

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        setupConnection()
    }

    private func setupConnection() {
        guard let config = StorageBoxConfig.load() else { return }
        self.config = config
        let keychain = KeychainManager()
        let password = try? keychain.loadPassword(for: config.username)
        let manager = SFTPConnectionManager(config: config, password: password)
        self.connectionManager = manager
        self.sftpOperations = SFTPOperations(connectionManager: manager)
    }

    func invalidate() {
        Task {
            await connectionManager?.disconnect()
        }
    }

    // MARK: - Enumeration

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> any NSFileProviderEnumerator {
        guard let ops = sftpOperations, let config = config else {
            throw NSFileProviderError(.notAuthenticated)
        }
        return FileProviderEnumerator(
            containerIdentifier: containerItemIdentifier,
            sftpOperations: ops,
            basePath: config.basePath
        )
    }

    // MARK: - Item Metadata

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        if identifier == .rootContainer {
            let rootItem = RemoteItem(
                path: config?.basePath ?? "/",
                filename: "",
                isDirectory: true,
                size: 0,
                modificationDate: nil,
                permissions: nil
            )
            completionHandler(FileProviderItem(remoteItem: rootItem), nil)
            progress.completedUnitCount = 1
            return progress
        }

        Task {
            do {
                guard let ops = sftpOperations else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                let path = decodePath(from: identifier)
                let remoteItem = try await ops.getAttributes(at: path)
                completionHandler(FileProviderItem(remoteItem: remoteItem), nil)
            } catch {
                completionHandler(nil, error)
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    // MARK: - Download

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                guard let ops = sftpOperations else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                let remotePath = decodePath(from: itemIdentifier)
                let localURL = try await ops.downloadFile(remotePath: remotePath, progress: progress)
                let remoteItem = try await ops.getAttributes(at: remotePath)
                completionHandler(localURL, FileProviderItem(remoteItem: remoteItem), nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }
        return progress
    }

    // MARK: - Create

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                guard let ops = sftpOperations else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                let parentPath = decodePath(from: itemTemplate.parentItemIdentifier)
                let remotePath = parentPath == "/"
                    ? "/\(itemTemplate.filename)"
                    : "\(parentPath)/\(itemTemplate.filename)"

                if itemTemplate.contentType == .folder {
                    try await ops.createDirectory(at: remotePath)
                } else if let localURL = url {
                    try await ops.uploadFile(localURL: localURL, remotePath: remotePath, progress: progress)
                }

                let remoteItem = try await ops.getAttributes(at: remotePath)
                completionHandler(FileProviderItem(remoteItem: remoteItem), [], false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }

    // MARK: - Modify

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                guard let ops = sftpOperations else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                var currentPath = decodePath(from: item.itemIdentifier)
                var identifierChanged = false

                // Handle rename or move
                if changedFields.contains(.filename) || changedFields.contains(.parentItemIdentifier) {
                    let newParent = decodePath(from: item.parentItemIdentifier)
                    let newPath = newParent == "/"
                        ? "/\(item.filename)"
                        : "\(newParent)/\(item.filename)"
                    if newPath != currentPath {
                        try await ops.rename(from: currentPath, to: newPath)
                        currentPath = newPath
                        identifierChanged = true
                    }
                }

                // Handle content update
                if changedFields.contains(.contents), let localURL = newContents {
                    try await ops.uploadFile(localURL: localURL, remotePath: currentPath, progress: progress)
                }

                let remoteItem = try await ops.getAttributes(at: currentPath)
                completionHandler(FileProviderItem(remoteItem: remoteItem), [], identifierChanged, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }
        return progress
    }

    // MARK: - Delete

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping ((any Error)?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let ops = sftpOperations else {
                    throw NSFileProviderError(.notAuthenticated)
                }
                let remotePath = decodePath(from: identifier)
                let item = try await ops.getAttributes(at: remotePath)

                if item.isDirectory {
                    if options.contains(.recursive) {
                        try await deleteRecursively(at: remotePath, ops: ops)
                    } else {
                        let contents = try await ops.listDirectory(at: remotePath)
                        if !contents.isEmpty {
                            throw NSFileProviderError(.directoryNotEmpty)
                        }
                        try await ops.deleteDirectory(at: remotePath)
                    }
                } else {
                    try await ops.deleteFile(at: remotePath)
                }
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    // MARK: - Helpers

    private func decodePath(from identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer {
            return config?.basePath ?? "/"
        }
        return RemoteItem.decodePath(from: identifier.rawValue) ?? config?.basePath ?? "/"
    }

    private func deleteRecursively(at path: String, ops: SFTPOperations) async throws {
        let contents = try await ops.listDirectory(at: path)
        for item in contents {
            if item.isDirectory {
                try await deleteRecursively(at: item.path, ops: ops)
            } else {
                try await ops.deleteFile(at: item.path)
            }
        }
        try await ops.deleteDirectory(at: path)
    }
}
