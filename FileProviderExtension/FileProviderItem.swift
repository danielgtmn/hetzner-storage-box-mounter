import FileProvider
import UniformTypeIdentifiers
import HetznerMountKit

class FileProviderItem: NSObject, NSFileProviderItem {
    private let remoteItem: RemoteItem

    init(remoteItem: RemoteItem) {
        self.remoteItem = remoteItem
        super.init()
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        if remoteItem.path == "/" || remoteItem.path == "." {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(remoteItem.itemIdentifier)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        let parentPath = remoteItem.parentPath
        if parentPath == "/" || parentPath.isEmpty || parentPath == "." {
            return .rootContainer
        }
        guard let encoded = parentPath.data(using: .utf8)?.base64EncodedString() else {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(encoded)
    }

    var filename: String {
        remoteItem.filename
    }

    var contentType: UTType {
        remoteItem.contentType
    }

    var capabilities: NSFileProviderItemCapabilities {
        if remoteItem.isDirectory {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems,
                    .allowsRenaming, .allowsDeleting]
        }
        return [.allowsReading, .allowsWriting, .allowsRenaming,
                .allowsDeleting, .allowsEvicting]
    }

    var documentSize: NSNumber? {
        NSNumber(value: remoteItem.size)
    }

    var contentModificationDate: Date? {
        remoteItem.modificationDate
    }

    var itemVersion: NSFileProviderItemVersion {
        let versionString = "\(remoteItem.size)_\(remoteItem.modificationDate?.timeIntervalSince1970 ?? 0)"
        let versionData = versionString.data(using: .utf8) ?? Data()
        return NSFileProviderItemVersion(
            contentVersion: versionData,
            metadataVersion: versionData
        )
    }
}
