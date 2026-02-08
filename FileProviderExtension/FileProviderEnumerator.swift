import FileProvider
import HetznerMountKit

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    private let containerIdentifier: NSFileProviderItemIdentifier
    private let sftpOperations: SFTPOperations
    private let basePath: String

    init(
        containerIdentifier: NSFileProviderItemIdentifier,
        sftpOperations: SFTPOperations,
        basePath: String
    ) {
        self.containerIdentifier = containerIdentifier
        self.sftpOperations = sftpOperations
        self.basePath = basePath
        super.init()
    }

    func invalidate() {}

    func enumerateItems(
        for observer: any NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        Task {
            do {
                let remotePath = resolveRemotePath(for: containerIdentifier)
                let items = try await sftpOperations.listDirectory(at: remotePath)
                let fpItems = items.map { FileProviderItem(remoteItem: $0) }
                observer.didEnumerate(fpItems)
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
        // SFTP has no change feed, so we do a full re-scan
        Task {
            do {
                let remotePath = resolveRemotePath(for: containerIdentifier)
                let items = try await sftpOperations.listDirectory(at: remotePath)
                let fpItems = items.map { FileProviderItem(remoteItem: $0) }
                observer.didUpdate(fpItems)
                let newAnchor = NSFileProviderSyncAnchor(
                    "\(Date().timeIntervalSince1970)".data(using: .utf8)!
                )
                observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        let anchor = NSFileProviderSyncAnchor(
            "\(Date().timeIntervalSince1970)".data(using: .utf8)!
        )
        completionHandler(anchor)
    }

    private func resolveRemotePath(for identifier: NSFileProviderItemIdentifier) -> String {
        if identifier == .rootContainer || identifier == .workingSet {
            return basePath
        }
        return RemoteItem.decodePath(from: identifier.rawValue) ?? basePath
    }
}
