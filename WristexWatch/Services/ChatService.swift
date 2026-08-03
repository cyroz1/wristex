import Combine
import Foundation

public struct ChatMessage: Codable, Hashable, Identifiable {
    public enum Role: String, Codable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public var text: String
    public let timestamp: Date

    public init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

@MainActor
public final class ChatStore {
    public static let shared = ChatStore()

    private let defaults = UserDefaults.standard
    private let messagesKey = "wristex.chat.messages"

    private init() {}

    public func load() -> [ChatMessage] {
        guard let data = defaults.data(forKey: messagesKey) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    public func save(_ messages: [ChatMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: messagesKey)
    }

    public func clear() {
        defaults.removeObject(forKey: messagesKey)
    }
}

public enum ChatAPIError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpStatus(Int)
    case apiMessage(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add an OpenAI API key in Settings."
        case .invalidResponse:
            return "The Chat API returned an invalid response."
        case let .httpStatus(status):
            switch status {
            case 401: return "The OpenAI API key is invalid."
            case 429: return "The OpenAI API rate limit was reached."
            default: return "OpenAI API error (HTTP \(status))."
            }
        case let .apiMessage(message):
            return message
        }
    }
}

@MainActor
public final class ChatService: ObservableObject {
    public static let shared = ChatService()

    @Published public private(set) var apiKey: String
    @Published public private(set) var model: String

    private let defaults = UserDefaults.standard
    private let modelKey = "wristex.chat.model"
    private let apiKeyAccount = "openai-api-key"
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")!

    private init() {
        apiKey = KeychainStore.read(apiKeyAccount)
        model = defaults.string(forKey: modelKey) ?? "gpt-4o-mini"
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func configure(apiKey: String, model: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = cleanKey
        self.model = cleanModel.isEmpty ? "gpt-4o-mini" : cleanModel
        KeychainStore.write(cleanKey, account: apiKeyAccount)
        defaults.set(self.model, forKey: modelKey)
    }

    public func clearAPIKey() {
        configure(apiKey: "", model: model)
    }

    public func testConnection() async throws {
        guard isConfigured else { throw ChatAPIError.notConfigured }

        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        addHeaders(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ChatAPIError.httpStatus(httpResponse.statusCode)
        }
    }

    public func send(
        history: [ChatMessage],
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard isConfigured else { throw ChatAPIError.notConfigured }
        guard !history.isEmpty else { throw ChatAPIError.invalidResponse }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": history.map { message in
                [
                    "role": message.role.rawValue,
                    "content": [[
                        "type": "input_text",
                        "text": message.text
                    ]]
                ]
            },
            "stream": true,
            "store": false
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ChatAPIError.httpStatus(httpResponse.statusCode)
        }

        var reply = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]",
                  let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else {
                continue
            }

            if type == "response.output_text.delta",
               let delta = event["delta"] as? String,
               !delta.isEmpty {
                reply += delta
                onDelta(delta)
            } else if type == "error" || type == "response.failed" {
                let message = (event["message"] as? String)
                    ?? ((event["error"] as? [String: Any])?["message"] as? String)
                    ?? "The OpenAI API request failed."
                throw ChatAPIError.apiMessage(message)
            } else if type == "response.completed" {
                return reply
            }
        }

        guard !reply.isEmpty else { throw ChatAPIError.invalidResponse }
        return reply
    }

    private func addHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
}
