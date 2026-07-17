import SwiftUI

public struct GitStatusView: View {
    @EnvironmentObject private var viewModel: GitViewModel
    @State private var showingCommitSheet = false
    @State private var commitMessageInput = ""
    
    public init() {}
    
    public var body: some View {
        List {
            if viewModel.isLoading && viewModel.gitStatus == nil {
                VStack {
                    ProgressView()
                        .padding()
                    Text("Syncing git status...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else if let status = viewModel.gitStatus {
                // 1. Branch Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .foregroundColor(.amber)
                        Text(status.branch)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 12) {
                        Label("\(status.ahead) ahead", systemImage: "arrow.up")
                        Label("\(status.behind) behind", systemImage: "arrow.down")
                    }
                    .font(.system(size: 9, weight: .light, design: .rounded))
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                // 2. Action Grid / Buttons
                Section(header: Text("Actions").font(.system(.footnote, design: .rounded))) {
                    HStack(spacing: 8) {
                        Button(action: { Task { await viewModel.pull() } }) {
                            VStack(spacing: 2) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.body)
                                Text("Pull")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                        }
                        .tint(.blue.opacity(0.8))
                        
                        Button(action: {
                            commitMessageInput = ""
                            showingCommitSheet = true
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                Text("Commit")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                        }
                        .tint(.orange.opacity(0.8))
                        .disabled(status.modifiedFiles.isEmpty && status.untrackedFiles.isEmpty)
                        
                        Button(action: { Task { await viewModel.push() } }) {
                            VStack(spacing: 2) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.body)
                                Text("Push")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                        }
                        .tint(.emerald.opacity(0.8))
                        .disabled(status.ahead == 0)
                    }
                    .frame(height: 48)
                    .listRowBackground(Color.clear)
                }
                
                // Feedback text banner
                if let feedback = viewModel.actionFeedbackMessage {
                    Text(feedback)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.emerald)
                        .multilineTextAlignment(.center)
                        .listRowBackground(Color.emerald.opacity(0.08))
                }
                
                // 3. Modified Files List
                if status.modifiedFiles.isEmpty && status.untrackedFiles.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundColor(.emerald)
                        Text("Clean Working Directory")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.white.opacity(0.04))
                } else {
                    Section(header: Text("Changes").font(.system(.footnote, design: .rounded)).foregroundColor(.amber)) {
                        ForEach(status.modifiedFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundColor(.amber)
                                Text(file.split(separator: "/").last ?? "")
                                    .font(.caption2)
                                Spacer()
                                Text("M")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.amber)
                            }
                        }
                        
                        ForEach(status.untrackedFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.emerald)
                                Text(file.split(separator: "/").last ?? "")
                                    .font(.caption2)
                                Spacer()
                                Text("A")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.emerald)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Status unavailable.")
                        .font(.caption)
                    Button("Reload") {
                        Task { await viewModel.loadGitStatus() }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Git Manager")
        .refreshable {
            await viewModel.loadGitStatus()
        }
        .sheet(isPresented: $showingCommitSheet) {
            VStack(spacing: 12) {
                Text("Commit Message")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                HStack {
                    TextField("Refactor models...", text: $commitMessageInput)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    
                    Button(action: presentDictation) {
                        Image(systemName: "mic.fill")
                    }
                    .frame(width: 36)
                    .tint(.orange)
                }
                
                HStack(spacing: 8) {
                    Button("Cancel") {
                        showingCommitSheet = false
                    }
                    .tint(.secondary)
                    
                    Button("Commit") {
                        let msg = commitMessageInput
                        showingCommitSheet = false
                        Task {
                            await viewModel.commit(message: msg)
                        }
                    }
                    .tint(.orange)
                    .disabled(commitMessageInput.isEmpty)
                }
            }
            .padding()
        }
        .task {
            await viewModel.loadGitStatus()
        }
    }
    
    private func presentDictation() {
        HapticManager.shared.playStart()
        #if os(watchOS)
        let rootController = WKExtension.shared().visibleInterfaceController
        rootController?.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            guard let results = results, let firstResult = results.first as? String else {
                HapticManager.shared.playStop()
                return
            }
            HapticManager.shared.playStop()
            let text = firstResult.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                commitMessageInput = text
            }
        }
        #else
        print("Dictation in Preview Mode")
        #endif
    }
}

extension Color {
    static let amber = Color(red: 0.95, green: 0.60, blue: 0.07)
}

struct GitStatusView_Previews: PreviewProvider {
    public static var previews: some View {
        let mockVm = GitViewModel()
        return GitStatusView()
            .environmentObject(mockVm)
    }
}
