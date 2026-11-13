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
        if ScreenshotMode.isEnabled {
            gitStatus = ScreenshotFixtures.gitStatus
        }
    }

    public var workspacePath: String {
        let override = workspaceOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? ssh.remoteWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines) : override
    }
    
    public func loadGitStatus() async {
        guard !ScreenshotMode.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        gitStatus = nil
        do {
            let workspace = workspacePath
            guard !workspace.isEmpty else {
                throw GitViewModelError.missingWorkspace
            }

            let cmd = "cd \(Shell.quotePath(workspace)) && git status --porcelain=v1 --branch --no-renames --untracked-files=all -z"
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
                cmd = "cd \(Shell.quotePath(workspace)) && git pull"
            case .push:
                if let status = gitStatus, !status.hasUpstream {
                    guard status.hasCommit, !status.isDetached else {
                        throw GitViewModelError.pushNeedsBranch
                    }
                    let remote = try await preferredPushRemote(workspace: workspace, branch: status.branch)
                    cmd = "cd \(Shell.quotePath(workspace)) && git push --set-upstream \(Shell.quote(remote)) HEAD"
                } else {
                    cmd = "cd \(Shell.quotePath(workspace)) && git push"
                }
            case .commit:
                let message = commitMessage ?? "Automated commit from Wristex"
                cmd = "cd \(Shell.quotePath(workspace)) && git add . && git commit -m \(Shell.quote(message))"
            }
            
            let stdout = try await ssh.executeCommand(cmd)
            let summary = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                actionFeedbackMessage = "\(action.label) complete."
            } else if summary.count > 240 {
                actionFeedbackMessage = String(summary.prefix(237)) + "…"
            } else {
                actionFeedbackMessage = summary
            }
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
        guard let headerEnd = output.firstIndex(of: "\0") else {
            throw GitViewModelError.invalidStatusOutput
        }
        let header = String(output[..<headerEnd])
        guard header.hasPrefix("## ") else { throw GitViewModelError.invalidStatusOutput }

        var branch = String(header.dropFirst(3))
        let hasCommit = !branch.hasPrefix("No commits yet on ")
        let hasUpstream = branch.range(of: "...") != nil
        if let trackingRange = branch.range(of: "...") {
            branch = String(branch[..<trackingRange.lowerBound])
        }
        if branch.hasPrefix("No commits yet on ") {
            branch = String(branch.dropFirst("No commits yet on ".count))
        }
        let isDetached = branch.isEmpty || branch.hasPrefix("HEAD")
        if isDetached {
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
        let recordsStart = output.index(after: headerEnd)
        let records = output[recordsStart...].split(separator: "\0", omittingEmptySubsequences: true)
        for record in records where record.count >= 3 {
            let line = String(record)
            let status = String(line.prefix(2))
            let path = String(line.dropFirst(3))
            guard !path.isEmpty else { continue }
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
            behind: behind,
            hasUpstream: hasUpstream,
            hasCommit: hasCommit,
            isDetached: isDetached
        )
    }

    private func preferredPushRemote(workspace: String, branch: String) async throws -> String {
        let branchPushRemote = Shell.quote("branch.\(branch).pushRemote")
        let branchRemote = Shell.quote("branch.\(branch).remote")
        let command = "cd \(Shell.quotePath(workspace)) && { git config --get \(branchPushRemote) 2>/dev/null || git config --get remote.pushDefault 2>/dev/null || git config --get \(branchRemote) 2>/dev/null || git remote; }"
        let remotes = try await ssh.executeCommand(command)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !remotes.isEmpty else { throw GitViewModelError.noRemote }
        if remotes.count == 1 { return remotes[0] }
        if remotes.contains("origin") { return "origin" }
        throw GitViewModelError.ambiguousRemotes
    }
}

private enum GitViewModelError: LocalizedError {
    case missingWorkspace
    case invalidStatusOutput
    case pushNeedsBranch
    case noRemote
    case ambiguousRemotes

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Set the remote workspace in Settings."
        case .invalidStatusOutput:
            return "Git returned an unreadable status."
        case .pushNeedsBranch:
            return "Commit to a named branch before pushing."
        case .noRemote:
            return "Add a Git remote before publishing this branch."
        case .ambiguousRemotes:
            return "Set remote.pushDefault or branch pushRemote to choose a remote."
        }
    }
}

private extension GitAction {
    var label: String {
        switch self {
        case .pull: return "Pull"
        case .push: return "Push"
        case .commit: return "Commit"
        }
    }
}
