import SwiftUI

public struct ApprovalListView: View {
    @EnvironmentObject private var viewModel: ApprovalViewModel
    
    public init() {}
    
    public var body: some View {
        List {
            if viewModel.isLoading && viewModel.approvals.isEmpty {
                VStack {
                    ProgressView()
                        .padding()
                    Text("Fetching approvals...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else if viewModel.approvals.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundColor(.emerald) // Custom color token
                    Text("All Actions Approved")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                    Text("Agent has no pending tool prompts.")
                        .font(.system(size: 10, weight: .light, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            } else {
                Section(header: Text("Awaiting Permission").font(.system(.footnote, design: .rounded)).foregroundColor(.orange)) {
                    ForEach(viewModel.approvals) { request in
                        NavigationLink(destination: ApprovalDetailView(request: request)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: toolIcon(request.toolName))
                                        .foregroundColor(toolColor(request.toolName))
                                    Text(request.toolName)
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.semibold)
                                }
                                
                                Text(request.details)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Approvals")
        .refreshable {
            await viewModel.loadApprovals()
        }
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
