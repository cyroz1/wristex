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
    @State private var availableChatModels: [String] = []
    @State private var isTesting = false
    @State private var isTestingChat = false
    @State private var isLoadingChatModels = false
    @State private var feedback: String?
    @State private var chatFeedback: String?
    @State private var didLoadSettings = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            CompactWatchHeader("Settings") {
                if isTesting || isTestingChat {
                    ProgressView()
                        .scaleEffect(0.55)
                }
            }

            List {
            Section("Connection") {
                NavigationLink {
                    SSHConnectionSettingsView(
                        host: $localHost,
                        username: $localUsername,
                        portText: $localPortText,
                        workspacePath: $localWorkspacePath
                    )
                } label: {
                    SettingsRow(
                        title: "SSH host",
                        value: connectionSummary,
                        systemImage: "network"
                    )
                }

                NavigationLink {
                    SSHAuthenticationSettingsView(
                        password: $localPassword,
                        privateKeyPEM: $localPrivateKeyPEM,
                        privateKeyPassphrase: $localPrivateKeyPassphrase
                    )
                } label: {
                    SettingsRow(
                        title: "Authentication",
                        value: authenticationSummary,
                        systemImage: "key.fill"
                    )
                }
            }

            Section("Chat") {
                NavigationLink {
                    ChatSettingsView(
                        apiKey: $localOpenAIAPIKey,
                        model: $localChatModel,
                        availableModels: $availableChatModels,
                        isLoadingModels: $isLoadingChatModels,
                        isTesting: $isTestingChat,
                        feedback: $chatFeedback,
                        onTest: {
                            ChatService.shared.configure(apiKey: localOpenAIAPIKey, model: localChatModel)
                            Task { await testChatAPI() }
                        }
                    )
                } label: {
                    SettingsRow(
                        title: "Chat API",
                        value: chatSummary,
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
            }

            Section("Actions") {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    Label(isTesting ? "Testing…" : "Save & Test", systemImage: "bolt.horizontal.fill")
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
                        .lineLimit(2)
                }
            }
            }
            .listRowInsets(EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3))
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didLoadSettings else { return }
            didLoadSettings = true
            sshManager.reloadConfigDefaults()
            loadSettings()
            Task { await loadChatModels() }
        }
    }

    private var connectionSummary: String {
        let host = localHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return "Not configured" }
        let user = localUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = localPortText.isEmpty ? "22" : localPortText
        return user.isEmpty ? "\(host):\(port)" : "\(user)@\(host):\(port)"
    }

    private var authenticationSummary: String {
        if !localPrivateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Private key"
        }
        if !localPassword.isEmpty { return "Password" }
        return "Not configured"
    }

    private var chatSummary: String {
        guard !localOpenAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "API key not set"
        }
        return localChatModel
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
        availableChatModels = ChatService.shared.availableModels
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
        availableChatModels = []
        do {
            let models = try await ChatService.shared.refreshAvailableModels()
            applyChatModels(models)
            chatFeedback = "Chat API connected."
            HapticManager.shared.playSuccess()
        } catch {
            chatFeedback = error.localizedDescription
            HapticManager.shared.playFailure()
        }
        isTestingChat = false
    }

    private func loadChatModels() async {
        guard ChatService.shared.isConfigured else { return }
        isLoadingChatModels = true
        defer { isLoadingChatModels = false }

        guard let models = try? await ChatService.shared.refreshAvailableModels() else { return }
        applyChatModels(models)
    }

    private func applyChatModels(_ models: [String]) {
        availableChatModels = models
        guard !models.contains(localChatModel), let newestModel = models.first else { return }

        localChatModel = newestModel
        let key = localOpenAIAPIKey.isEmpty ? ChatService.shared.apiKey : localOpenAIAPIKey
        ChatService.shared.configure(apiKey: key, model: newestModel)
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.indigo)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(value)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SSHConnectionSettingsView: View {
    @Binding var host: String
    @Binding var username: String
    @Binding var portText: String
    @Binding var workspacePath: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsBackHeader(title: "SSH Host", dismiss: dismiss)
            Form {
                Section("Server") {
                    TextField("Hostname", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    TextField("Port", text: $portText)
                }

                Section("Workspace") {
                    TextField("Remote path", text: $workspacePath)
                        .autocorrectionDisabled()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SSHAuthenticationSettingsView: View {
    @Binding var password: String
    @Binding var privateKeyPEM: String
    @Binding var privateKeyPassphrase: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsBackHeader(title: "Authentication", dismiss: dismiss)
            Form {
                Section("Credentials") {
                    SecureField("SSH password", text: $password)
                        .textContentType(.password)
                    SecureField("PEM private key", text: $privateKeyPEM)
                    SecureField("Key passphrase", text: $privateKeyPassphrase)
                        .textContentType(.password)
                }

                Section {
                    Text("Saved in Keychain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ChatSettingsView: View {
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var availableModels: [String]
    @Binding var isLoadingModels: Bool
    @Binding var isTesting: Bool
    @Binding var feedback: String?
    let onTest: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SettingsBackHeader(title: "Chat API", dismiss: dismiss)
            Form {
                Section("API key") {
                    SecureField("OpenAI API key", text: $apiKey)
                        .textContentType(.password)
                    Text("Stored securely in Keychain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section("Model") {
                    if availableModels.isEmpty {
                        Text(model)
                            .font(.caption)
                        if isLoadingModels {
                            ProgressView("Loading…")
                        } else {
                            Text("Test the API to load the newest models.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Chat model", selection: $model) {
                            ForEach(availableModels, id: \.self) { availableModel in
                                Text(availableModel).tag(availableModel)
                            }
                        }
                        Text("Newest 5 text models for this key")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: onTest) {
                        Label(isTesting ? "Testing…" : "Test API", systemImage: "checkmark.circle")
                    }
                    .disabled(isTesting)

                    if let feedback {
                        Text(feedback)
                            .font(.caption2)
                            .foregroundColor(feedback.hasPrefix("Chat API connected") ? .green : .red)
                            .lineLimit(3)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SettingsBackHeader: View {
    let title: String
    let dismiss: DismissAction

    var body: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 25, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer()
        }
        .frame(height: 26)
        .padding(.horizontal, 3)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View { SettingsView() }
}
