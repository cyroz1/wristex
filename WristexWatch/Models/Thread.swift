import Foundation

public enum AgentThreadStatusKind: String, Codable, Hashable {
    case notLoaded
    case idle
    case active
    case systemError
}

public enum AgentThreadActiveFlag: String, Codable, Hashable {
    case waitingOnApproval
    case waitingOnUserInput
}

public struct AgentThreadStatus: Codable, Hashable {
    public var kind: AgentThreadStatusKind
    public var activeFlags: [AgentThreadActiveFlag]

    public init(kind: AgentThreadStatusKind = .idle, activeFlags: [AgentThreadActiveFlag] = []) {
        self.kind = kind
        self.activeFlags = activeFlags
    }

    public var label: String {
        switch kind {
        case .notLoaded: return "Not loaded"
        case .idle: return "Ready"
        case .active:
            if activeFlags.contains(.waitingOnApproval) { return "Needs approval" }
            if activeFlags.contains(.waitingOnUserInput) { return "Needs input" }
            return "Working"
        case .systemError: return "Error"
        }
    }

    public var shortLabel: String {
        switch kind {
        case .notLoaded: return "OFF"
        case .idle: return "READY"
        case .active:
            if activeFlags.contains(.waitingOnApproval) { return "APPROVE" }
            if activeFlags.contains(.waitingOnUserInput) { return "INPUT" }
            return "RUNNING"
        case .systemError: return "ERROR"
        }
    }
}

public enum CodexPersonality: String, CaseIterable, Codable, Hashable, Identifiable {
    case automatic
    case friendly
    case pragmatic

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .friendly: return "Friendly"
        case .pragmatic: return "Pragmatic"
        }
    }
    var serverValue: String? { self == .automatic ? nil : rawValue }
}

public enum CodexApprovalPolicy: String, CaseIterable, Codable, Hashable, Identifiable {
    case onRequest = "on-request"
    case untrusted
    case never

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .onRequest: return "Ask when needed"
        case .untrusted: return "Ask for untrusted"
        case .never: return "Never ask"
        }
    }
}

public enum CodexSandboxPolicy: String, CaseIterable, Codable, Hashable, Identifiable {
    case automatic
    case readOnly
    case workspaceWrite
    case dangerFullAccess

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return "Host default"
        case .readOnly: return "Read-only"
        case .workspaceWrite: return "Workspace write"
        case .dangerFullAccess: return "Full access"
        }
    }

    var serverValue: [String: Any]? {
        switch self {
        case .automatic: return nil
        case .readOnly: return ["type": "readOnly", "networkAccess": false]
        case .workspaceWrite: return ["type": "workspaceWrite", "networkAccess": false]
        case .dangerFullAccess: return ["type": "dangerFullAccess"]
        }
    }
}

public enum CodexReasoningSummary: String, CaseIterable, Codable, Hashable, Identifiable {
    case automatic
    case concise
    case detailed
    case none

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .concise: return "Concise"
        case .detailed: return "Detailed"
        case .none: return "Hidden"
        }
    }
    var serverValue: String? { self == .automatic ? nil : rawValue }
}

public struct ThreadSettings: Codable, Hashable {
    public var reasoningEffort: String?
    public var personality: CodexPersonality
    public var approvalPolicy: CodexApprovalPolicy
    public var sandboxPolicy: CodexSandboxPolicy
    public var reasoningSummary: CodexReasoningSummary

    public init(
        reasoningEffort: String? = nil,
        personality: CodexPersonality = .automatic,
        approvalPolicy: CodexApprovalPolicy = .onRequest,
        sandboxPolicy: CodexSandboxPolicy = .automatic,
        reasoningSummary: CodexReasoningSummary = .automatic
    ) {
        self.reasoningEffort = reasoningEffort
        self.personality = personality
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicy = sandboxPolicy
        self.reasoningSummary = reasoningSummary
    }
}

public enum AgentThreadGoalStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case active
    case paused
    case blocked
    case usageLimited
    case budgetLimited
    case complete

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .blocked: return "Blocked"
        case .usageLimited: return "Usage limited"
        case .budgetLimited: return "Budget limited"
        case .complete: return "Complete"
        }
    }
}

public struct AgentThreadGoal: Codable, Hashable {
    public let threadID: String
    public let objective: String
    public var status: AgentThreadGoalStatus
    public let tokenBudget: Int64?
    public let tokensUsed: Int64
    public let timeUsedSeconds: Int64
    public let updatedAt: Int64

    public init(
        threadID: String,
        objective: String,
        status: AgentThreadGoalStatus,
        tokenBudget: Int64? = nil,
        tokensUsed: Int64 = 0,
        timeUsedSeconds: Int64 = 0,
        updatedAt: Int64 = 0
    ) {
        self.threadID = threadID
        self.objective = objective
        self.status = status
        self.tokenBudget = tokenBudget
        self.tokensUsed = tokensUsed
        self.timeUsedSeconds = timeUsedSeconds
        self.updatedAt = updatedAt
    }
}

public struct AgentThread: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var lastMessage: String
    public var activeModel: String
    public var codexSessionID: String?
    public var connectionID: String?
    public var status: AgentThreadStatus
    public var isPinned: Bool
    public var cwd: String?
    public var settings: ThreadSettings

    enum CodingKeys: String, CodingKey {
        case id, title, lastMessage, activeModel, codexSessionID, connectionID, status, isPinned, cwd, settings
    }

    public init(
        id: String,
        title: String,
        lastMessage: String,
        activeModel: String,
        codexSessionID: String? = nil,
        connectionID: String? = nil,
        status: AgentThreadStatus = AgentThreadStatus(),
        isPinned: Bool = false,
        cwd: String? = nil,
        settings: ThreadSettings = ThreadSettings()
    ) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.activeModel = activeModel
        self.codexSessionID = codexSessionID
        self.connectionID = connectionID
        self.status = status
        self.isPinned = isPinned
        self.cwd = cwd
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        lastMessage = try container.decode(String.self, forKey: .lastMessage)
        activeModel = try container.decode(String.self, forKey: .activeModel)
        codexSessionID = try container.decodeIfPresent(String.self, forKey: .codexSessionID)
        connectionID = try container.decodeIfPresent(String.self, forKey: .connectionID)
        status = try container.decodeIfPresent(AgentThreadStatus.self, forKey: .status) ?? AgentThreadStatus()
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        settings = try container.decodeIfPresent(ThreadSettings.self, forKey: .settings) ?? ThreadSettings()
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
