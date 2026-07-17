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
    
    private let ssh = SSHManager.shared
    private var pollingTask: Task<Void, Never>? = nil
    
    public init(thread: AgentThread) {
        self.thread = thread
        self.activeModelId = thread.activeModel
    }
    
    public func loadMessages() async {
        errorMessage = nil
        do {
            let cmd = """
            mkdir -p ~/.codex && \
            if [ ! -f ~/.codex/messages_\(thread.id).json ]; then \
              echo '[]' > ~/.codex/messages_\(thread.id).json; \
            fi && \
            cat ~/.codex/messages_\(thread.id).json
            """
            let stdout = try await ssh.executeCommand(cmd)
            guard let data = stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let decoder = JSONDecoder()
            self.messages = try decoder.decode([ThreadMessage].self, from: data)
        } catch {
            self.errorMessage = "Failed to load messages: \(error.localizedDescription)"
        }
    }
    
    public func loadModels() async {
        do {
            let cmd = """
            if [ ! -f ~/.codex/models.json ]; then \
              echo '[{"id":"gpt-4o","name":"GPT-4o (Standard)"},{"id":"claude-3-5","name":"Claude 3.5 Sonnet"},{"id":"gemini-1-5","name":"Gemini 1.5 Pro"}]' > ~/.codex/models.json; \
            fi && \
            cat ~/.codex/models.json
            """
            let stdout = try await ssh.executeCommand(cmd)
            guard let data = stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let decoder = JSONDecoder()
            self.models = try decoder.decode([ModelOption].self, from: data)
        } catch {
            // Fallback default options
            self.models = [
                ModelOption(id: "gpt-4o", name: "GPT-4o (Standard)"),
                ModelOption(id: "claude-3-5", name: "Claude 3.5 Sonnet"),
                ModelOption(id: "gemini-1-5", name: "Gemini 1.5 Pro")
            ]
        }
    }
    
    public func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        errorMessage = nil
        
        let tempMessage = ThreadMessage(sender: "user", content: text, timestamp: Date())
        self.messages.append(tempMessage)
        
        HapticManager.shared.playClick()
        
        do {
            let textEscaped = text.replacingOccurrences(of: "'", with: "'\\''")
            // Execute python to append user message AND update lastMessage in threads.json
            let cmd = """
            python3 -c "
            import json, os, datetime
            msg_path = os.path.expanduser('~/.codex/messages_\(thread.id).json')
            thread_path = os.path.expanduser('~/.codex/threads.json')
            
            # 1. Update message log
            try:
                msgs = json.load(open(msg_path))
            except:
                msgs = []
            
            new_msg = {'sender': 'user', 'content': '\(textEscaped)', 'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'}
            msgs.append(new_msg)
            
            with open(msg_path, 'w') as f:
                json.dump(msgs, f)
                
            # 2. Update threads.json metadata
            try:
                threads = json.load(open(thread_path))
                for t in threads:
                    if t['id'] == '\(thread.id)':
                        t['lastMessage'] = '\(textEscaped)'
                with open(thread_path, 'w') as f:
                    json.dump(threads, f)
            except Exception as e:
                pass
                
            # Simulate agent auto-reply creation
            try:
                agent_msg = {'sender': 'agent', 'content': 'Direct SSH action triggered for: \"\(textEscaped)\". Let me process that.', 'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'}
                msgs.append(agent_msg)
                with open(msg_path, 'w') as f:
                    json.dump(msgs, f)
                for t in threads:
                    if t['id'] == '\(thread.id)':
                        t['lastMessage'] = agent_msg['content']
                with open(thread_path, 'w') as f:
                    json.dump(threads, f)
            except:
                pass
            "
            """
            _ = try await ssh.executeCommand(cmd)
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
            let cmd = """
            python3 -c "
            import json, os
            path = os.path.expanduser('~/.codex/threads.json')
            try:
                data = json.load(open(path))
                for t in data:
                    if t['id'] == '\(thread.id)':
                        t['activeModel'] = '\(modelId)'
                with open(path, 'w') as f:
                    json.dump(data, f)
                print('success')
            except Exception as e:
                print('error: ' + str(e))
            "
            """
            let stdout = try await ssh.executeCommand(cmd)
            if stdout.contains("success") {
                self.activeModelId = modelId
                HapticManager.shared.playSuccess()
            } else {
                self.errorMessage = "Host error: \(stdout)"
                HapticManager.shared.playFailure()
            }
        } catch {
            self.errorMessage = "Failed to update model: \(error.localizedDescription)"
            HapticManager.shared.playFailure()
        }
    }
    
    public func startPolling() {
        stopPolling()
        
        pollingTask = Task {
            await loadMessages()
            await loadModels()
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
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
