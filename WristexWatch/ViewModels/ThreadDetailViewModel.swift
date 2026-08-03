import Combine
import Foundation

@MainActor
public final class ThreadDetailViewModel: ObservableObject {
    @Published public private(set) var thread: AgentThread
    @Published public var messages: [ThreadMessage] = []
    @Published public var models: [ModelOption] = []
    @Published public var activeModelId: String
    @Published public var isLoading = false
    @Published public var isSending = false
    @Published public var isVoiceRecording = false
    @Published public var errorMessage: String?

    private let store = ThreadStore.shared
    private let codex = RemoteCodexService.shared
    private var streamingMessageID: UUID?

    public init(thread: AgentThread) {
        self.thread = thread
        activeModelId = thread.activeModel
    }

    public func loadMessages() async {
        do {
            let remoteMessages = try await codex.readMessages(threadID: thread.id)
            messages = remoteMessages
            store.save(remoteMessages, for: thread.id)
        } catch {
            messages = store.messages(for: thread.id)
            errorMessage = error.localizedDescription
        }
    }

    public func loadModels() async {
        do {
            let remoteModels = try await codex.loadModels()
            models = [ModelOption(id: "default", name: "Host Default")] + remoteModels
        } catch {
            models = [ModelOption(id: "default", name: "Host Default")]
        }
    }

    public func sendMessage(_ text: String) async {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !isSending else { return }

        isSending = true
        errorMessage = nil
        messages.append(ThreadMessage(sender: "user", content: cleanText, timestamp: Date()))
        store.save(messages, for: thread.id)
        HapticManager.shared.playClick()

        do {
            let result = try await codex.send(cleanText, thread: thread)
            if let streamingMessageID,
               let index = messages.firstIndex(where: { $0.id == streamingMessageID }) {
                messages[index] = ThreadMessage(
                    id: streamingMessageID,
                    sender: "agent",
                    content: result.reply,
                    timestamp: Date()
                )
            } else {
                messages.append(ThreadMessage(sender: "agent", content: result.reply, timestamp: Date()))
            }
            self.streamingMessageID = nil
            thread.codexSessionID = result.sessionID
            thread.lastMessage = result.reply
            store.save(messages, for: thread.id)
            store.save(thread)
            HapticManager.shared.playSuccess()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }
        isSending = false
    }

    public func selectModel(_ modelId: String) async {
        do {
            try await codex.updateThreadModel(thread.id, modelID: modelId)
            activeModelId = modelId
            thread.activeModel = modelId
            store.save(thread)
            HapticManager.shared.playSuccess()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }
    }

    public func interruptTurn() async {
        do {
            try await codex.interrupt(threadID: thread.id)
            isSending = false
            streamingMessageID = nil
            HapticManager.shared.playClick()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startVoiceTranscription() async -> Bool {
        do {
            try await codex.startVoiceTranscription(threadID: thread.id)
            isVoiceRecording = true
            HapticManager.shared.playStart()
            return true
        } catch {
            errorMessage = "GPT voice unavailable: " + error.localizedDescription
            HapticManager.shared.playFailure()
            return false
        }
    }

    public func stopVoiceTranscription() async {
        do {
            try await codex.stopVoiceTranscription(threadID: thread.id)
            isVoiceRecording = false
            HapticManager.shared.playStop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startPolling() {
        codex.setNotificationHandler { [weak self] method, params in
            self?.handleRemoteNotification(method: method, params: params)
        }
        Task {
            await loadMessages()
            await loadModels()
        }
    }

    public func stopPolling() {
        codex.setNotificationHandler(nil)
        if isVoiceRecording {
            Task {
                try? await codex.stopVoiceTranscription(threadID: thread.id)
            }
            isVoiceRecording = false
        }
    }

    private func handleRemoteNotification(method: String, params: [String: Any]) {
        guard params["threadId"] as? String == thread.id else { return }
        if method == "thread/realtime/transcript/done",
           params["role"] as? String == "user",
           let text = params["text"] as? String {
            isVoiceRecording = false
            let dictatedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dictatedText.isEmpty {
                Task { await sendMessage(dictatedText) }
            }
            return
        }
        guard method == "item/agentMessage/delta",
              let delta = params["delta"] as? String,
              !delta.isEmpty else {
            return
        }

        if let streamingMessageID,
           let index = messages.firstIndex(where: { $0.id == streamingMessageID }) {
            let current = messages[index]
            messages[index] = ThreadMessage(
                id: streamingMessageID,
                sender: "agent",
                content: current.content + delta,
                timestamp: current.timestamp
            )
        } else {
            let id = UUID()
            streamingMessageID = id
            messages.append(ThreadMessage(id: id, sender: "agent", content: delta, timestamp: Date()))
        }
        store.save(messages, for: thread.id)
    }
}
