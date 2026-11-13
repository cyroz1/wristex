import Combine
import Foundation

@MainActor
public final class ThreadDetailViewModel: ObservableObject {
    @Published public private(set) var thread: AgentThread
    @Published public var messages: [ThreadMessage] = []
    @Published public var models: [ModelOption] = []
    @Published public var activeModelId: String
    @Published public var settings = ThreadSettings()
    @Published public var goal: AgentThreadGoal?
    @Published public var isLoading = false
    @Published public var isSending = false
    @Published public var isVoiceRecording = false
    @Published public private(set) var isStoppingVoice = false
    @Published public private(set) var voiceTranscript = ""
    @Published public var errorMessage: String?

    private let store = ThreadStore.shared
    private let codex = RemoteCodexService.shared
    private let chat = ChatService.shared
    private var streamingMessageID: UUID?
    private var streamingMessageIDs: [String: UUID] = [:]

    public init(thread: AgentThread) {
        self.thread = thread
        activeModelId = thread.activeModel
        settings = thread.settings
        if ScreenshotMode.isEnabled {
            messages = ScreenshotFixtures.threadMessages
            models = ScreenshotFixtures.models
            goal = ScreenshotFixtures.goal
        }
    }

    public func loadMessages() async {
        guard !ScreenshotMode.isEnabled else { return }
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
        guard !ScreenshotMode.isEnabled else { return }
        do {
            let remoteModels = try await codex.loadModels()
            models = [ModelOption(id: "default", name: "Host Default")] + remoteModels
        } catch {
            models = [ModelOption(id: "default", name: "Host Default")]
        }
    }

    public var reasoningEffortOptions: [String] {
        let advertised = models.first(where: { $0.id == activeModelId })?.reasoningEfforts ?? []
        if advertised.isEmpty {
            return ["default", "low", "medium", "high"]
        }
        return ["default"] + advertised.filter { $0 != "default" }
    }

    public func sendMessage(_ text: String) async {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !isSending else { return }

        if cleanText == voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines) {
            voiceTranscript = ""
        }
        clearStreamingMessageState()
        isSending = true
        errorMessage = nil
        messages.append(ThreadMessage(sender: "user", content: cleanText, timestamp: Date()))
        store.save(messages, for: thread.id)
        HapticManager.shared.playClick()

