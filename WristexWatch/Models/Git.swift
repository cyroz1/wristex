import Foundation

public struct GitStatus: Codable, Hashable {
    public let branch: String
    public let modifiedFiles: [String]
    public let untrackedFiles: [String]
    public let ahead: Int
    public let behind: Int
    
    public init(branch: String, modifiedFiles: [String], untrackedFiles: [String], ahead: Int, behind: Int) {
        self.branch = branch
        self.modifiedFiles = modifiedFiles
        self.untrackedFiles = untrackedFiles
        self.ahead = ahead
        self.behind = behind
    }
}

public enum GitAction: String, Codable {
    case pull = "pull"
    case push = "push"
    case commit = "commit"
}
