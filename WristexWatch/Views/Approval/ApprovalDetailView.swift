import SwiftUI

public struct ApprovalDetailView: View {
    let request: ApprovalRequest
    
    @EnvironmentObject private var viewModel: ApprovalViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(request: ApprovalRequest) {
        self.request = request
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Header Details
                HStack {
                    Label(request.toolName, systemImage: toolIcon(request.toolName))
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(toolColor(request.toolName))
                    
                    Spacer()
                    
                    Text(formattedTime(request.timestamp))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                
                // Inspect Card / Console view
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action Description:")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(request.details)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(request.toolName == "run_command" ? .green : .white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(6)
                    }
                }
                .padding(6)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                
                // Approve / Deny Buttons
                HStack(spacing: 8) {
                    Button(action: {
                        Task {
                            await viewModel.respond(id: request.id, approve: false)
                            dismiss()
                        }
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Deny")
                        }
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                    Button(action: {
                        Task {
                            await viewModel.respond(id: request.id, approve: true)
                            dismiss()
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Approve")
                        }
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.emerald)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Inspect Request")
        .navigationBarTitleDisplayMode(.inline)
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
