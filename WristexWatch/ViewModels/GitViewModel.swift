import Foundation
import Combine

@MainActor
public final class GitViewModel: ObservableObject {
    @Published public var gitStatus: GitStatus? = nil
    @Published public var isLoading = false
    @Published public var isExecutingAction = false
    @Published public var errorMessage: String? = nil
    @Published public var actionFeedbackMessage: String? = nil
    
    private let ssh = SSHManager.shared
    
    public init() {}
    
    public func loadGitStatus() async {
        isLoading = true
        errorMessage = nil
        do {
            let cmd = """
            cd \(Shell.quote(ssh.remoteWorkspacePath)) && python3 -c "
            import subprocess, json
            try:
                branch = subprocess.check_output(['git', 'branch', '--show-current']).decode('utf-8').strip()
                
                # Check ahead/behind count
                try:
                    ab_out = subprocess.check_output(['git', 'rev-list', '--left-right', '--count', 'HEAD...@{u}'], stderr=subprocess.DEVNULL).decode('utf-8').strip()
                    ahead, behind = map(int, ab_out.split())
                except:
                    ahead, behind = 0, 0
                
                # Get modified and untracked files
                status_out = subprocess.check_output(['git', 'status', '--porcelain']).decode('utf-8').splitlines()
                modified = []
                untracked = []
                for line in status_out:
                    if line.startswith('??'):
                        untracked.append(line[3:])
                    else:
                        modified.append(line[3:])
                print(json.dumps({
                    'branch': branch,
                    'modifiedFiles': modified,
                    'untrackedFiles': untracked,
                    'ahead': ahead,
                    'behind': behind
                }))
            except Exception as e:
                print(json.dumps({
                    'branch': 'error',
                    'modifiedFiles': [],
                    'untrackedFiles': [],
                    'ahead': 0,
                    'behind': 0,
                    'error': str(e)
                }))
            "
            """
            let stdout = try await ssh.executeCommand(cmd)
            guard let data = stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            let decoder = JSONDecoder()
            self.gitStatus = try decoder.decode(GitStatus.self, from: data)
        } catch {
            self.errorMessage = "SSH status failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    public func pull() async {
        await executeAction(.pull)
    }
    
    public func push() async {
        await executeAction(.push)
    }
    
    public func commit(message: String) async {
        await executeAction(.commit, commitMessage: message)
    }
    
    private func executeAction(_ action: GitAction, commitMessage: String? = nil) async {
        isExecutingAction = true
        errorMessage = nil
        actionFeedbackMessage = nil
        
        HapticManager.shared.playClick()
        
        do {
            let cmd: String
            switch action {
            case .pull:
                cmd = "cd \(Shell.quote(ssh.remoteWorkspacePath)) && git pull"
            case .push:
                cmd = "cd \(Shell.quote(ssh.remoteWorkspacePath)) && git push"
            case .commit:
                let message = commitMessage ?? "Automated commit from Wristex"
                cmd = "cd \(Shell.quote(ssh.remoteWorkspacePath)) && git add . && git commit -m \(Shell.quote(message))"
            }
            
            let stdout = try await ssh.executeCommand(cmd)
            actionFeedbackMessage = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            HapticManager.shared.playSuccess()
            
            // Reload status to reflect changes
            await loadGitStatus()
        } catch {
            errorMessage = "Git action failed: \(error.localizedDescription)"
            HapticManager.shared.playFailure()
        }
        isExecutingAction = false
    }
}
