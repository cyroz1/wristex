import Foundation

public struct ApprovalRequest: Codable, Identifiable, Hashable {
    public let id: String
    public let toolName: String
    public let details: String
    public var status: String // "pending", "approved", "denied"
    public let timestamp: Date
    public let responseMethod: String?
    public let threadID: String?
    public let turnID: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case toolName
        case details
        case status
        case timestamp, responseMethod, threadID, turnID
    }
    
    public init(
        id: String,
        toolName: String,
        details: String,
        status: String,
        timestamp: Date,
        responseMethod: String? = nil,
        threadID: String? = nil,
        turnID: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.details = details
        self.status = status
        self.timestamp = timestamp
        self.responseMethod = responseMethod
        self.threadID = threadID
        self.turnID = turnID
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.toolName = try container.decode(String.self, forKey: .toolName)
        self.details = try container.decode(String.self, forKey: .details)
        self.status = try container.decode(String.self, forKey: .status)
        self.responseMethod = try container.decodeIfPresent(String.self, forKey: .responseMethod)
        self.threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        self.turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
        
        let dateString = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            self.timestamp = date
        } else {
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            self.timestamp = fallbackFormatter.date(from: dateString) ?? Date()
        }
    }
}
