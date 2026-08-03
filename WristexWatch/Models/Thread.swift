import Foundation

public struct AgentThread: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var lastMessage: String
    public var activeModel: String
    public var codexSessionID: String?
    public var connectionID: String?

    public init(
        id: String,
        title: String,
        lastMessage: String,
        activeModel: String,
        codexSessionID: String? = nil,
        connectionID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.activeModel = activeModel
        self.codexSessionID = codexSessionID
        self.connectionID = connectionID
    }
}

public struct ThreadMessage: Codable, Identifiable, Hashable {
    public let id: UUID
    public let sender: String
    public let content: String
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id, sender, content, timestamp
    }

    public init(id: UUID = UUID(), sender: String, content: String, timestamp: Date) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sender = try container.decode(String.self, forKey: .sender)
        content = try container.decode(String.self, forKey: .content)

        if let date = try? container.decode(Date.self, forKey: .timestamp) {
            timestamp = date
        } else {
            let value = try container.decode(String.self, forKey: .timestamp)
            timestamp = ISO8601DateFormatter().date(from: value) ?? Date()
        }
    }
}
