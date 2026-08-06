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
    private let workspaceOverride: String?
    
    public init(workspacePath: String? = nil) {
        workspaceOverride = workspacePath
    }

    private var workspacePath: String {
        (workspaceOverride ?? ssh.remoteWorkspacePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func loadGitStatus() async {
        isLoading = true
        errorMessage = nil
        gitStatus = nil
        do {
            let workspace = workspacePath
            guard !workspace.isEmpty else {
                throw GitViewModelError.missingWorkspace
            }

            let cmd = "cd \(Shell.quote(workspace)) && git status --porcelain=v1 --branch"
            let stdout = try await ssh.executeCommand(cmd)
            self.gitStatus = try parseGitStatus(stdout)
        } catch {
            self.errorMessage = error.localizedDescription
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
            let workspace = workspacePath
            guard !workspace.isEmpty else {
                errorMessage = GitViewModelError.missingWorkspace.localizedDescription
                isExecutingAction = false
                return
            }

            switch action {
            case .pull:
                cmd = "cd \(Shell.quote(workspace)) && git pull"
            case .push:
                cmd = "cd \(Shell.quote(workspace)) && git push"
            case .commit:
                let message = commitMessage ?? "Automated commit from Wristex"
                cmd = "cd \(Shell.quote(workspace)) && git add . && git commit -m \(Shell.quote(message))"
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

    private func parseGitStatus(_ output: String) throws -> GitStatus {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first(where: { $0.hasPrefix("## ") }) else {
            throw GitViewModelError.invalidStatusOutput
        }

        var branch = String(header.dropFirst(3))
        if let trackingRange = branch.range(of: "...") {
            branch = String(branch[..<trackingRange.lowerBound])
        }
        if branch.isEmpty || branch.hasPrefix("HEAD") {
            branch = "(detached)"
        }

        var ahead = 0
        var behind = 0
        if let metadataStart = header.firstIndex(of: "[") {
            let metadata = String(header[metadataStart...])
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
            for value in metadata.split(separator: ",") {
                let parts = value.split(separator: " ")
                guard parts.count == 2, let count = Int(parts[1]) else { continue }
                if parts[0] == "ahead" { ahead = count }
                if parts[0] == "behind" { behind = count }
            }
        }

        var modifiedFiles: [String] = []
        var untrackedFiles: [String] = []
        for line in lines.dropFirst() where line.count >= 3 {
            let status = String(line.prefix(2))
            let path = String(line.dropFirst(3))
            if status == "??" {
                untrackedFiles.append(path)
            } else {
                modifiedFiles.append(path)
            }
        }

        return GitStatus(
            branch: branch,
            modifiedFiles: modifiedFiles,
            untrackedFiles: untrackedFiles,
            ahead: ahead,
            behind: behind
        )
    }
}

private enum GitViewModelError: LocalizedError {
    case missingWorkspace
    case invalidStatusOutput

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Set the remote workspace in Settings."
        case .invalidStatusOutput:
            return "Git returned an unreadable status."
        }
    }
}
