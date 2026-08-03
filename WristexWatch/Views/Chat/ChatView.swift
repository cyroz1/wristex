import SwiftUI
import WatchKit

public struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if !viewModel.isConfigured {
                setupCard
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(viewModel.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onAppear {
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.count) {
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Message…", text: $inputText)
                    .font(.system(.body, design: .rounded))
                    .submitLabel(.send)
                    .onSubmit { sendInput() }

                if viewModel.isVoiceRecording {
                    Button {
                        Task {
                            if let transcript = await viewModel.stopVoiceTranscription() {
                                await viewModel.sendMessage(transcript)
                            }
                        }
                    } label: {
                        Image(systemName: "waveform")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        Task {
                            // Prefer GPT transcription when the API key is
                            // configured; native dictation remains a fallback.
                            if !(await viewModel.startVoiceTranscription()) {
                                presentDictation()
                            }
                        }
                    } label: {
                        Image(systemName: "mic.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                    .disabled(viewModel.isSending)
                }

                Button(action: sendInput) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(viewModel.isSending || !viewModel.isConfigured || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
            .padding(.horizontal, 2)

            if viewModel.isSending {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Thinking…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(viewModel.modelName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.clearChat()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.messages.isEmpty || viewModel.isSending)
            }
        }
        .onAppear {
            viewModel.refreshConfiguration()
        }
        .onDisappear {
            viewModel.cancelVoiceTranscription()
        }
    }

    private var setupCard: some View {
        VStack(spacing: 5) {
            Label("API key needed", systemImage: "key.fill")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.orange)
            Text("Add your OpenAI API key in Settings to use Chat.")
                .font(.system(size: 9))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            NavigationLink("Open Settings", destination: SettingsView())
                .font(.caption2)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(10)
        .padding(.horizontal, 4)
        .padding(.bottom, 5)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "message.fill")
                .font(.title3)
                .foregroundColor(.indigo)
            Text("Private Chat")
                .font(.system(.headline, design: .rounded))
            Text("Messages stay on this watch and are sent to the OpenAI Responses API when you send them.")
                .font(.system(size: 9))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            Text(message.text.isEmpty ? "…" : message.text)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(message.role == .user ? Color.indigo : Color.white.opacity(0.12))
                .cornerRadius(12)
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }

    private func sendInput() {
        let text = inputText
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }

    private func presentDictation() {
        HapticManager.shared.playStart()

        #if os(watchOS)
        let rootController = WKApplication.shared().visibleInterfaceController
        rootController?.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { results in
            HapticManager.shared.playStop()
            guard let result = results?.first as? String else { return }
            let dictatedText = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dictatedText.isEmpty else { return }
            Task { await viewModel.sendMessage(dictatedText) }
        }
        #else
        HapticManager.shared.playStop()
        #endif
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View { ChatView() }
}
