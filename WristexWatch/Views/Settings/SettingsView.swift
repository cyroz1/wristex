import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var sshManager = SSHManager.shared

    @State private var localHost = ""
    @State private var localUsername = ""
    @State private var localPortText = "22"
    @State private var localWorkspacePath = ""
    @State private var localPassword = ""
    @State private var localPrivateKeyPEM = ""
    @State private var localPrivateKeyPassphrase = ""
    @State private var localOpenAIAPIKey = ""
    @State private var localChatModel = "gpt-4o-mini"
    @State private var isTesting = false
    @State private var isTestingChat = false
    @State private var feedback: String?
    @State private var chatFeedback: String?

    public init() {}

    public var body: some View {
        Form {
            Section("SSH Host") {
                TextField("Hostname", text: $localHost)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                TextField("Username", text: $localUsername)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                TextField("Port", text: $localPortText)
                TextField("Workspace", text: $localWorkspacePath)
                    .autocorrectionDisabled()
            }

            Section("Authentication") {
                SecureField("SSH password", text: $localPassword)
                    .textContentType(.password)
                SecureField("PEM private key (optional)", text: $localPrivateKeyPEM)
                SecureField("Key passphrase", text: $localPrivateKeyPassphrase)
                    .textContentType(.password)
                Text("Saved in Keychain")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section("Chat API") {
                SecureField("OpenAI API key", text: $localOpenAIAPIKey)
                    .textContentType(.password)
                TextField("Chat model", text: $localChatModel)
                    .autocorrectionDisabled()
                Text("The key is stored in Keychain. Chat calls api.openai.com directly; it is separate from Codex SSH.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    ChatService.shared.configure(apiKey: localOpenAIAPIKey, model: localChatModel)
                    Task { await testChatAPI() }
                } label: {
                    HStack {
                        if isTestingChat { ProgressView() }
                        Image(systemName: "bubble.left.and.bubble.right")
                        Text(isTestingChat ? "Testing…" : "Test Chat API")
                    }
                }
                .disabled(isTestingChat)

                if let chatFeedback {
                    Text(chatFeedback)
                        .font(.caption2)
                        .foregroundColor(chatFeedback == "Chat API connected." ? .green : .red)
                }
            }

            Section {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    HStack {
                        if isTesting { ProgressView() }
                        Image(systemName: "bolt.horizontal.fill")
                        Text(isTesting ? "Testing…" : "Save & Test")
                    }
                }
                .disabled(isTesting)

                if sshManager.hasPinnedFingerprint {
                    Button("Forget Host Key", role: .destructive) {
                        sshManager.forgetHostFingerprint()
                        feedback = "Host key forgotten."
                    }
                }

                if let feedback {
                    Text(feedback)
                        .font(.caption2)
                        .foregroundColor(feedback.hasPrefix("Connected") ? .green : .red)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: loadSettings)
    }

    private func loadSettings() {
        localHost = sshManager.host
        localUsername = sshManager.username
        localPortText = String(sshManager.port)
        localWorkspacePath = sshManager.remoteWorkspacePath
        localPassword = sshManager.password
        localPrivateKeyPEM = sshManager.privateKeyPEM
        localPrivateKeyPassphrase = sshManager.privateKeyPassphrase
        localOpenAIAPIKey = ChatService.shared.apiKey
        localChatModel = ChatService.shared.model
    }

    private func saveAndTest() async {
        await CodexAppServerClient.shared.disconnect()
        sshManager.host = localHost.trimmingCharacters(in: .whitespacesAndNewlines)
        sshManager.username = localUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        sshManager.port = Int(localPortText) ?? 22
        sshManager.remoteWorkspacePath = localWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        sshManager.password = localPassword
        sshManager.privateKeyPEM = localPrivateKeyPEM
        sshManager.privateKeyPassphrase = localPrivateKeyPassphrase
        ChatService.shared.configure(apiKey: localOpenAIAPIKey, model: localChatModel)

        isTesting = true
        feedback = nil
        do {
            let status = try await RemoteCodexService.shared.testConnection()
            feedback = "Connected: \(status)"
            HapticManager.shared.playSuccess()
        } catch {
            feedback = error.localizedDescription
            HapticManager.shared.playFailure()
        }
        isTesting = false
    }

    private func testChatAPI() async {
        isTestingChat = true
        chatFeedback = nil
        do {
            try await ChatService.shared.testConnection()
            chatFeedback = "Chat API connected."
            HapticManager.shared.playSuccess()
        } catch {
            chatFeedback = error.localizedDescription
            HapticManager.shared.playFailure()
        }
        isTestingChat = false
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View { SettingsView() }
}
