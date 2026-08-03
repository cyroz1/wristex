import SwiftUI

public struct ThreadListView: View {
    @EnvironmentObject private var viewModel: ThreadListViewModel
    @State private var showingNewThreadAlert = false
    @State private var newThreadTitle = ""
    
    public init() {}
    
    public var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }

            Button(action: { showingNewThreadAlert = true }) {
                HStack {
                    Image(systemName: "plus.bubble.fill")
                    Text("New Thread")
                        .font(.system(.body, design: .rounded))
                }
                .foregroundColor(.white)
            }
            .listRowBackground(
                LinearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            if viewModel.isLoading && viewModel.threads.isEmpty {
                VStack {
                    ProgressView()
                        .padding()
                    Text("Loading threads...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else if viewModel.threads.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("No Active Threads")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await viewModel.loadThreads() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            } else {
                    ForEach(viewModel.threads) { thread in
                        NavigationLink(destination: ThreadDetailView(thread: thread)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(thread.title)
                                    .font(.system(.body, design: .rounded))
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                                Spacer()
                                // Small indicator for active model
                                Text(modelDisplayName(thread.activeModel))
                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            
                            Text(thread.lastMessage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                            .padding(.vertical, 4)
                        }
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
        .navigationTitle("Threads")
        .refreshable {
            await viewModel.loadThreads()
        }
        .sheet(isPresented: $showingNewThreadAlert) {
            VStack(spacing: 12) {
                Text("New Thread Name")
                    .font(.headline)
                
                TextField("e.g. Build login form", text: $newThreadTitle)
                    .autocorrectionDisabled()
                
                HStack(spacing: 10) {
                    Button("Cancel") {
                        showingNewThreadAlert = false
                        newThreadTitle = ""
                    }
                    .tint(.red)
                    
                    Button("Create") {
                        let title = newThreadTitle
                        showingNewThreadAlert = false
                        newThreadTitle = ""
                        Task {
                            await viewModel.createNewThread(title: title)
                        }
                    }
                    .tint(.blue)
                }
            }
            .padding()
        }
        .task {
            await viewModel.loadThreads()
        }
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
}

struct ThreadListView_Previews: PreviewProvider {
    public static var previews: some View {
        let mockVm = ThreadListViewModel()
        return ThreadListView()
            .environmentObject(mockVm)
    }
}
