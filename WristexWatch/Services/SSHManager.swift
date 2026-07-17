import Foundation
import Combine

#if canImport(WatchKit)
import WatchKit
#endif

public final class SSHManager: ObservableObject {
    public static let shared = SSHManager()
    
    // Published properties persisted in UserDefaults
    @Published public var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "wristex_ssh_host") }
    }
    
    @Published public var username: String {
        didSet { UserDefaults.standard.set(username, forKey: "wristex_ssh_username") }
    }
    
    @Published public var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "wristex_ssh_port") }
    }
    
    @Published public var remoteWorkspacePath: String {
        didSet { UserDefaults.standard.set(remoteWorkspacePath, forKey: "wristex_ssh_workspace") }
    }
    
    // For safety, passwords can be stored in Keychain in production.
    // For development, we store in UserDefaults or memory.
    @Published public var password: String {
        didSet { UserDefaults.standard.set(password, forKey: "wristex_ssh_password") }
    }
    
    private init() {
        self.host = UserDefaults.standard.string(forKey: "wristex_ssh_host") ?? "localhost"
        self.username = UserDefaults.standard.string(forKey: "wristex_ssh_username") ?? "amir"
        self.port = UserDefaults.standard.integer(forKey: "wristex_ssh_port")
        if self.port == 0 { self.port = 22 }
        self.remoteWorkspacePath = UserDefaults.standard.string(forKey: "wristex_ssh_workspace") ?? "/Users/amir/Documents/wristex"
        self.password = UserDefaults.standard.string(forKey: "wristex_ssh_password") ?? ""
    }
    
    /// Executes a command on the remote machine over SSH and returns stdout.
    /// In local development/macOS preview, this executes locally if the host is "localhost" or "127.0.0.1".
    public func executeCommand(_ command: String) async throws -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        #if os(macOS)
        if trimmedHost == "localhost" || trimmedHost == "127.0.0.1" {
            return try executeLocalCommand(command)
        }
        #endif
        
        // --- Production SSH client connection block ---
        // In actual watchOS execution, we would utilize a library like Shout or SwiftSSH:
        //
        // let connection = try SSH.connect(host: host, port: port, username: username, auth: .password(password))
        // let response = try connection.execute(command)
        // return response.stdout
        //
        // Since we are running in simulator/preview mode without the full third-party SSH framework linked,
        // we simulate a network response if not running on macOS local fallback.
        
        try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate network latency
        
        // Simulating return content based on the command requested
        if command.contains("git status") {
            return """
            On branch main
            Your branch is up to date with 'origin/main'.
            Changes not staged for commit:
              modified:   WristexWatch/Views/SettingsView.swift
              modified:   WristexWatch/Services/SSHManager.swift
            Untracked files:
              WristexWatch/Views/LoginView.swift
            """
        } else if command.contains("ls -la ~/.codex/threads/") {
            return """
            drwxr-xr-x  3 amir  staff   96 Jul 17 16:30 .
            drwxr-xr-x  4 amir  staff  128 Jul 17 16:30 ..
            -rw-r--r--  1 amir  staff  256 Jul 17 16:30 thread-1.json
            -rw-r--r--  1 amir  staff  256 Jul 17 16:30 thread-2.json
            """
        } else if command.contains("cat ~/.codex/threads/thread-1.json") {
            return """
            {
              "id": "thread-1",
              "title": "Build login layout",
              "lastMessage": "Should we add a FaceID toggle?",
              "activeModel": "gemini-1-5",
              "messages": [
                {"sender": "agent", "content": "Hello! I am ready to help you build the login layout.", "timestamp": "2026-07-17T20:26:00.000Z"},
                {"sender": "user", "content": "Great, use SwiftUI and SF Symbols for the buttons.", "timestamp": "2026-07-17T20:27:00.000Z"},
                {"sender": "agent", "content": "Got it. I have drafted a layout. Should we add a FaceID toggle?", "timestamp": "2026-07-17T20:28:00.000Z"}
              ]
            }
            """
        } else if command.contains("cat ~/.codex/pending_approvals.json") {
            return """
            [
              {
                "id": "appr-1",
                "toolName": "run_command",
                "details": "xcodebuild -scheme WristexWatch -destination \\"platform=watchOS Simulator\\"",
                "status": "pending",
                "timestamp": "2026-07-17T20:28:00.000Z"
              }
            ]
            """
        } else if command.contains("git pull") {
            return "Already up to date."
        } else if command.contains("git push") {
            return "Everything up-to-date"
        }
        
        return "SSH command succeeded (Simulated output)."
    }
    
    #if os(macOS)
    /// Runs a command locally on macOS using Process (only compiled on macOS dev environments).
    private func executeLocalCommand(_ command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        // Run inside zsh shell to support command line chains and cd
        process.arguments = ["-c", command]
        process.launchPath = "/bin/zsh"
        process.launch()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LocalCommandError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
        }
        
        return output
    }
    #endif
}
