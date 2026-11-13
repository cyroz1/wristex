import Foundation
import SwiftUI

enum ScreenshotMode {
    static let route: String? = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--screenshot-view"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
        #else
        return nil
        #endif
    }()

    static var isEnabled: Bool { route != nil }
}

enum ScreenshotFixtures {
    static let workspacePath = "/Users/demo/Projects/Wristex"

    static let thread = AgentThread(
        id: "screenshot-thread",
        title: "Refine the watch experience",
        lastMessage: "The thread controls and file browser are ready to review.",
        activeModel: "gpt-5",
        status: AgentThreadStatus(kind: .idle),
        cwd: workspacePath,
        settings: ThreadSettings(
            reasoningEffort: "high",
            approvalPolicy: .onRequest,
            sandboxPolicy: .workspaceWrite,
            reasoningSummary: .concise
        )
    )

    static let threadMessages = [
        ThreadMessage(sender: "user", content: "Can you tighten the Watch controls and keep the file previews readable?", timestamp: Date(timeIntervalSince1970: 1_762_900_000)),
        ThreadMessage(sender: "agent", content: "I’ll keep the controls compact, show a clear diff, and preserve the project folder for this thread.", timestamp: Date(timeIntervalSince1970: 1_762_900_060))
    ]

    static let chatMessages = [
        ChatMessage(role: .user, text: "Give me a quick summary of today’s changes."),
        ChatMessage(role: .assistant, text: "The Watch app now has thread controls, safer Git actions, and a compact remote file browser.")
    ]

    static let models = [
        ModelOption(id: "default", name: "Host Default"),
        ModelOption(id: "gpt-5", name: "GPT-5", reasoningEfforts: ["low", "medium", "high"]),
        ModelOption(id: "gpt-5-mini", name: "GPT-5 mini", reasoningEfforts: ["low", "medium"])
    ]

    static let goal = AgentThreadGoal(
        threadID: thread.id,
        objective: "Finish the Watch interface polish",
        status: .active,
        tokenBudget: 20_000,
        tokensUsed: 4_820,
        timeUsedSeconds: 1_230,
        updatedAt: 1_762_900_000
    )

    static let commandApproval = ApprovalRequest(
        id: "screenshot-command",
        toolName: "run_command",
        details: "$ git status --short && git diff --stat",
        status: "pending",
        timestamp: Date(timeIntervalSince1970: 1_762_900_100),
        responseMethod: "item/commandExecution/requestApproval",
        threadID: thread.id,
        turnID: "screenshot-turn"
    )

    static let permissionApproval = ApprovalRequest(
        id: "screenshot-permissions",
        toolName: "request_permissions",
        details: "Network access\nWrite: /Users/demo/Projects/Wristex",
        status: "pending",
        timestamp: Date(timeIntervalSince1970: 1_762_900_120),
        responseMethod: "item/permissions/requestApproval",
        threadID: thread.id,
        turnID: "screenshot-turn"
    )

    static let inputApproval = ApprovalRequest(
        id: "screenshot-input",
        toolName: "user_input",
        details: "Codex needs a few details before it can continue.",
        status: "pending",
        timestamp: Date(timeIntervalSince1970: 1_762_900_140),
        responseMethod: "item/tool/requestUserInput",
        threadID: thread.id,
        turnID: "screenshot-turn",
        questions: [
            ApprovalQuestion(
                id: "environment",
                header: "Environment",
                question: "Which environment should I use?",
                isOther: false,
                isSecret: false,
                options: [
                    ApprovalQuestionOption(label: "Development", description: "Local development environment"),
                    ApprovalQuestionOption(label: "Staging", description: "Shared staging environment")
                ]
            ),
            ApprovalQuestion(
                id: "token",
                header: "Token",
                question: "Enter the deployment token.",
                isOther: false,
                isSecret: true,
                options: nil
            )
        ],
        isBlocking: true
    )