        do {
            updateStatus(AgentThreadStatus(kind: .active))
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
            self.streamingMessageIDs.removeAll()
            thread.codexSessionID = result.sessionID
            thread.lastMessage = result.reply
            updateStatus(AgentThreadStatus(kind: .idle))
            store.save(messages, for: thread.id)
            store.save(thread)
            HapticManager.shared.playSuccess()
        } catch {
            clearStreamingMessageState()
            store.save(messages, for: thread.id)
            updateStatus(AgentThreadStatus(kind: .systemError))
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }
        isSending = false
    }

    public func selectModel(_ modelId: String) async {
        activeModelId = modelId
        thread.activeModel = modelId
        store.save(thread)
        HapticManager.shared.playSuccess()
    }

    public func updateSettings(_ newSettings: ThreadSettings) async {
        settings = newSettings
        thread.settings = newSettings
        store.save(thread)
        HapticManager.shared.playSuccess()
    }

    public func updateFolder(_ folder: String) async {
        let cleanFolder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        thread.cwd = cleanFolder.isEmpty ? nil : cleanFolder
        store.save(thread)
        HapticManager.shared.playSuccess()
    }

    public func clearError() {
        errorMessage = nil
    }

    public func setGoal(_ objective: String) async {
        let cleanObjective = objective.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanObjective.isEmpty else { return }
        do {
            goal = try await codex.setGoal(threadID: thread.id, objective: cleanObjective)
            HapticManager.shared.playSuccess()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }
    }

    public func clearGoal() async {
        do {
            try await codex.clearGoal(threadID: thread.id)
            goal = nil
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
            clearStreamingMessageState()
            store.save(messages, for: thread.id)
            updateStatus(AgentThreadStatus(kind: .idle))
            HapticManager.shared.playClick()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func startVoiceTranscription() async -> Bool {
        guard !isSending, !isVoiceRecording else { return false }
        do {
            try await chat.startVoiceCapture()
            isVoiceRecording = true
            HapticManager.shared.playStart()
            return true
        } catch {
            errorMessage = "Voice transcription unavailable: " + error.localizedDescription
            HapticManager.shared.playFailure()
            return false
        }
    }

    public func stopVoiceTranscription() async -> Bool {
        guard isVoiceRecording, !isStoppingVoice else { return false }
        isStoppingVoice = true
        defer { isStoppingVoice = false }
        do {
            let transcript = try await chat.stopVoiceCapture()
            isVoiceRecording = false
            let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTranscript.isEmpty {
                let existingTranscript = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                voiceTranscript = existingTranscript.isEmpty
                    ? cleanTranscript
                    : existingTranscript + " " + cleanTranscript
            }
            HapticManager.shared.playStop()
            if cleanTranscript.isEmpty {
                errorMessage = "No speech was recognized."
                return false
            }
            return true
        } catch {
            isVoiceRecording = false
            errorMessage = "Voice transcription failed: " + error.localizedDescription
            HapticManager.shared.playFailure()
            return false
        }
    }

    public func startPolling() {
        guard !ScreenshotMode.isEnabled else { return }
        codex.setNotificationHandler { [weak self] method, params in
            self?.handleRemoteNotification(method: method, params: params)
        }
        Task {
            await loadMessages()
            await loadModels()
            goal = try? await codex.loadGoal(threadID: thread.id)
        }
    }

    public func stopPolling() {
        codex.setNotificationHandler(nil)
        if isVoiceRecording {
            chat.cancelVoiceCapture()
            isVoiceRecording = false
        }
        voiceTranscript = ""
    }

    private func handleRemoteNotification(method: String, params: [String: Any]) {
        guard params["threadId"] as? String == thread.id else { return }
        if method == "thread/status/changed" {
            updateStatus(status(from: params["status"]))
            return
        }
        if method == "thread/goal/updated" {
            Task { goal = try? await codex.loadGoal(threadID: thread.id) }
            return
        }
        if method == "turn/started" {
            if !isSending { clearStreamingMessageState() }
            updateStatus(AgentThreadStatus(kind: .active))
            return
        }
        if method == "turn/completed" {
            updateStatus(AgentThreadStatus(kind: .idle))
            store.save(messages, for: thread.id)
            if !isSending { clearStreamingMessageState() }
            return
        }
        guard method == "item/agentMessage/delta",
              let delta = params["delta"] as? String,
              let itemID = params["itemId"] as? String,
              let turnID = params["turnId"] as? String,
              !delta.isEmpty else {
            return
        }

        let streamKey = turnID + ":" + itemID
        if let messageID = streamingMessageIDs[streamKey],
           let index = messages.firstIndex(where: { $0.id == messageID }) {
            let current = messages[index]
            messages[index] = ThreadMessage(
                id: messageID,
                sender: "agent",
                content: current.content + delta,
                timestamp: current.timestamp
            )
        } else {
            let id = UUID()
            streamingMessageIDs[streamKey] = id
            streamingMessageID = id
            messages.append(ThreadMessage(id: id, sender: "agent", content: delta, timestamp: Date()))
        }
    }

    private func clearStreamingMessageState() {
        streamingMessageID = nil
        streamingMessageIDs.removeAll()
    }

    private func updateStatus(_ status: AgentThreadStatus) {
        thread.status = status
        store.save(thread)
    }

    private func status(from value: Any?) -> AgentThreadStatus {
        guard let raw = value as? [String: Any],
              let type = raw["type"] as? String,
              let kind = AgentThreadStatusKind(rawValue: type) else {
            return AgentThreadStatus()
        }
        let flags = (raw["activeFlags"] as? [String] ?? [])
            .compactMap(AgentThreadActiveFlag.init(rawValue:))
        return AgentThreadStatus(kind: kind, activeFlags: flags)
    }
}
