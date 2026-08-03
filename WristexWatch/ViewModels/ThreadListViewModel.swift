import Combine
import Foundation

@MainActor
public final class ThreadListViewModel: ObservableObject {
    @Published public var threads: [AgentThread] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String?

    private let ssh = SSHManager.shared
    private let store = ThreadStore.shared
    private let codex = RemoteCodexService.shared

    public init() {}

    public func loadThreads() async {
        isLoading = true
        errorMessage = nil
        do {
            let remoteThreads = try await codex.listThreads()
            threads = remoteThreads
            remoteThreads.forEach { store.save($0) }
        } catch {
            // Keep the last known local list visible when the watch is offline.
            threads = store.threads(for: ssh.connectionID)
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func createNewThread(title: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        do {
            let thread = try await codex.createThread(title: cleanTitle)
            store.save(thread)
            threads.insert(thread, at: 0)
            HapticManager.shared.playSuccess()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }
    }

    public func archive(_ thread: AgentThread) async {
        do {
            try await codex.archiveThread(thread.id)
            threads.removeAll { $0.id == thread.id }
            HapticManager.shared.playSuccess()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }
    }

    public func delete(_ thread: AgentThread) async {
        do {
            try await codex.deleteThread(thread.id)
            threads.removeAll { $0.id == thread.id }
            HapticManager.shared.playSuccess()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
        }
    }
}
