import SwiftUI

public struct RemoteFileDiffView: View {
    let filePath: String
    let workspacePath: String
    let isUntracked: Bool
    private let screenshotMode: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var diff = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    public init(
        filePath: String,
        workspacePath: String,
        isUntracked: Bool,
        screenshotMode: Bool = false
    ) {
        self.filePath = filePath
        self.workspacePath = workspacePath
        self.isUntracked = isUntracked
        self.screenshotMode = screenshotMode
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text(fileName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(isUntracked ? "NEW" : "DIFF")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(isUntracked ? .green : .orange)
            }
            .frame(height: 26)
            .padding(.horizontal, 3)

            if isLoading {
                ProgressView("Loading diff…")
                    .frame(maxHeight: .infinity)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(diffLines) { item in
                            let line = item.text
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 3)
                                .background(background(for: line))
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadDiff() }
    }

    private var fileName: String {
        filePath.split(separator: "/").last.map(String.init) ?? filePath
    }

    private var diffLines: [DiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { DiffLine(id: $0.offset, text: String($0.element)) }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red }
        if line.hasPrefix("@@") { return .cyan }
        return .primary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return .green.opacity(0.10) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return .red.opacity(0.10) }
        return .clear
    }

    private func loadDiff() async {
        if screenshotMode {
            diff = ScreenshotFixtures.diff
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            diff = try await RemoteWorkspaceService.shared.readDiff(
                workspacePath: workspacePath,
                relativePath: filePath,
                isUntracked: isUntracked
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct DiffLine: Identifiable {
        let id: Int
        let text: String
    }
}
