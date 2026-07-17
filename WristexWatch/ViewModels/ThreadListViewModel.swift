import Foundation
import Combine

@MainActor
public final class ThreadListViewModel: ObservableObject {
    @Published public var threads: [AgentThread] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String? = nil
    
    private let network = NetworkManager.shared
    
    public init() {}
    
    public func loadThreads() async {
        isLoading = true
        errorMessage = nil
        do {
            self.threads = try await network.fetchThreads()
        } catch {
            self.errorMessage = "Failed to load threads: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    public func createNewThread(title: String) async {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let newThread = try await network.createThread(title: title)
            self.threads.insert(newThread, at: 0)
            HapticManager.shared.playSuccess()
        } catch {
            self.errorMessage = "Failed to create thread: \(error.localizedDescription)"
            HapticManager.shared.playFailure()
        }
        isLoading = false
    }
}