    static let mcpApproval = ApprovalRequest(
        id: "screenshot-mcp",
        toolName: "mcp_input",
        details: "Release service\nChoose the deployment region.",
        status: "pending",
        timestamp: Date(timeIntervalSince1970: 1_762_900_160),
        responseMethod: "mcpServer/elicitation/request",
        threadID: thread.id,
        turnID: "screenshot-turn",
        formFields: [
            ApprovalFormField(
                name: "region",
                title: "Region",
                description: "Where should the release be deployed?",
                kind: "singleSelect",
                required: true,
                isSecret: false,
                defaultValue: nil,
                options: [
                    ApprovalQuestionOption(label: "US East", description: "us-east-1"),
                    ApprovalQuestionOption(label: "EU West", description: "eu-west-1")
                ]
            ),
            ApprovalFormField(
                name: "notify",
                title: "Notify the team",
                description: "Send a release notification.",
                kind: "boolean",
                required: false,
                isSecret: false,
                defaultValue: "true",
                options: nil
            )
        ],
        elicitationMode: "form"
    )

    static let deviceVerificationApproval = ApprovalRequest(
        id: "screenshot-device-verification",
        toolName: "mcp_input",
        details: "Verify this device\nContinue with a secure account approval.",
        status: "pending",
        timestamp: Date(timeIntervalSince1970: 1_762_900_180),
        responseMethod: "mcpServer/elicitation/request",
        threadID: thread.id,
        turnID: "screenshot-turn",
        elicitationMode: "openai/userVerification"
    )

    static let approvals = [commandApproval, permissionApproval, inputApproval, mcpApproval, deviceVerificationApproval]

    static let gitStatus = GitStatus(
        branch: "feature/watch-polish",
        modifiedFiles: [
            "WristexWatch/Services/RemoteCodexService.swift",
            "README.md"
        ],
        untrackedFiles: ["WristexWatch/Views/Workspace/PreviewCard.swift"],
        ahead: 2,
        behind: 0
    )

    static let directoryEntries = [
        RemoteFileEntry(path: workspacePath + "/WristexWatch", name: "WristexWatch", kind: .directory),
        RemoteFileEntry(path: workspacePath + "/README.md", name: "README.md", kind: .file, byteSize: 4_280),
        RemoteFileEntry(path: workspacePath + "/Package.swift", name: "Package.swift", kind: .file, byteSize: 1_024),
        RemoteFileEntry(path: workspacePath + "/Assets", name: "Assets", kind: .symbolicLink)
    ]

    static let fileContents = RemoteFileContents(
        text: "# Wristex\n\nA focused Codex companion for Apple Watch.\n\n## Workflows\n\n- Review remote threads\n- Approve tool requests\n- Inspect Git changes",
        byteSize: 132,
        wasTruncated: false
    )

    static let diff = """
    diff --git a/WristexWatch/Views/Thread/ThreadDetailView.swift b/WristexWatch/Views/Thread/ThreadDetailView.swift
    index 2f1a8c1..9b2e8fd 100644
    --- a/WristexWatch/Views/Thread/ThreadDetailView.swift
    +++ b/WristexWatch/Views/Thread/ThreadDetailView.swift
    @@ -42,7 +42,8 @@ struct ThreadDetailView: View {
     private var composer: some View {
    -    TextField("Message…", text: $inputText)
    +    TextField("Message…", text: $inputText)
    +        .submitLabel(.send)
     }
    """
}

struct ScreenshotCaptureView: View {
    let route: String
    @State private var host = "codex.example.test"
    @State private var username = "developer"
    @State private var portText = "22"
    @State private var workspacePath = ScreenshotFixtures.workspacePath
    @State private var sshAuthenticationMethod: SSHAuthenticationMethod = .password
    @State private var sshKeyAuthenticationMethod: SSHAuthenticationMethod = .privateKey
    @State private var sshPassword = ""
    @State private var privateKeyPEM = ""
    @State private var privateKeyPassphrase = ""
    @State private var chatAPIKey = ""
    @State private var chatModel = "gpt-5-mini"
    @State private var availableChatModels = ["gpt-5-mini", "gpt-5"]
    @State private var isLoadingChatModels = false
    @State private var isTestingChat = false
    @State private var chatFeedback: String?

