import Foundation
import Combine

@MainActor
public final class ApprovalViewModel: ObservableObject {
    @Published public var approvals: [ApprovalRequest] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String? = nil
    
    private let ssh = SSHManager.shared
    private var pollingTask: Task<Void, Never>? = nil
    
    public init() {}
    
    public func loadApprovals() async {
        errorMessage = nil
        do {
            let cmd = """
            mkdir -p ~/.codex && \
            if [ ! -f ~/.codex/pending_approvals.json ]; then \
              echo '[]' > ~/.codex/pending_approvals.json; \
            fi && \
            cat ~/.codex/pending_approvals.json
            """
            let stdout = try await ssh.executeCommand(cmd)
            guard let data = stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let decoder = JSONDecoder()
            self.approvals = try decoder.decode([ApprovalRequest].self, from: data)
        } catch {
            self.errorMessage = "Failed to load approvals: \(error.localizedDescription)"
        }
    }
    
    public func respond(id: String, approve: Bool) async {
        isLoading = true
        errorMessage = nil
        
        if approve {
            HapticManager.shared.playSuccess()
        } else {
            HapticManager.shared.playFailure()
        }
        
        do {
            let cmd = """
            python3 -c "
            import json, os, datetime
            path = os.path.expanduser('~/.codex/pending_approvals.json')
            resp_dir = os.path.expanduser('~/.codex/responses')
            
            # 1. Update pending list
            try:
                approvals = json.load(open(path))
            except:
                approvals = []
            
            filtered = [a for a in approvals if a['id'] != '\(id)']
            with open(path, 'w') as f:
                json.dump(filtered, f)
                
            # 2. Write response log
            os.makedirs(resp_dir, exist_ok=True)
            resp_file = os.path.join(resp_dir, '\(id).json')
            with open(resp_file, 'w') as f:
                json.dump({'approved': \(approve ? "True" : "False"), 'timestamp': datetime.datetime.utcnow().isoformat() + 'Z'}, f)
                
            print('success')
            "
            """
            let stdout = try await ssh.executeCommand(cmd)
            if stdout.contains("success") {
                self.approvals.removeAll { $0.id == id }
            } else {
                self.errorMessage = "Response execution failed: \(stdout)"
            }
        } catch {
            self.errorMessage = "Error sending decision: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    public func startPolling() {
        stopPolling()
        pollingTask = Task {
            await loadApprovals()
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                await loadApprovals()
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
