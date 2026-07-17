import Foundation

public struct AgentThread: Codable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public var lastMessage: String
    public var activeModel: String
    
    public init(id: String, title: String, lastMessage: String, activeModel: String) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.activeModel = activeModel
    }
}

public struct ThreadMessage: Codable, Identifiable, Hashable {
    public var id: UUID {
        // Since backend might not return UUID, we compute a stable one or generate.
        return UUID()
    }
    public let sender: String // "user" or "agent"
    public let content: String
    public let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case sender
        case content
        case timestamp
    }
    
    public init(sender: String, content: String, timestamp: Date) {
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sender = try container.decode(String.self, forKey: .sender)
        self.content = try container.decode(String.self, forKey: .content)
        
        let dateString = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        // Try fallback if standard ISO8601 fails
        if let date = formatter.date(from: dateString) {
            self.timestamp = date
        } else {
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            self.timestamp = fallbackFormatter.date(from: dateString) ?? Date()
        }
    }
}
