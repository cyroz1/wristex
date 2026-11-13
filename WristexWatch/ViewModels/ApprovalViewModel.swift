import Foundation
import Combine

@MainActor
public final class ApprovalViewModel: ObservableObject {
    @Published public var approvals: [ApprovalRequest] = []
    @Published public var isLoading = false
    @Published public var errorMessage: String? = nil

    private let codex = RemoteCodexService.shared
    private var pollingTask: Task<Void, Never>?

    public init() {
        if ScreenshotMode.isEnabled {
            approvals = ScreenshotFixtures.approvals
        }
    }

    public func loadApprovals() async {
        guard !ScreenshotMode.isEnabled else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await codex.connect()
            approvals = codex.approvals
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @discardableResult
    public func respond(
        id: String,
        approve: Bool,
        permissionScope: String = "turn",
        answers: [String: [String]] = [:],
        elicitationContent: [String: Any] = [:]
    ) async -> Bool {
        isLoading = true
        errorMessage = nil
        do {
            try await codex.respondToApproval(
                id: id,
                approve: approve,
                permissionScope: permissionScope,
                answers: answers,
                elicitationContent: elicitationContent
            )
            approvals.removeAll { $0.id == id }
            approve ? HapticManager.shared.playSuccess() : HapticManager.shared.playFailure()
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.playFailure()
            isLoading = false
            return false
        }
    }

    public func startPolling() {
        guard !ScreenshotMode.isEnabled else { return }
        stopPolling()
        codex.setApprovalHandler { [weak self] request in
            guard let self else { return }
            if !self.approvals.contains(where: { $0.id == request.id }) {
                self.approvals.append(request)
                HapticManager.shared.playStart()
            }
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.loadApprovals()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                await self.loadApprovals()
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        codex.setApprovalHandler(nil)
    }

    deinit {
        pollingTask?.cancel()
    }
}
