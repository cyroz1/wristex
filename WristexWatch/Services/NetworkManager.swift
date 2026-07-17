import Foundation
import Combine

public final class NetworkManager: ObservableObject {
    public static let shared = NetworkManager()
    
    // Published properties so SwiftUI views update if settings change
    @Published public var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "wristex_base_url")
        }
    }
    
    @Published public var authToken: String {
        didSet {
            UserDefaults.standard.set(authToken, forKey: "wristex_auth_token")
        }
    }
    
    private init() {
        // Default to localhost:3000 for simulator testing
        self.baseURL = UserDefaults.standard.string(forKey: "wristex_base_url") ?? "http://localhost:3000"
        self.authToken = UserDefaults.standard.string(forKey: "wristex_auth_token") ?? ""
    }
    
    // MARK: - API Helpers
    
    private func createRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard let cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let base = URL(string: cleanBase) else {
            throw URLError(.badURL)
        }
        
        let url = base.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10.0
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = body
        return request
    }
    
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
        
        let decoder = JSONDecoder()
        // We handle ISO8601 formatting or standard timestamp mappings inside decoder or models
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: - Threads & Messages
    
    public func fetchThreads() async throws -> [AgentThread] {
        let request = try createRequest(path: "api/threads", method: "GET")
        return try await execute(request)
    }
    
    public func createThread(title: String) async throws -> AgentThread {
        let payload = ["title": title]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try createRequest(path: "api/threads", method: "POST", body: body)
        return try await execute(request)
    }
    
    public func fetchMessages(threadId: String) async throws -> [ThreadMessage] {
        let request = try createRequest(path: "api/threads/\(threadId)/messages", method: "GET")
        return try await execute(request)
    }
    
    public func sendMessage(threadId: String, content: String) async throws -> ThreadMessage {
        let payload = ["content": content]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try createRequest(path: "api/threads/\(threadId)/messages", method: "POST", body: body)
        return try await execute(request)
    }
    
    // MARK: - Approvals
    
    public func fetchApprovals() async throws -> [ApprovalRequest] {
        let request = try createRequest(path: "api/approvals", method: "GET")
        return try await execute(request)
    }
    
    public func respondToApproval(id: String, approved: Bool) async throws -> Bool {
        let payload = ["approved": approved]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try createRequest(path: "api/approvals/\(id)/respond", method: "POST", body: body)
        
        struct Response: Codable {
            let success: Bool
        }
        
        let res: Response = try await execute(request)
        return res.success
    }
    
    // MARK: - Git Actions
    
    public func fetchGitStatus() async throws -> GitStatus {
        let request = try createRequest(path: "api/git/status", method: "GET")
        return try await execute(request)
    }
    
    public func executeGitAction(action: GitAction, commitMessage: String? = nil) async throws -> (success: Bool, message: String) {
        var payload: [String: Any] = ["action": action.rawValue]
        if let msg = commitMessage {
            payload["commitMessage"] = msg
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try createRequest(path: "api/git/action", method: "POST", body: body)
        
        struct Response: Codable {
            let success: Bool
            let message: String
        }
        
        let res: Response = try await execute(request)
        return (res.success, res.message)
    }
    
    // MARK: - Models / Intelligence
    
    public func fetchModels() async throws -> [ModelOption] {
        let request = try createRequest(path: "api/models", method: "GET")
        return try await execute(request)
    }
    
    public func updateThreadModel(threadId: String, modelId: String) async throws -> Bool {
        let payload = ["model": modelId]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try createRequest(path: "api/threads/\(threadId)/model", method: "POST", body: body)
        
        struct Response: Codable {
            let success: Bool
        }
        
        let res: Response = try await execute(request)
        return res.success
    }
}
