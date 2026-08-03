import Foundation

public struct ModelOption: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let reasoningEfforts: [String]
    public let supportsPersonality: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, name, reasoningEfforts, supportsPersonality
    }

    public init(
        id: String,
        name: String,
        reasoningEfforts: [String] = [],
        supportsPersonality: Bool = false
    ) {
        self.id = id
        self.name = name
        self.reasoningEfforts = reasoningEfforts
        self.supportsPersonality = supportsPersonality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        reasoningEfforts = try container.decodeIfPresent([String].self, forKey: .reasoningEfforts) ?? []
        supportsPersonality = try container.decodeIfPresent(Bool.self, forKey: .supportsPersonality) ?? false
    }
}
