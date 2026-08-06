import SwiftUI

public struct ThreadListView: View {
    @EnvironmentObject private var viewModel: ThreadListViewModel
    @State private var showingNewThreadAlert = false
    @State private var newThreadTitle = ""
    @State private var newThreadFolder = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            CompactWatchHeader("Threads") {
                Button {
                    Task { await viewModel.loadThreads() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    showingNewThreadAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .background(Color.indigo.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            List {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.red)
                        .lineLimit(2)
                        .listRowInsets(EdgeInsets(top: 2, leading: 3, bottom: 2, trailing: 3))
                }

                if viewModel.isLoading && viewModel.threads.isEmpty {
                    VStack(spacing: 2) {
                        ProgressView()
                        Text("Loading threads...")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } else if viewModel.threads.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                        Text("No Active Threads")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await viewModel.loadThreads() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.indigo)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.threads) { thread in
                        NavigationLink(destination: ThreadDetailView(thread: thread)) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 3) {
                                    Text(thread.title)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    Text(modelDisplayName(thread.activeModel))
                                        .font(.system(size: 7, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Color.white.opacity(0.12))
                                        .cornerRadius(3)
                                }

                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(statusColor(thread))
                                        .frame(width: 5, height: 5)
                                    Text(thread.status.shortLabel)
                                        .font(.system(size: 7, weight: .bold, design: .rounded))
                                        .foregroundColor(statusColor(thread))
                                    if thread.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 7))
                                            .foregroundColor(.orange)
                                    }
                                    Spacer(minLength: 2)
                                    Text(projectLabel(thread))
                                        .font(.system(size: 7, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Text(thread.lastMessage)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 1)
                        }
                        .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await viewModel.delete(thread) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                Task { await viewModel.archive(thread) }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .refreshable { await viewModel.loadThreads() }
            .sheet(isPresented: $showingNewThreadAlert) {
                VStack(spacing: 7) {
                    Text("New Thread")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    TextField("Thread name", text: $newThreadTitle)
                        .autocorrectionDisabled()
                    TextField("Project folder (optional)", text: $newThreadFolder)
                        .autocorrectionDisabled()
                        .font(.caption)

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            showingNewThreadAlert = false
                            newThreadTitle = ""
                            newThreadFolder = ""
                        }
                        .tint(.red)

                        Button("Create") {
                            let title = newThreadTitle
                            let folder = newThreadFolder
                            showingNewThreadAlert = false
                            newThreadTitle = ""
                            newThreadFolder = ""
                            Task { await viewModel.createNewThread(title: title, cwd: folder) }
                        }
                        .tint(.blue)
                    }
                }
                .padding(8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadThreads() }
    }
    
    private func modelDisplayName(_ modelId: String) -> String {
        switch modelId {
        case "default": return "Default"
        case "gpt-4o": return "GPT-4"
        case "claude-3-5": return "Claude"
        case "gemini-1-5": return "Gemini"
        default: return modelId.prefix(4).uppercased()
        }
    }

    private func projectLabel(_ thread: AgentThread) -> String {
        guard let cwd = thread.cwd, !cwd.isEmpty else { return "No folder" }
        return cwd.split(separator: "/").last.map(String.init) ?? cwd
    }

    private func statusColor(_ thread: AgentThread) -> Color {
        switch thread.status.kind {
        case .notLoaded: return .gray
        case .idle: return .green
        case .active:
            return thread.status.activeFlags.isEmpty ? .blue : .orange
        case .systemError: return .red
        }
    }
}

struct ThreadListView_Previews: PreviewProvider {
    public static var previews: some View {
        let mockVm = ThreadListViewModel()
        return ThreadListView()
            .environmentObject(mockVm)
    }
}
