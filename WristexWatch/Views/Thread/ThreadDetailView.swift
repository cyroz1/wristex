import SwiftUI
import WatchKit

public struct ThreadDetailView: View {
    @StateObject private var viewModel: ThreadDetailViewModel
    @State private var showingModelPicker = false
    @State private var showingControls = false
    @State private var inputText = ""
    
    public init(thread: AgentThread) {
        _viewModel = StateObject(wrappedValue: ThreadDetailViewModel(thread: thread))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Quick Action Header: Model Selector & Manual Reload
                        HStack {
                            Button(action: { showingModelPicker = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "cpu")
                                    Text(activeModelName)
                                }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.indigo)
                            }
                            .buttonStyle(.bordered)
                            .tint(.indigo.opacity(0.15))
                            
                            Spacer()

                            Button(action: { showingControls = true }) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange.opacity(0.15))
                            
                            if viewModel.isLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Button(action: { Task { await viewModel.loadMessages() } }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.bordered)
                                .tint(.secondary.opacity(0.15))
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 7, height: 7)
                            Image(systemName: statusIcon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(viewModel.thread.status.label)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            if let goal = viewModel.goal {
                                Text("· \(goal.status.label)")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                        
                        // Messages Bubble List
                        if viewModel.messages.isEmpty {
                            VStack(spacing: 8) {
                                Spacer()
                                Text("No messages yet.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Tap the dictation field below to start.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                        } else {
                            ForEach(viewModel.messages) { msg in
                                HStack {
                                    if msg.sender == "user" {
                                        Spacer(minLength: 24)
                                        Text(msg.content)
                                            .font(.system(.body, design: .rounded))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                LinearGradient(
                                                    colors: [.indigo, .blue],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .cornerRadius(12)
                                            .id(msg.id)
                                    } else {
                                        Text(msg.content)
                                            .font(.system(.body, design: .rounded))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.white.opacity(0.12))
                                            .cornerRadius(12)
                                            .id(msg.id)
                                        Spacer(minLength: 24)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
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
            
            // Dictation Input Section (Apple watch default keyboard overlay + Dictation integration)
            HStack(spacing: 6) {
                TextField("Reply...", text: $inputText)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 4)
                    .submitLabel(.send)
                    .onSubmit {
                        let text = inputText
                        inputText = ""
                        Task {
                            await viewModel.sendMessage(text)
                        }
                    }
                
                if viewModel.isVoiceRecording {
                    Button {
                        Task { await viewModel.stopVoiceTranscription() }
                    } label: {
                        Image(systemName: "waveform")
                            .font(.body)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(width: 44)
                } else if viewModel.isSending {
                    Button {
                        Task { await viewModel.interruptTurn() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.body)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(width: 44)
                } else {
                    Button {
                        Task {
                            // Prefer Codex realtime transcription over SSH;
                            // fall back to native watchOS dictation if the
                            // remote Codex build does not support it.
                            if !(await viewModel.startVoiceTranscription()) {
                                presentDictation()
                            }
                        }
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.body)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .frame(width: 44)
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }
        }
        .navigationTitle(viewModel.thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .sheet(isPresented: $showingModelPicker) {
            ScrollView {
                VStack(spacing: 8) {
                    Text("Select Model")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.indigo)
                        .padding(.bottom, 4)
                    
                    if viewModel.models.isEmpty {
                        Text("No models available.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.models) { option in
                            Button(action: {
                                showingModelPicker = false
                                Task {
                                    await viewModel.selectModel(option.id)
                                }
                            }) {
                                HStack {
                                    Text(option.name)
                                        .font(.system(.body, design: .rounded))
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
                .padding()
            }
        }
        .sheet(isPresented: $showingControls) {
            ThreadControlsView(viewModel: viewModel)
        }
    }
    
    private var activeModelName: String {
        if let current = viewModel.models.first(where: { $0.id == viewModel.activeModelId }) {
            return current.name
        }
        return viewModel.activeModelId.uppercased()
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

    private var statusIcon: String {
        switch viewModel.thread.status.kind {
        case .notLoaded: return "moon.zzz.fill"
        case .idle: return "checkmark.circle.fill"
        case .active:
            if viewModel.thread.status.activeFlags.contains(.waitingOnApproval) {
                return "exclamationmark.shield.fill"
            }
            if viewModel.thread.status.activeFlags.contains(.waitingOnUserInput) {
                return "questionmark.circle.fill"
            }
            return "bolt.horizontal.circle.fill"
        case .systemError: return "xmark.octagon.fill"
        }
    }
    
    private func presentDictation() {
        // Uses standard Apple Watch input session controller.
        // On watchOS, we can call WKExtension.shared().visibleInterfaceController?.presentTextInputController
        // to show a native dictation screen and capture text.
        HapticManager.shared.playStart()
        
        #if os(watchOS)
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

    var body: some View {
        List {
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
