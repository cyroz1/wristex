import Foundation
import Combine

@MainActor
public final class ThreadListViewModel: ObservableObject {
    @Published public var threads: [AgentThread] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String? = nil
    
    private let ssh = SSHManager.shared
    
    public init() {}
    
    public func loadThreads() async {
        isLoading = true
        errorMessage = nil
        do {
            // Ensure .codex folder exists, make sure threads.json exists, then read it
            let cmd = """
            mkdir -p ~/.codex && \
            if [ ! -f ~/.codex/threads.json ]; then \
              echo '[{"id":"thread-1","title":"Build login layout","lastMessage":"Should we add a FaceID toggle?","activeModel":"gemini-1-5"}]' > ~/.codex/threads.json; \
            fi && \
            cat ~/.codex/threads.json
            """
            let stdout = try await ssh.executeCommand(cmd)
            guard let data = stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let decoder = JSONDecoder()
            self.threads = try decoder.decode([AgentThread].self, from: data)
        } catch {
            self.errorMessage = "SSH load failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    public func createNewThread(title: String) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let titleEscaped = title.replacingOccurrences(of: "'", with: "'\\''")
            // Execute python3 directly on remote host to read, append, and save threads
            let cmd = """
            python3 -c "
            import json, os, uuid
            path = os.path.expanduser('~/.codex/threads.json')
            try:
                data = json.load(open(path))
            except:
                data = []
            new_id = 'thread-' + str(uuid.uuid4())[:8]
            new_t = {'id': new_id, 'title': '\(titleEscaped)', 'lastMessage': 'Thread created.', 'activeModel': 'gpt-4o'}
            data.insert(0, new_t)
            with open(path, 'w') as f:
                json.dump(data, f)
            print(json.dumps(new_t))
            "
            """
            let stdout = try await ssh.executeCommand(cmd)
            guard let data = stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let decoder = JSONDecoder()
            let newThread = try decoder.decode(AgentThread.self, from: data)
            
            self.threads.insert(newThread, at: 0)
            HapticManager.shared.playSuccess()
        } catch {
            self.errorMessage = "Failed to create thread: \(error.localizedDescription)"
            HapticManager.shared.playFailure()
        }
        isLoading = false
    }
}
