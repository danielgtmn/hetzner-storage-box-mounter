import Foundation
import UniformTypeIdentifiers

public struct RemoteItem: Sendable {
    public let path: String
    public let filename: String
    public let isDirectory: Bool
    public let size: UInt64
    public let modificationDate: Date?
    public let permissions: UInt32?

    public init(
        path: String,
        filename: String,
        isDirectory: Bool,
        size: UInt64,
        modificationDate: Date?,
        permissions: UInt32?
    ) {
        self.path = path
        self.filename = filename
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
    }

    public var parentPath: String {
        (path as NSString).deletingLastPathComponent
    }

    public var contentType: UTType {
        if isDirectory { return .folder }
        return UTType(filenameExtension: (filename as NSString).pathExtension) ?? .data
    }

    /// Stable identifier derived from the remote path (base64 encoded)
    public var itemIdentifier: String {
        path.data(using: .utf8)?.base64EncodedString() ?? path
    }

    /// Decode a remote path from an item identifier
    public static func decodePath(from identifier: String) -> String? {
        guard let data = Data(base64Encoded: identifier),
              let path = String(data: data, encoding: .utf8) else {
            return nil
        }
        return path
    }
}