    var body: some View {
        Group {
            switch route {
            case "tabs":
                MainTabView()
            case "chat":
                NavigationStack { ChatView() }
            case "threads":
                NavigationStack {
                    ThreadListView()
                        .environmentObject(ThreadListViewModel())
                }
            case "threads-empty":
                NavigationStack {
                    ThreadListView()
                        .environmentObject(ThreadListViewModel(screenshotEmpty: true))
                }
            case "new-thread":
                NavigationStack {
                    ThreadListView(screenshotNewThread: true)
                        .environmentObject(ThreadListViewModel())
                }
            case "thread-detail":
                NavigationStack { ThreadDetailView(thread: ScreenshotFixtures.thread) }
            case "thread-models":
                NavigationStack {
                    ThreadDetailView(thread: ScreenshotFixtures.thread, screenshotSheet: "models")
                }
            case "thread-reasoning":
                NavigationStack {
                    ThreadDetailView(thread: ScreenshotFixtures.thread, screenshotSheet: "reasoning")
                }
            case "thread-controls":
                NavigationStack {
                    ThreadControlsView(viewModel: ThreadDetailViewModel(thread: ScreenshotFixtures.thread))
                }
            case "approvals":
                NavigationStack {
                    ApprovalListView()
                        .environmentObject(ApprovalViewModel())
                }
            case "approval-command":
                approvalDetail(ScreenshotFixtures.commandApproval)
            case "approval-permissions":
                approvalDetail(ScreenshotFixtures.permissionApproval)
            case "approval-input":
                approvalDetail(ScreenshotFixtures.inputApproval)
            case "approval-mcp":
                approvalDetail(ScreenshotFixtures.mcpApproval)
            case "approval-device-verification":
                approvalDetail(ScreenshotFixtures.deviceVerificationApproval)
            case "git":
                NavigationStack {
                    GitStatusView()
                        .environmentObject(GitViewModel(workspacePath: ScreenshotFixtures.workspacePath))
                }
            case "git-commit":
                NavigationStack {
                    GitStatusView(screenshotCommitSheet: true)
                        .environmentObject(GitViewModel(workspacePath: ScreenshotFixtures.workspacePath))
                }
            case "settings":
                NavigationStack { SettingsView() }
            case "ssh-host":
                NavigationStack {
                    SSHConnectionSettingsView(
                        host: $host,
                        username: $username,
                        portText: $portText,
                        workspacePath: $workspacePath
                    )
                }
            case "ssh-auth":
                NavigationStack {
                    SSHAuthenticationSettingsView(
                        authenticationMethod: $sshAuthenticationMethod,
                        password: $sshPassword,
                        privateKeyPEM: $privateKeyPEM,
                        privateKeyPassphrase: $privateKeyPassphrase
                    )
                }
            case "ssh-auth-key":
                NavigationStack {
                    SSHAuthenticationSettingsView(
                        authenticationMethod: $sshKeyAuthenticationMethod,
                        password: $sshPassword,
                        privateKeyPEM: $privateKeyPEM,
                        privateKeyPassphrase: $privateKeyPassphrase
                    )
                }
            case "chat-settings":
                NavigationStack {
                    ChatSettingsView(
                        apiKey: $chatAPIKey,
                        model: $chatModel,
                        availableModels: $availableChatModels,
                        isLoadingModels: $isLoadingChatModels,
                        isTesting: $isTestingChat,
                        feedback: $chatFeedback,
                        onTest: {}
                    )
                }
            case "workspace":
                NavigationStack {
                    WorkspaceBrowserView(rootPath: ScreenshotFixtures.workspacePath, screenshotMode: true)
                }
            case "file-preview":
                NavigationStack {
                    RemoteFilePreviewView(
                        filePath: ScreenshotFixtures.workspacePath + "/README.md",
                        fileName: "README.md",
                        screenshotMode: true
                    )
                }
            case "diff":
                NavigationStack {
                    RemoteFileDiffView(
                        filePath: "WristexWatch/Views/Thread/ThreadDetailView.swift",
                        workspacePath: ScreenshotFixtures.workspacePath,
                        isUntracked: false,
                        screenshotMode: true
                    )
                }
            default:
                Text("Unknown screenshot route: \(route)")
                    .font(.caption)
            }
        }
    }

    private func approvalDetail(_ request: ApprovalRequest) -> some View {
        NavigationStack {
            ApprovalDetailView(request: request)
                .environmentObject(ApprovalViewModel())
        }
    }
}
