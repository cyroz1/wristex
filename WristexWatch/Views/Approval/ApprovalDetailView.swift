import SwiftUI

public struct ApprovalDetailView: View {
    let request: ApprovalRequest
    
    @EnvironmentObject private var viewModel: ApprovalViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(request: ApprovalRequest) {
        self.request = request
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            CompactWatchHeader("Approval") {
                Text(request.toolName)
                    .font(.system(size: 7, weight: .semibold, design: .rounded))
                    .foregroundColor(toolColor(request.toolName))
                    .lineLimit(1)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: toolIcon(request.toolName))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(toolColor(request.toolName))
                        Text(formattedTime(request.timestamp))
                            .font(.system(size: 8, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Action")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)

                        Text(request.details)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(request.toolName == "run_command" ? .green : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(5)
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)

                    HStack(spacing: 4) {
                        Button {
                            Task {
                                await viewModel.respond(id: request.id, approve: false)
                                dismiss()
                            }
                        } label: {
                            Label("Deny", systemImage: "xmark")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, height: 30)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            Task {
                                await viewModel.respond(id: request.id, approve: true)
                                dismiss()
                            }
                        } label: {
                            Label("Approve", systemImage: "checkmark")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, height: 30)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .background(Color.emerald.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ApprovalDetailView_Previews: PreviewProvider {
    public static var previews: some View {
        let request = ApprovalRequest(id: "appr-1", toolName: "run_command", details: "git commit -m 'feat: biometrics'", status: "pending", timestamp: Date())
        let mockVm = ApprovalViewModel()
        return ApprovalDetailView(request: request)
            .environmentObject(mockVm)
    }
}
