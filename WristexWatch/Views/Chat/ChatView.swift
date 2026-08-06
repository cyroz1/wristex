import Foundation
import SwiftUI
import WatchKit

/// Renders assistant content using Foundation's Markdown parser while keeping
/// the compact typography controlled by each watch screen.
public struct WatchMarkdownText: View {
    private let markdown: String

    public init(_ markdown: String) {
        self.markdown = markdown
    }

    public var body: some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
        } else {
            Text(markdown)
        }
    }
}

public struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            CompactWatchHeader("Chat") {
                Text(viewModel.modelName)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button {
                    viewModel.clearChat()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 25, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .background(Color.red.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(viewModel.messages.isEmpty || viewModel.isSending)
            }

            if !viewModel.isConfigured {
                setupCard
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if viewModel.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(viewModel.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
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

            HStack(spacing: 4) {
                TextField("Message…", text: $inputText)
                    .font(.system(size: 12, design: .rounded))
                    .padding(.horizontal, 6)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
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
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
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
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.indigo.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSending)
                }

                Button {
                    sendInput()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.indigo.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending || !viewModel.isConfigured || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.isSending || !viewModel.isConfigured || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.top, 2)
            .padding(.horizontal, 2)

            if viewModel.isSending {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Thinking…")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 1)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 2)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.refreshConfiguration()
        }
        .onDisappear {
            viewModel.cancelVoiceTranscription()
        }
    }

    private var setupCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "key.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("API key needed")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                NavigationLink("Open Settings", destination: SettingsView())
                    .font(.system(size: 9))
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(9)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 3) {
            Image(systemName: "message.fill")
                .font(.system(size: 14))
                .foregroundColor(.indigo)
            Text("Start a chat")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Ask anything")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 16) }
            WatchMarkdownText(message.text.isEmpty ? "…" : message.text)
                .font(.system(size: 14, design: .rounded))
                .lineSpacing(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(message.role == .user ? Color.indigo : Color.white.opacity(0.12))
                .cornerRadius(10)
            if message.role == .assistant { Spacer(minLength: 16) }
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
