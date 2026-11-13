import Foundation

public enum RemoteFileKind: Hashable {
    case directory
    case file
    case symbolicLink
}

public struct RemoteFileEntry: Hashable, Identifiable {
    public let path: String
    public let name: String
    public let kind: RemoteFileKind
    public let byteSize: Int64

    public var id: String { path }
    public var isDirectory: Bool { kind == .directory }

    public init(path: String, name: String, kind: RemoteFileKind, byteSize: Int64 = 0) {
        self.path = path
        self.name = name
        self.kind = kind
        self.byteSize = byteSize
    }
}

public struct RemoteFileContents {
    public let text: String
    public let byteSize: Int64
    public let wasTruncated: Bool

    public init(text: String, byteSize: Int64, wasTruncated: Bool) {
        self.text = text
        self.byteSize = byteSize
        self.wasTruncated = wasTruncated
    }
}
