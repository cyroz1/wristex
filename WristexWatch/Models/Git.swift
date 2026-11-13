import Foundation

public struct GitStatus: Codable, Hashable {
    public let branch: String
    public let modifiedFiles: [String]
    public let untrackedFiles: [String]
    public let ahead: Int
    public let behind: Int
    public let hasUpstream: Bool
    public let hasCommit: Bool
    public let isDetached: Bool
    
    public init(
        branch: String,
        modifiedFiles: [String],
        untrackedFiles: [String],
        ahead: Int,
        behind: Int,
        hasUpstream: Bool = true,
        hasCommit: Bool = true,
        isDetached: Bool = false
    ) {
        self.branch = branch
        self.modifiedFiles = modifiedFiles
        self.untrackedFiles = untrackedFiles
        self.ahead = ahead
        self.behind = behind
        self.hasUpstream = hasUpstream
        self.hasCommit = hasCommit
        self.isDetached = isDetached
    }
}

public enum GitAction: String, Codable {
    case pull = "pull"
    case push = "push"
    case commit = "commit"
}
