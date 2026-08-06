import SwiftUI
import WatchKit

public struct ThreadDetailView: View {
    @StateObject private var viewModel: ThreadDetailViewModel
    @StateObject private var gitViewModel: GitViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingControls = false
    @State private var showingGit = false
    @State private var showingModelPicker = false
    @State private var showingReasoningPicker = false
    @State private var inputText = ""
    
    public init(thread: AgentThread) {
        _viewModel = StateObject(wrappedValue: ThreadDetailViewModel(thread: thread))
        _gitViewModel = StateObject(wrappedValue: GitViewModel(workspacePath: thread.cwd ?? ""))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            threadHeader
            statusLine

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if viewModel.messages.isEmpty {
                            VStack(spacing: 4) {
                                Text("No messages yet.")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.secondary)
                                Text("Use the message bubble or dictation.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 90)
                        } else {
                            ForEach(viewModel.messages) { msg in
                                HStack(spacing: 0) {
                                    if msg.sender == "user" {
                                        Spacer(minLength: 18)
                                        WatchMarkdownText(msg.content)
                                            .font(.system(size: 13, design: .rounded))
                                            .lineSpacing(1)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                LinearGradient(
                                                    colors: [.indigo, .blue],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .cornerRadius(11)
                                            .id(msg.id)
                                    } else {
                                        WatchMarkdownText(msg.content)
                                            .font(.system(size: 13, design: .rounded))
                                            .lineSpacing(1)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.white.opacity(0.12))
                                            .cornerRadius(11)
                                            .id(msg.id)
                                        Spacer(minLength: 18)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.messages.count) {
                    if let lastMsg = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMsg.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let lastMsg = viewModel.messages.last {
                        proxy.scrollTo(lastMsg.id, anchor: .bottom)
                    }
                }
            }

            composer
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .sheet(isPresented: $showingControls) {
            ThreadControlsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingGit) {
            NavigationStack {
                GitStatusView()
                    .environmentObject(gitViewModel)
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            modelSelectionSheet
        }
        .sheet(isPresented: $showingReasoningPicker) {
            reasoningSelectionSheet
        }
    }

    private var threadHeader: some View {
        HStack(alignment: .top, spacing: 3) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 27, height: 25)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.thread.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(projectDirectoryLabel)
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 3)

            HStack(spacing: 2) {
                Button {
                    showingControls = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 27, height: 25)
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    showingGit = true
                } label: {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 27, height: 25)
                }
                .buttonStyle(.plain)
                .foregroundColor(.green)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 3)
        .padding(.top, 1)
        .padding(.bottom, 1)
    }

