import SwiftUI

public struct ApprovalListView: View {
    @EnvironmentObject private var viewModel: ApprovalViewModel
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            CompactWatchHeader("Approvals") {
                if !viewModel.approvals.isEmpty {
                    Text("\(viewModel.approvals.count)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                }
                Button {
                    Task { await viewModel.loadApprovals() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            List {
                if viewModel.isLoading && viewModel.approvals.isEmpty {
                    VStack(spacing: 2) {
                        ProgressView()
                        Text("Fetching approvals…")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } else if viewModel.approvals.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.emerald)
                        Text("All clear")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text("No pending tool prompts.")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(viewModel.approvals) { request in
                            NavigationLink(destination: ApprovalDetailView(request: request)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: toolIcon(request.toolName))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(toolColor(request.toolName))
                                        Text(request.toolName)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                    }

                                    Text(request.details)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 1)
                            }
                            .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
                        }
                    } header: {
                        Text("Awaiting permission")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                }
            }
            .refreshable { await viewModel.loadApprovals() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            // Keep polling in background for main badge updates, or leave it to TabView control
        }
    }
    
    private func toolIcon(_ name: String) -> String {
        switch name {
        case "run_command": return "terminal.fill"
        case "write_file", "replace_file_content", "multi_replace_file_content": return "doc.text.fill"
        case "read_file": return "doc.text.magnifyingglass"
        case "search_web": return "globe"
        default: return "questionmark.key.filled"
        }
    }
    
    private func toolColor(_ name: String) -> Color {
        switch name {
        case "run_command": return .red
        case "write_file", "replace_file_content", "multi_replace_file_content": return .orange
        case "read_file": return .blue
        case "search_web": return .purple
        default: return .secondary
        }
    }
}

// Custom clean color extensions for premium UI
extension Color {
    static let emerald = Color(red: 0.18, green: 0.80, blue: 0.44)
    static let darkCharcoal = Color(red: 0.11, green: 0.11, blue: 0.12)
}

struct ApprovalListView_Previews: PreviewProvider {
    public static var previews: some View {
        let mockVm = ApprovalViewModel()
        return ApprovalListView()
            .environmentObject(mockVm)
    }
}
