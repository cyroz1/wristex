import Foundation
import Combine

@MainActor
public final class ThreadDetailViewModel: ObservableObject {
    public let thread: AgentThread
    
    @Published public var messages: [ThreadMessage] = []
    @Published public var models: [ModelOption] = []
    @Published public var activeModelId: String
    @Published public var isLoading = false
    @Published public var isSending = false
    @Published public var errorMessage: String? = nil
    
    private let network = NetworkManager.shared
    private var pollingTask: Task<Void, Never>? = nil
    
    public init(thread: AgentThread) {
        self.thread = thread
        self.activeModelId = thread.activeModel
    }
    
    public func loadMessages() async {
        errorMessage = nil
        do {
            self.messages = try await network.fetchMessages(threadId: thread.id)
        } catch {
            self.errorMessage = "Failed to load messages"
        }
    }
    
    public func loadModels() async {
        do {
            self.models = try await network.fetchModels()
        } catch {
            // Silently ignore or show fallback models
            self.models = [
                ModelOption(id: "gpt-4o", name: "GPT-4o"),
                ModelOption(id: "claude-3-5", name: "Claude 3.5"),
                ModelOption(id: "gemini-1-5", name: "Gemini 1.5 Pro")
            ]
        }
    }
    
    public func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        errorMessage = nil
        
        // Optimistically add the message to the view
        let tempMessage = ThreadMessage(sender: "user", content: text, timestamp: Date())
        self.messages.append(tempMessage)
        
        HapticManager.shared.playClick()
        
        do {
            _ = try await network.sendMessage(threadId: thread.id, content: text)
            // Trigger haptic when message successfully sends
            HapticManager.shared.playSuccess()
            
            // Reload message history immediately
            await loadMessages()
        } catch {
            self.errorMessage = "Failed to send message: \(error.localizedDescription)"
            HapticManager.shared.playFailure()
        }
        isSending = false
    }
    
    public func selectModel(_ modelId: String) async {
        do {
            let success = try await network.updateThreadModel(threadId: thread.id, modelId: modelId)
            if success {
                self.activeModelId = modelId
                HapticManager.shared.playSuccess()
            }
        } catch {
            self.errorMessage = "Failed to update model: \(error.localizedDescription)"
            HapticManager.shared.playFailure()
        }
    }
    
    // Polling logic to fetch agent responses dynamically
    public func startPolling() {
        stopPolling()
        
        pollingTask = Task {
            // Initial loads
            await loadMessages()
            await loadModels()
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // Poll every 3 seconds
                if Task.isCancelled { break }
                await loadMessages()
            }
        }
    }
    
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
    
    deinit {
        pollingTask?.cancel()
    }
}
