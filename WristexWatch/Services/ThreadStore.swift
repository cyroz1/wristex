import Foundation

@MainActor
final class ThreadStore {
    static let shared = ThreadStore()

    private let defaults = UserDefaults.standard
    private let threadsKey = "wristex_threads_v2"
    private let messagesPrefix = "wristex_messages_v2_"

    private init() {}

    func threads(for connectionID: String) -> [AgentThread] {
        guard let data = defaults.data(forKey: threadsKey),
              let saved = try? decoder.decode([AgentThread].self, from: data) else {
            return []
        }
        return saved.filter { $0.connectionID == connectionID }
    }

    func save(_ thread: AgentThread) {
        var all = allThreads()
        if let index = all.firstIndex(where: { $0.id == thread.id }) {
            all[index] = thread
        } else {
            all.insert(thread, at: 0)
        }
        if let data = try? encoder.encode(all) {
            defaults.set(data, forKey: threadsKey)
        }
    }

    func messages(for threadID: String) -> [ThreadMessage] {
        guard let data = defaults.data(forKey: messagesPrefix + threadID),
              let messages = try? decoder.decode([ThreadMessage].self, from: data) else {
            return []
        }
        return messages
    }

    func save(_ messages: [ThreadMessage], for threadID: String) {
        if let data = try? encoder.encode(messages) {
            defaults.set(data, forKey: messagesPrefix + threadID)
        }
    }

    private func allThreads() -> [AgentThread] {
        guard let data = defaults.data(forKey: threadsKey) else { return [] }
        return (try? decoder.decode([AgentThread].self, from: data)) ?? []
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
