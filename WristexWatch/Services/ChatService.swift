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
    @Published public private(set) var availableModels: [String] = []

    private let defaults = UserDefaults.standard
    private let modelKey = "wristex.chat.model"
    private let apiKeyAccount = "openai-api-key"
    private static let debugAPIKeyEnvironment = "WRISTEX_OPENAI_API_KEY"
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let transcriptionEndpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")!
    private let transcriptionModel = "gpt-transcribe"
    private let maxVoiceBytes = 20 * 1024 * 1024
    private var voiceCapture: WatchVoiceCapture?
    private var voiceData = Data()
    private var voiceSampleRate = 16_000
    private var voiceChannels = 1

    private init() {
        #if DEBUG
        let injectedAPIKey = ProcessInfo.processInfo.environment[Self.debugAPIKeyEnvironment]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        #else
        let injectedAPIKey: String? = nil
        #endif

        apiKey = injectedAPIKey ?? KeychainStore.read(apiKeyAccount)
        model = defaults.string(forKey: modelKey) ?? "gpt-4o-mini"

        if let injectedAPIKey {
            KeychainStore.write(injectedAPIKey, account: apiKeyAccount)
        }
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func configure(apiKey: String, model: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanKey != self.apiKey {
            availableModels = []
        }
        self.apiKey = cleanKey
        self.model = cleanModel.isEmpty ? "gpt-4o-mini" : cleanModel
        KeychainStore.write(cleanKey, account: apiKeyAccount)
        defaults.set(self.model, forKey: modelKey)
    }

    public func clearAPIKey() {
        configure(apiKey: "", model: model)
    }

    public func startVoiceCapture() async throws {
        guard isConfigured else { throw ChatAPIError.notConfigured }
        guard voiceCapture == nil else { return }
        guard await WatchVoiceCapture.requestPermission() else {
            throw ChatAPIError.apiMessage("Microphone access was denied.")
        }

        voiceData.removeAll(keepingCapacity: true)
        voiceSampleRate = 16_000
        voiceChannels = 1

        let capture = WatchVoiceCapture()
        capture.onAudio = { [weak self] data, sampleRate, channels, _ in
            guard let self, self.voiceData.count < self.maxVoiceBytes else { return }
            self.voiceData.append(data.prefix(self.maxVoiceBytes - self.voiceData.count))
            self.voiceSampleRate = sampleRate
            self.voiceChannels = channels
        }

        do {
            try capture.start()
            voiceCapture = capture
        } catch {
            capture.stop()
            throw error
        }
    }

    public func stopVoiceCapture() async throws -> String {
        guard let capture = voiceCapture else {
            throw ChatAPIError.invalidResponse
        }

        capture.stop()
        voiceCapture = nil
        let pcm = voiceData
        let sampleRate = voiceSampleRate
        let channels = voiceChannels
        voiceData.removeAll(keepingCapacity: false)

        guard !pcm.isEmpty else { throw ChatAPIError.invalidResponse }
        let wav = makeWAV(from: pcm, sampleRate: sampleRate, channels: channels)
        return try await transcribe(wav)
    }

    public func cancelVoiceCapture() {
        voiceCapture?.stop()
        voiceCapture = nil
        voiceData.removeAll(keepingCapacity: false)
    }

    public func refreshAvailableModels() async throws -> [String] {
        guard isConfigured else { throw ChatAPIError.notConfigured }

        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        addHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let message = Self.apiErrorMessage(from: data) {
                throw ChatAPIError.apiMessage(message)
            }
            throw ChatAPIError.httpStatus(httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(ModelListResponse.self, from: data)
        let models = payload.data
            .filter { Self.isTextChatModel($0.id) }
            .sorted {
                if $0.created != $1.created { return $0.created > $1.created }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
            .prefix(5)
            .map(\.id)

        guard !models.isEmpty else {
            throw ChatAPIError.apiMessage("No text chat models are available for this API key.")
        }

        availableModels = models
        return models
    }

    public func testConnection() async throws {
        _ = try await refreshAvailableModels()
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
                var item: [String: Any] = [
                    "role": message.role.rawValue,
                    "content": [[
                        "type": message.role == .assistant ? "output_text" : "input_text",
                        "text": message.text
                    ]]
                ]
                if message.role == .assistant {
                    item["type"] = "message"
                }
                return item
            },
            "tools": [[
                "type": "web_search"
            ]],
            "stream": true,
            "store": false
        ])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            if let message = Self.apiErrorMessage(from: errorData) {
                throw ChatAPIError.apiMessage(message)
            }
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

    private func transcribe(_ wav: Data) async throws -> String {
        guard isConfigured else { throw ChatAPIError.notConfigured }

        let boundary = "WristexBoundary-" + UUID().uuidString
        var request = URLRequest(url: transcriptionEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendField(name: "model", value: transcriptionModel, boundary: boundary, to: &body)
        body.append(Data(("--" + boundary + "\r\n").utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"wristex.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data(("\r\n--" + boundary + "--\r\n").utf8))
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ChatAPIError.apiMessage(message)
            }
            throw ChatAPIError.httpStatus(httpResponse.statusCode)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatAPIError.invalidResponse
        }
        return text
    }

    private func appendField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append(Data(("--" + boundary + "\r\n").utf8))
        body.append(Data(("Content-Disposition: form-data; name=\"" + name + "\"\r\n\r\n").utf8))
        body.append(Data((value + "\r\n").utf8))
    }

    private func makeWAV(from pcm: Data, sampleRate: Int, channels: Int) -> Data {
        let safeSampleRate = max(sampleRate, 8_000)
        let safeChannels = max(channels, 1)
        let byteRate = safeSampleRate * safeChannels * 2
        let blockAlign = safeChannels * 2
        var wav = Data()
        wav.append(Data("RIFF".utf8))
        appendLittleEndian(UInt32(pcm.count + 36), to: &wav)
        wav.append(Data("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16), to: &wav)
        appendLittleEndian(UInt16(1), to: &wav)
        appendLittleEndian(UInt16(safeChannels), to: &wav)
        appendLittleEndian(UInt32(safeSampleRate), to: &wav)
        appendLittleEndian(UInt32(byteRate), to: &wav)
        appendLittleEndian(UInt16(blockAlign), to: &wav)
        appendLittleEndian(UInt16(16), to: &wav)
        wav.append(Data("data".utf8))
        appendLittleEndian(UInt32(pcm.count), to: &wav)
        wav.append(pcm)
        return wav
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func addHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private static func isTextChatModel(_ id: String) -> Bool {
        let normalizedID = id.lowercased()
        let nonChatMarkers = [
            "embedding",
            "moderation",
            "whisper",
            "transcribe",
            "tts",
            "dall-e",
            "image",
            "sora",
            "realtime",
            "audio"
        ]
        return !nonChatMarkers.contains { normalizedID.contains($0) }
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String,
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private struct ModelListResponse: Decodable {
        let data: [APIModel]
    }

    private struct APIModel: Decodable {
        let id: String
        let created: Int
    }
}
