import Combine
import Foundation

@MainActor
public final class RemoteWorkspaceViewModel: ObservableObject {
    @Published public private(set) var entries: [RemoteFileEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    public let directoryPath: String
    private let workspace = RemoteWorkspaceService.shared
    private let screenshotMode: Bool

    public init(directoryPath: String, screenshotMode: Bool = false) {
        self.directoryPath = directoryPath
        self.screenshotMode = screenshotMode
        if screenshotMode {
            entries = ScreenshotFixtures.directoryEntries
        }
    }

    public func load() async {
        guard !screenshotMode else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            entries = try await workspace.listDirectory(at: directoryPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
