import Foundation

public struct ApprovalQuestionOption: Codable, Hashable, Identifiable {
    public let label: String
    public let description: String

    public var id: String { label }

    public init(label: String, description: String) {
        self.label = label
        self.description = description
    }
}

public struct ApprovalQuestion: Codable, Hashable, Identifiable {
    public let id: String
    public let header: String
    public let question: String
    public let isOther: Bool
    public let isSecret: Bool
    public let options: [ApprovalQuestionOption]?

    public init(
        id: String,
        header: String,
        question: String,
        isOther: Bool,
        isSecret: Bool,
        options: [ApprovalQuestionOption]?
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.isOther = isOther
        self.isSecret = isSecret
        self.options = options
    }
}

public struct ApprovalFormField: Codable, Hashable, Identifiable {
    public let name: String
    public let title: String
    public let description: String
    public let kind: String
    public let required: Bool
    public let isSecret: Bool
    public let defaultValue: String?
    public let options: [ApprovalQuestionOption]?

    public var id: String { name }

    public init(
        name: String,
        title: String,
        description: String,
        kind: String,
        required: Bool,
        isSecret: Bool,
        defaultValue: String?,
        options: [ApprovalQuestionOption]?
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.kind = kind
        self.required = required
        self.isSecret = isSecret
        self.defaultValue = defaultValue
        self.options = options
    }
}

public struct ApprovalRequest: Codable, Identifiable, Hashable {
    public let id: String
    public let toolName: String
    public let details: String
    public var status: String // "pending", "approved", "denied"
    public let timestamp: Date
    public let responseMethod: String?
    public let threadID: String?
    public let turnID: String?
    public let questions: [ApprovalQuestion]
    public let isBlocking: Bool
    public let formFields: [ApprovalFormField]
    public let elicitationMode: String?
    public let elicitationURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case toolName
        case details
        case status
        case timestamp, responseMethod, threadID, turnID, questions, isBlocking
        case formFields, elicitationMode, elicitationURL
    }
    
    public init(
        id: String,
        toolName: String,
        details: String,
        status: String,
        timestamp: Date,
        responseMethod: String? = nil,
        threadID: String? = nil,
        turnID: String? = nil,
        questions: [ApprovalQuestion] = [],
        isBlocking: Bool = false,
        formFields: [ApprovalFormField] = [],
        elicitationMode: String? = nil,
        elicitationURL: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.details = details
        self.status = status
        self.timestamp = timestamp
        self.responseMethod = responseMethod
        self.threadID = threadID
        self.turnID = turnID
        self.questions = questions
        self.isBlocking = isBlocking
        self.formFields = formFields
        self.elicitationMode = elicitationMode
        self.elicitationURL = elicitationURL
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
        self.questions = try container.decodeIfPresent([ApprovalQuestion].self, forKey: .questions) ?? []
        self.isBlocking = try container.decodeIfPresent(Bool.self, forKey: .isBlocking) ?? false
        self.formFields = try container.decodeIfPresent([ApprovalFormField].self, forKey: .formFields) ?? []
        self.elicitationMode = try container.decodeIfPresent(String.self, forKey: .elicitationMode)
        self.elicitationURL = try container.decodeIfPresent(String.self, forKey: .elicitationURL)
        
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
