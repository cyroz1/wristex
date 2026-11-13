import SwiftUI

public struct WorkspaceBrowserView: View {
    private let rootPath: String
    private let directoryPath: String
    private let screenshotMode: Bool
    @StateObject private var viewModel: RemoteWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    public init(
        rootPath: String,
        directoryPath: String? = nil,
        screenshotMode: Bool = false
    ) {
        let cleanRoot = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rootPath = cleanRoot
        self.directoryPath = directoryPath ?? cleanRoot
        self.screenshotMode = screenshotMode
        _viewModel = StateObject(wrappedValue: RemoteWorkspaceViewModel(
            directoryPath: directoryPath ?? cleanRoot,
            screenshotMode: screenshotMode
        ))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { dismiss() } label: {
                    Image(systemName: directoryPath == rootPath ? "xmark" : "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Text(directoryTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 2)

                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .frame(height: 26)
            .padding(.horizontal, 3)

            List {
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await viewModel.load() } }
                    }
                    .frame(maxWidth: .infinity)
                } else if viewModel.entries.isEmpty {
                    Text("This folder is empty.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.entries) { entry in
                        if entry.isDirectory {
                            NavigationLink {
                                WorkspaceBrowserView(rootPath: rootPath, directoryPath: entry.path, screenshotMode: screenshotMode)
                            } label: {
                                fileRow(entry)
                            }
                        } else if entry.kind == .file {
                            NavigationLink {
                                RemoteFilePreviewView(filePath: entry.path, fileName: entry.name, screenshotMode: screenshotMode)
                            } label: {
                                fileRow(entry)
                            }
                        } else {
                            fileRow(entry)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
            .refreshable { await viewModel.load() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    private var directoryTitle: String {
        directoryPath.split(separator: "/").last.map(String.init) ?? directoryPath
    }

    @ViewBuilder
    private func fileRow(_ entry: RemoteFileEntry) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon(for: entry.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(entry.isDirectory ? .blue : .secondary)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11, design: .rounded))
                    .lineLimit(2)
                if entry.kind == .file {
                    Text(Self.byteLabel(entry.byteSize))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func icon(for kind: RemoteFileKind) -> String {
        switch kind {
        case .directory: return "folder.fill"
        case .file: return "doc.text"
        case .symbolicLink: return "link"
        }
    }

    fileprivate static func byteLabel(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct RemoteFilePreviewView: View {
    let filePath: String
    let fileName: String
    private let screenshotMode: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var contents: RemoteFileContents?
    @State private var errorMessage: String?
    @State private var isLoading = false

    init(filePath: String, fileName: String, screenshotMode: Bool = ScreenshotMode.isEnabled) {
        self.filePath = filePath
        self.fileName = fileName
        self.screenshotMode = screenshotMode
        _contents = State(initialValue: screenshotMode ? ScreenshotFixtures.fileContents : nil)
    }

    var body: some View {
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
                if isLoading { ProgressView().scaleEffect(0.55) }
            }
            .frame(height: 26)
            .padding(.horizontal, 3)

            if let contents {
                if contents.wasTruncated {
                    Text("Previewing first 16 KB · \(WorkspaceBrowserView.byteLabel(contents.byteSize)) total")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                ScrollView {
                    Text(contents.text.isEmpty ? "(empty file)" : contents.text)
                        .font(.system(size: 8, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if isLoading {
                ProgressView("Loading file…")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !screenshotMode else { return }
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            contents = try await RemoteWorkspaceService.shared.readFile(at: filePath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
