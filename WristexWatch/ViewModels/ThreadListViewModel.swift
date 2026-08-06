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
            let cachedByID = Dictionary(uniqueKeysWithValues: store.threads(for: ssh.connectionID).map { ($0.id, $0) })
            threads = remoteThreads.map { remote in
                var current = remote
                if let cached = cachedByID[remote.id] {
                    if remote.activeModel == "default" {
                        current.activeModel = cached.activeModel
                    }
                    current.settings = cached.settings
                }
                return current
            }
            threads.forEach { store.save($0) }
        } catch {
            // Keep the last known local list visible when the watch is offline.
            threads = store.threads(for: ssh.connectionID)
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func createNewThread(title: String, cwd: String? = nil) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let thread = try await codex.createThread(title: cleanTitle, cwd: cleanCWD)
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
