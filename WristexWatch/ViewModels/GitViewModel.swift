import Foundation
import Combine

@MainActor
public final class GitViewModel: ObservableObject {
    @Published public var gitStatus: GitStatus? = nil
    @Published public var isLoading = false
    @Published public var isExecutingAction = false
    @Published public var errorMessage: String? = nil
    @Published public var actionFeedbackMessage: String? = nil
    
    private let network = NetworkManager.shared
    
    public init() {}
    
    public func loadGitStatus() async {
        isLoading = true
        errorMessage = nil
        do {
            self.gitStatus = try await network.fetchGitStatus()
        } catch {
            self.errorMessage = "Failed to load git status: \(error.localizedDescription)"
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
            let (success, feedback) = try await network.executeGitAction(action: action, commitMessage: commitMessage)
            if success {
                actionFeedbackMessage = feedback
                HapticManager.shared.playSuccess()
                
                // Reload git status immediately to reflect updates
                await loadGitStatus()
            } else {
                errorMessage = "Action failed: \(feedback)"
                HapticManager.shared.playFailure()
            }
        } catch {
            errorMessage = "Git action failed: \(error.localizedDescription)"
            HapticManager.shared.playFailure()
        }
        isExecutingAction = false
    }
}
