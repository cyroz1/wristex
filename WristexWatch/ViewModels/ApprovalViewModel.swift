import Foundation
import Combine

@MainActor
public final class ApprovalViewModel: ObservableObject {
    @Published public var approvals: [ApprovalRequest] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String? = nil
    
    private let network = NetworkManager.shared
    private var pollingTask: Task<Void, Never>? = nil
    
    public init() {}
    
    public func loadApprovals() async {
        errorMessage = nil
        do {
            self.approvals = try await network.fetchApprovals()
        } catch {
            self.errorMessage = "Failed to load approvals: \(error.localizedDescription)"
        }
    }
    
    public func respond(id: String, approve: Bool) async {
        isLoading = true
        errorMessage = nil
        
        // Play haptic for response action
        if approve {
            HapticManager.shared.playSuccess()
        } else {
            HapticManager.shared.playFailure()
        }
        
        do {
            let success = try await network.respondToApproval(id: id, approved: approve)
            if success {
                // Optimistically remove from list
                self.approvals.removeAll { $0.id == id }
            } else {
                self.errorMessage = "Action response was not confirmed by agent server."
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
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Poll every 2 seconds for prompts
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
