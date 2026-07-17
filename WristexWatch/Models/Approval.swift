import Foundation

public struct ApprovalRequest: Codable, Identifiable, Hashable {
    public let id: String
    public let toolName: String
    public let details: String
    public var status: String // "pending", "approved", "denied"
    public let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case toolName
        case details
        case status
        case timestamp
    }
    
    public init(id: String, toolName: String, details: String, status: String, timestamp: Date) {
        self.id = id
        self.toolName = toolName
        self.details = details
        self.status = status
        self.timestamp = timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.toolName = try container.decode(String.self, forKey: .toolName)
        self.details = try container.decode(String.self, forKey: .details)
        self.status = try container.decode(String.self, forKey: .status)
        
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
