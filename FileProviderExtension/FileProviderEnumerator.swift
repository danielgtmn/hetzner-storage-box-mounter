import FileProvider
import HetznerMountKit
import os.log

private let enumLogger = Logger(subsystem: "com.danielgtmn.hetznermount.fileprovider", category: "Enumerator")

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
                enumLogger.info("enumerateItems at: \(remotePath)")
                let items = try await sftpOperations.listDirectory(at: remotePath)
                enumLogger.info("Got \(items.count) items")
                let fpItems = items.map { FileProviderItem(remoteItem: $0) }
                observer.didEnumerate(fpItems)
                observer.finishEnumerating(upTo: nil)
            } catch {
                enumLogger.error("enumerateItems error: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
            }
        }
    }

    func enumerateChanges(
        for observer: any NSFileProviderChangeObserver,
        from syncAnchor: NSFileProviderSyncAnchor
    ) {
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
                enumLogger.error("enumerateChanges error: \(error.localizedDescription)")
                observer.finishEnumeratingWithError(NSFileProviderError(.serverUnreachable))
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