    private var statusLine: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Text(viewModel.thread.status.shortLabel)
            if let goal = viewModel.goal {
                Text("· \(goal.status.label)")
                    .foregroundColor(.secondary)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.45)
            }
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundColor(statusColor)
        .padding(.horizontal, 4)
        .padding(.bottom, 1)
    }

    private var composer: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                modelPicker
                reasoningPicker
            }
            .frame(height: 25)

            HStack(spacing: 3) {
                TextField("Message…", text: $inputText)
                    .font(.system(size: 13, design: .rounded))
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .submitLabel(.send)
                    .onSubmit(sendInput)

                if viewModel.isSending {
                    Button {
                        Task { await viewModel.interruptTurn() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 32)
                            .background(Color.red.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                } else {
                    Button(action: presentDictation) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 32)
                            .background(Color.indigo.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .padding(.bottom, 1)
        .background(Color.black)
    }

    private var modelPicker: some View {
        Button {
            showingModelPicker = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "cpu")
                Text(compactModelName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 23)
        }
        .buttonStyle(.plain)
        .foregroundColor(.indigo)
        .background(Color.indigo.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var reasoningPicker: some View {
        Button {
            showingReasoningPicker = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "dial.medium")
                Text(reasoningLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 23)
        }
        .buttonStyle(.plain)
        .foregroundColor(.orange)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var modelSelectionSheet: some View {
        List {
            Section("Model") {
                if viewModel.models.isEmpty {
                    Text("No models available.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.models) { option in
                        Button {
                            showingModelPicker = false
                            Task { await viewModel.selectModel(option.id) }
                        } label: {
                            HStack {
                                Text(option.name)
                                    .lineLimit(1)
                                Spacer()
                                if option.id == viewModel.activeModelId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.indigo)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Model")
    }

    private var reasoningSelectionSheet: some View {
        List {
            Section("Reasoning") {
                ForEach(viewModel.reasoningEffortOptions, id: \.self) { effort in
                    Button {
                        showingReasoningPicker = false
                        var next = viewModel.settings
                        next.reasoningEffort = effort == "default" ? nil : effort
                        Task { await viewModel.updateSettings(next) }
                    } label: {
                        HStack {
                            Text(effort == "default" ? "Model default" : effort.capitalized)
                            Spacer()
                            if (viewModel.settings.reasoningEffort ?? "default") == effort {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reasoning")
    }
    
    private var compactModelName: String {
        if let current = viewModel.models.first(where: { $0.id == viewModel.activeModelId }) {
            return current.name == "Host Default" ? "Default" : current.name
        }
        return viewModel.activeModelId == "default" ? "Default" : viewModel.activeModelId
    }

    private var reasoningLabel: String {
        viewModel.settings.reasoningEffort?.capitalized ?? "Auto"
    }

    private var projectDirectoryLabel: String {
        guard let cwd = viewModel.thread.cwd, !cwd.isEmpty else {
            return "No project folder"
        }
        return cwd.split(separator: "/").last.map(String.init) ?? cwd
    }

    private var statusColor: Color {
        switch viewModel.thread.status.kind {
        case .notLoaded: return .gray
        case .idle: return .green
        case .active:
            return viewModel.thread.status.activeFlags.isEmpty ? .blue : .orange
        case .systemError: return .red
        }
    }

    private func sendInput() {
        let text = inputText
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }
    
    private func presentDictation() {
        // Uses standard Apple Watch input session controller.
        // On watchOS, present the native text input controller from the visible interface.
        // to show a native dictation screen and capture text.
        HapticManager.shared.playStart()
        
        #if os(watchOS)
        viewModel.clearError()
        let rootController = WKApplication.shared().visibleInterfaceController
        rootController?.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            guard let results = results, let firstResult = results.first as? String else {
                HapticManager.shared.playStop()
                return
            }
            
            HapticManager.shared.playStop()
            let dictatedText = firstResult.trimmingCharacters(in: .whitespacesAndNewlines)
            if !dictatedText.isEmpty {
                Task {
                    await viewModel.sendMessage(dictatedText)
                }
            }
        }
        #else
        // Fallback for previews/simulator if needed
        print("Dictation triggered in preview mode.")
        #endif
    }
}

private struct ThreadControlsView: View {
    @ObservedObject var viewModel: ThreadDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var goalText = ""
    @State private var folderText = ""

    var body: some View {
        List {
            Section("Project folder") {
                TextField("Optional remote path", text: $folderText)
                    .font(.caption)
                    .autocorrectionDisabled()

                Button(folderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Use no folder" : "Save folder") {
                    Task { await viewModel.updateFolder(folderText) }
                }

                Text(viewModel.thread.cwd.map { "Current: \($0)" } ?? "No project folder")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Section("Goal") {
                TextField("What should Codex achieve?", text: $goalText)
                    .lineLimit(3)

                if let goal = viewModel.goal {
                    Text("\(goal.status.label) · \(goal.tokensUsed) tokens")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button("Update Goal") {
                        Task { await viewModel.setGoal(goalText) }
                    }
                    Button("Clear Goal", role: .destructive) {
                        Task {
                            await viewModel.clearGoal()
                            goalText = ""
                        }
                    }
                } else {
                    Button("Set Goal") {
                        Task { await viewModel.setGoal(goalText) }
                    }
                }
            }

            Section("Reasoning effort") {
                ForEach(viewModel.reasoningEffortOptions, id: \.self) { effort in
                    Button {
                        var next = viewModel.settings
                        next.reasoningEffort = effort == "default" ? nil : effort
                        Task { await viewModel.updateSettings(next) }
                    } label: {
                        settingRow(
                            title: effort == "default" ? "Model default" : effort.capitalized,
                            selected: (viewModel.settings.reasoningEffort ?? "default") == effort
                        )
                    }
                }
            }

            Section("Personality") {
                ForEach(CodexPersonality.allCases) { personality in
                    Button {
                        var next = viewModel.settings
                        next.personality = personality
                        Task { await viewModel.updateSettings(next) }
                    } label: {
                        settingRow(title: personality.label, selected: viewModel.settings.personality == personality)
                    }
                }
            }

            Section("Approvals") {
                ForEach(CodexApprovalPolicy.allCases) { policy in
                    Button {
                        var next = viewModel.settings
                        next.approvalPolicy = policy
                        Task { await viewModel.updateSettings(next) }
                    } label: {
                        settingRow(title: policy.label, selected: viewModel.settings.approvalPolicy == policy)
                    }
                }
            }

            Section("Sandbox") {
                ForEach(CodexSandboxPolicy.allCases) { policy in
                    Button {
                        var next = viewModel.settings
                        next.sandboxPolicy = policy
                        Task { await viewModel.updateSettings(next) }
                    } label: {
                        settingRow(title: policy.label, selected: viewModel.settings.sandboxPolicy == policy)
                    }
                }
            }

            Section("Reasoning summary") {
                ForEach(CodexReasoningSummary.allCases) { summary in
                    Button {
                        var next = viewModel.settings
                        next.reasoningSummary = summary
                        Task { await viewModel.updateSettings(next) }
                    } label: {
                        settingRow(title: summary.label, selected: viewModel.settings.reasoningSummary == summary)
                    }
                }
            }

            Button("Done") { dismiss() }
        }
        .navigationTitle("Thread Controls")
        .onAppear {
            goalText = viewModel.goal?.objective ?? ""
            folderText = viewModel.thread.cwd ?? ""
        }
    }

    @ViewBuilder
    private func settingRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundColor(.indigo)
            }
        }
    }
}

struct ThreadDetailView_Previews: PreviewProvider {
    public static var previews: some View {
        let thread = AgentThread(id: "thread-1", title: "Build login layout", lastMessage: "Hello", activeModel: "gpt-4o")
        return ThreadDetailView(thread: thread)
    }
}
