import Combine
import Foundation

@MainActor
public final class ChatViewModel: ObservableObject {
    @Published public private(set) var messages: [ChatMessage]
    @Published public private(set) var isSending = false
    @Published public private(set) var isVoiceRecording = false
    @Published public var errorMessage: String?
    @Published public private(set) var modelName: String

    private let store = ChatStore.shared
    private let chat = ChatService.shared

    public init() {
        messages = store.load()
        modelName = chat.model
    }

    public var isConfigured: Bool {
        chat.isConfigured
    }

    public func refreshConfiguration() {
        modelName = chat.model
    }

    public func sendMessage(_ text: String) async {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, !isSending else { return }

        isSending = true
        errorMessage = nil
        let requestHistory = messages + [ChatMessage(role: .user, text: cleanText)]
        messages = requestHistory
        store.save(messages)
        HapticManager.shared.playClick()

        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: ""))

        do {
            let reply = try await chat.send(history: requestHistory) { [weak self] delta in
                guard let self,
                      let index = self.messages.firstIndex(where: { $0.id == assistantID }) else { return }
                self.messages[index].text += delta
            }
            if let index = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[index].text = reply
            }
            store.save(messages)
            HapticManager.shared.playSuccess()
        } catch {
            if let index = messages.firstIndex(where: { $0.id == assistantID }), messages[index].text.isEmpty {
                messages.remove(at: index)
            }
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }

        isSending = false
    }

    public func clearChat() {
        messages = []
        store.clear()
        errorMessage = nil
        HapticManager.shared.playClick()
    }

    public func startVoiceTranscription() async -> Bool {
        guard !isSending, !isVoiceRecording else { return false }
        do {
            try await chat.startVoiceCapture()
            isVoiceRecording = true
            errorMessage = nil
            HapticManager.shared.playStart()
            return true
        } catch {
            errorMessage = "GPT transcription unavailable: " + error.localizedDescription
            HapticManager.shared.playFailure()
            return false
        }
    }

    public func stopVoiceTranscription() async -> String? {
        guard isVoiceRecording else { return nil }
        isVoiceRecording = false
        do {
            let transcript = try await chat.stopVoiceCapture()
            HapticManager.shared.playStop()
            return transcript
        } catch {
            errorMessage = "GPT transcription failed: " + error.localizedDescription
            HapticManager.shared.playFailure()
            return nil
        }
    }

    public func cancelVoiceTranscription() {
        guard isVoiceRecording else { return }
        isVoiceRecording = false
        chat.cancelVoiceCapture()
        HapticManager.shared.playStop()
    }
}
