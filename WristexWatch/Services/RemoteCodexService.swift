import Foundation
import AVFoundation
import SwiftSH

struct CodexTurnResult {
    let threadID: String
    let turnID: String
    let sessionID: String
    let reply: String
}

enum CodexAppServerError: LocalizedError {
    case notConnected
    case invalidResponse(String)
    case server(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Codex app server is not connected."
        case .invalidResponse(let message):
            return "Codex returned an invalid response. " + message
        case .server(let message):
            return message
        case .transport(let message):
            return "SSH app-server transport failed. " + message
        }
    }
}

@MainActor
final class WatchVoiceCapture {
    private let audioEngine = AVAudioEngine()
    private var audioSession: AVAudioSession?

    var onAudio: ((Data, Int, Int, Int) -> Void)?

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
        audioSession = session

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let data = Self.pcm16Data(from: buffer)
            let sampleRate = Int(buffer.format.sampleRate)
            let channels = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)
            DispatchQueue.main.async {
                self?.onAudio?(data, sampleRate, channels, frameCount)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? audioSession?.setActive(false)
        audioSession = nil
    }

    private static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data {
        guard let channels = buffer.floatChannelData else { return Data() }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var data = Data(capacity: frameCount * channelCount * 2)

        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sample = max(-1, min(1, channels[channel][frame]))
                var value = Int16(sample * Float(Int16.max))
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
        }
        return data
    }
}

/// A small JSON-RPC 2.0 client for `codex app-server --stdio`.
///
/// The SSH shell is deliberately kept open: app-server sends streamed events
/// and approval requests while a turn is running, so one-shot SSH commands
/// cannot provide desktop-style behavior.
@MainActor
final class CodexAppServerClient {
    static let shared = CodexAppServerClient()

    var onApprovalRequest: ((ApprovalRequest) -> Void)?
    var onNotification: ((String, [String: Any]) -> Void)?

    private let ssh = SSHManager.shared
    private var session: SSHSession?
    private var shell: SSHShell?
    private var readBuffer = Data()
    private var nextRequestID = 1
    private var isInitialized = false
    private var isConnecting = false
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var pendingApprovalMethods: [String: String] = [:]
    private var pendingApprovalRPCIDs: [String: Any] = [:]
    private var pendingApprovals: [String: ApprovalRequest] = [:]
    private var turnWaiters: [String: [CheckedContinuation<[String: Any], Error>]] = [:]
    private var completedTurns: [String: Result<[String: Any], Error>] = [:]

    private init() {}

    var approvals: [ApprovalRequest] {
        pendingApprovals.values.sorted { $0.timestamp > $1.timestamp }
    }

    func connect() async throws {
        if isInitialized { return }
        if isConnecting {
            while isConnecting && !isInitialized {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if isInitialized { return }
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            let newSession = try await ssh.openAuthenticatedSession()
            let newShell = try SSHShell(session: newSession)
            newSession.setCallbackQueue(queue: .main)
            session = newSession
            shell = newShell
            _ = newShell.withCallback { [weak self] (data: Data?, error: Data?) in
                Task { @MainActor [weak self] in
                    self?.receive(data: data, error: error)
                }
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                newShell.open { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }

            newShell.write(Data("exec codex app-server --stdio\n".utf8))

            let initializeParams: [String: Any] = [
                "clientInfo": [
                    "name": "wristex",
                    "title": "Wristex",
                    "version": "1.0"
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
            _ = try await sendRequest(method: "initialize", params: initializeParams)
            sendNotification(method: "initialized", params: [:])
            isInitialized = true
        } catch {
            await disconnect()
            throw error
        }
    }

    func disconnect() async {
        isInitialized = false
        isConnecting = false
        shell?.close(nil)
        if let session {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.disconnect { continuation.resume() }
            }
        }
        shell = nil
        session = nil
        readBuffer.removeAll(keepingCapacity: false)

        let error = CodexAppServerError.transport("The SSH channel closed.")
        pendingResponses.values.forEach { $0.resume(throwing: error) }
        pendingResponses.removeAll()
        pendingApprovalMethods.removeAll()
        pendingApprovalRPCIDs.removeAll()
        pendingApprovals.removeAll()
        turnWaiters.values.flatMap { $0 }.forEach { $0.resume(throwing: error) }
        turnWaiters.removeAll()
    }

    func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try await connect()
        return try await sendRequest(method: method, params: params)
    }

    func waitForTurn(_ turnID: String) async throws -> [String: Any] {
        if let completed = completedTurns.removeValue(forKey: turnID) {
            return try completed.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            turnWaiters[turnID, default: []].append(continuation)
        }
    }

    func respondToApproval(id: String, approve: Bool) async throws {
        guard let method = pendingApprovalMethods[id],
              let rpcID = pendingApprovalRPCIDs[id] else {
            throw CodexAppServerError.invalidResponse("Approval is no longer pending.")
        }

        let response: [String: Any]
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            response = ["decision": approve ? "accept" : "decline"]
        case "execCommandApproval":
            if approve {
                response = ["decision": "approved"]
            } else {
                response = ["decision": ["denied": ["rejection": "Denied on Wristex."]]]
            }
        case "applyPatchApproval":
            if approve {
                response = ["decision": "approved"]
            } else {
                response = ["decision": ["denied": ["rejection": "Denied on Wristex."]]]
            }
        case "item/tool/requestUserInput":
            // The watch UI currently exposes approve/deny. An empty answer map
            // lets Codex continue without fabricating an answer to the user.
            response = ["answers": [:]]
        case "mcpServer/elicitation/request":
            response = ["action": approve ? "accept" : "decline"]
        case "item/permissions/requestApproval":
            // Permission profiles are intentionally never guessed on a tiny
            // screen. Deny is safe; approval can be added with a dedicated UI.
            guard !approve else {
                throw CodexAppServerError.invalidResponse("Permission approval needs a dedicated scope picker.")
            }
            response = ["permissions": [:], "scope": "turn"]
        default:
            throw CodexAppServerError.invalidResponse("Unsupported approval type.")
        }

        try sendResponse(id: rpcID, result: response)
        pendingApprovalMethods.removeValue(forKey: id)
        pendingApprovalRPCIDs.removeValue(forKey: id)
        pendingApprovals.removeValue(forKey: id)
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard let shell else { throw CodexAppServerError.notConnected }
        let id = String(nextRequestID)
        nextRequestID += 1

        let envelope: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]
        guard JSONSerialization.isValidJSONObject(envelope) else {
            throw CodexAppServerError.invalidResponse("Request \(method) could not be encoded.")
        }
        let data = try JSONSerialization.data(withJSONObject: envelope) + Data([10])

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[id] = continuation
            shell.write(data) { [weak self] error in
                guard let self, let error else { return }
                Task { @MainActor in
                    self.pendingResponses.removeValue(forKey: id)?.resume(
                        throwing: CodexAppServerError.transport(error.localizedDescription)
                    )
                }
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        guard let shell,
              let data = try? JSONSerialization.data(withJSONObject: [
                "method": method,
                "params": params
              ]) else { return }
        shell.write(data + Data([10]))
    }

    private func sendResponse(id: Any, result: [String: Any]) throws {
        guard let shell else { throw CodexAppServerError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "result": result
        ]) + Data([10])
        shell.write(data)
    }

    private func sendError(id: Any, code: Int, message: String) throws {
        guard let shell else { throw CodexAppServerError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "error": ["code": code, "message": message]
        ]) + Data([10])
        shell.write(data)
    }

    private func receive(data: Data?, error: Data?) {
        // `SSHShell` exposes stderr separately. Codex can legitimately write
        // diagnostics there while still sending valid JSON-RPC on stdout, so
        // stderr is not treated as a transport failure.
        guard let data, !data.isEmpty else { return }
        readBuffer.append(data)

        while let newline = readBuffer.firstIndex(of: 10) {
            let line = readBuffer.subdata(in: 0..<newline)
            readBuffer.removeSubrange(0...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                // A remote shell banner or warning is ignored. JSON-RPC lines
                // are the only messages that affect the client state.
                continue
            }
            handle(object)
        }
    }

    private func handle(_ object: [String: Any]) {
        if let method = object["method"] as? String {
            if let id = object["id"] {
                handleServerRequest(rawID: id, method: method, params: object["params"] as? [String: Any] ?? [:])
            } else {
                handleNotification(method: method, params: object["params"] as? [String: Any] ?? [:])
            }
            return
        }

        guard let rawID = object["id"] else { return }
        let id = rpcID(rawID)
        guard let continuation = pendingResponses.removeValue(forKey: id) else { return }

        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Codex app-server request failed."
            continuation.resume(throwing: CodexAppServerError.server(message))
        } else {
            continuation.resume(returning: object["result"] as? [String: Any] ?? [:])
        }
    }

    private func handleServerRequest(rawID: Any, method: String, params: [String: Any]) {
        if method == "currentTime/read" {
            try? sendResponse(id: rawID, result: [
                "currentTimeAt": Int(Date().timeIntervalSince1970)
            ])
            return
        }

        guard method.contains("Approval") || method.contains("requestApproval") || method == "item/tool/requestUserInput" || method == "mcpServer/elicitation/request" else {
            try? sendError(id: rawID, code: -32601, message: "Wristex does not implement " + method + ".")
            return
        }

        let id = rpcID(rawID)
        pendingApprovalMethods[id] = method
        pendingApprovalRPCIDs[id] = rawID
        let request = ApprovalRequest(
            id: id,
            toolName: toolName(for: method),
            details: approvalDetails(for: method, params: params),
            status: "pending",
            timestamp: approvalDate(params),
            responseMethod: method,
            threadID: params["threadId"] as? String,
            turnID: params["turnId"] as? String
        )
        pendingApprovals[id] = request
        onApprovalRequest?(request)
    }

    private func handleNotification(method: String, params: [String: Any]) {
        onNotification?(method, params)

        guard method == "turn/completed",
              let turn = params["turn"] as? [String: Any],
              let turnID = turn["id"] as? String else { return }

        let status = turn["status"] as? String ?? "completed"
        let result: Result<[String: Any], Error>
        if status != "completed" {
            let error = (turn["error"] as? [String: Any])?["message"] as? String ?? ("Codex turn " + status + ".")
            result = .failure(CodexAppServerError.server(error))
        } else {
            result = .success(turn)
        }

        if let waiters = turnWaiters.removeValue(forKey: turnID) {
            waiters.forEach { $0.resume(with: result) }
        } else {
            completedTurns[turnID] = result
        }
    }

    private func failPending(_ error: Error) {
        pendingResponses.values.forEach { $0.resume(throwing: error) }
        pendingResponses.removeAll()
        turnWaiters.values.flatMap { $0 }.forEach { $0.resume(throwing: error) }
        turnWaiters.removeAll()
    }

    private func rpcID(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private func toolName(for method: String) -> String {
        switch method {
        case "item/commandExecution/requestApproval", "execCommandApproval": return "run_command"
        case "item/fileChange/requestApproval", "applyPatchApproval": return "write_file"
        case "item/permissions/requestApproval": return "request_permissions"
        case "item/tool/requestUserInput": return "user_input"
        case "mcpServer/elicitation/request": return "mcp_input"
        default: return method
        }
    }

    private func approvalDetails(for method: String, params: [String: Any]) -> String {
        if method.contains("commandExecution"), let command = params["command"] as? String {
            return "$ " + command
        }
        if method == "execCommandApproval", let command = params["command"] as? String {
            return "$ " + command
        }
        if method.contains("fileChange") || method == "applyPatchApproval" {
            return params["reason"] as? String ?? "Codex wants to change files."
        }
        if let reason = params["reason"] as? String, !reason.isEmpty { return reason }
        if let server = params["serverName"] as? String { return "MCP server: " + server }
        if let questions = params["questions"] as? [[String: Any]] {
            return questions.compactMap { $0["question"] as? String }.joined(separator: "\n")
        }
        return "Codex is waiting for a decision."
    }

    private func approvalDate(_ params: [String: Any]) -> Date {
        if let milliseconds = params["startedAtMs"] as? NSNumber {
            return Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000)
        }
        return Date()
    }
}

@MainActor
final class RemoteCodexService {
    static let shared = RemoteCodexService()

    private let client = CodexAppServerClient.shared
    private let ssh = SSHManager.shared
    private var activeTurnIDs: [String: String] = [:]
    private var voiceCapture: WatchVoiceCapture?

    private init() {}

    var approvals: [ApprovalRequest] { client.approvals }

    func connect() async throws {
        try await client.connect()
    }

    func setApprovalHandler(_ handler: ((ApprovalRequest) -> Void)?) {
        client.onApprovalRequest = handler
    }

    func setNotificationHandler(_ handler: ((String, [String: Any]) -> Void)?) {
        client.onNotification = handler
    }

    func respondToApproval(id: String, approve: Bool) async throws {
        try await client.respondToApproval(id: id, approve: approve)
    }

    func listThreads() async throws -> [AgentThread] {
        var params: [String: Any] = [
            "archived": false,
            "limit": 100,
            "sortKey": "recency_at",
            "sortDirection": "desc",
            "sourceKinds": []
        ]
        if !ssh.remoteWorkspacePath.isEmpty {
            params["cwd"] = ssh.remoteWorkspacePath
        }
        let response = try await client.request("thread/list", params: params)
        let data = response["data"] as? [[String: Any]] ?? []
        return data.compactMap(makeThread)
    }

    func createThread(title: String) async throws -> AgentThread {
        var params: [String: Any] = [
            "sandbox": "workspace-write",
            "approvalPolicy": "on-request",
            "historyMode": "paginated"
        ]
        if !ssh.remoteWorkspacePath.isEmpty {
            params["cwd"] = ssh.remoteWorkspacePath
        }
        let response = try await client.request("thread/start", params: params)
        guard let thread = response["thread"] as? [String: Any],
              let result = makeThread(thread) else {
            throw CodexAppServerError.invalidResponse("thread/start did not return a thread.")
        }

        if !title.isEmpty {
            _ = try? await client.request("thread/name/set", params: [
                "threadId": result.id,
                "name": title
            ])
        }
        var named = result
        named.title = title.isEmpty ? result.title : title
        return named
    }

    func readMessages(threadID: String) async throws -> [ThreadMessage] {
        let response = try await client.request("thread/items/list", params: [
            "threadId": threadID,
            "limit": 200,
            "sortDirection": "asc"
        ])
        let entries = response["data"] as? [[String: Any]] ?? []
        var messages: [ThreadMessage] = []

        for entry in entries {
            guard let item = entry["item"] as? [String: Any],
                  let type = item["type"] as? String else { continue }

            let sender: String
            let content: String
            switch type {
            case "userMessage":
                sender = "user"
                content = textFromUserInput(item["content"])
            case "agentMessage":
                sender = "agent"
                content = item["text"] as? String ?? ""
            case "plan":
                sender = "agent"
                content = item["text"] as? String ?? ""
            default:
                continue
            }
            guard !content.isEmpty else { continue }
            let id = UUID(uuidString: item["id"] as? String ?? "") ?? UUID()
            messages.append(ThreadMessage(id: id, sender: sender, content: content, timestamp: Date()))
        }
        return messages
    }

    func loadModels() async throws -> [ModelOption] {
        let response = try await client.request("model/list", params: [
            "includeHidden": false,
            "limit": 100
        ])
        let data = response["data"] as? [[String: Any]] ?? []
        return data.compactMap { model in
            guard let id = model["id"] as? String else { return nil }
            let name = model["displayName"] as? String ?? id
            let reasoningEfforts = (model["supportedReasoningEfforts"] as? [[String: Any]] ?? [])
                .compactMap { $0["reasoningEffort"] as? String }
            let supportsPersonality = model["supportsPersonality"] as? Bool ?? false
            return ModelOption(
                id: id,
                name: name,
                reasoningEfforts: reasoningEfforts,
                supportsPersonality: supportsPersonality
            )
        }
    }

    func updateThreadModel(_ threadID: String, modelID: String) async throws {
        var params: [String: Any] = ["threadId": threadID]
        if modelID == "default" {
            params["model"] = NSNull()
        } else {
            params["model"] = modelID
        }
        _ = try await client.request("thread/settings/update", params: params)
    }

    func updateThreadSettings(_ threadID: String, settings: ThreadSettings) async throws {
        let params: [String: Any] = [
            "threadId": threadID,
            "effort": settings.reasoningEffort ?? NSNull(),
            "personality": settings.personality.serverValue ?? NSNull(),
            "approvalPolicy": settings.approvalPolicy.rawValue,
            "sandboxPolicy": settings.sandboxPolicy.serverValue ?? NSNull(),
            "summary": settings.reasoningSummary.serverValue ?? NSNull()
        ]
        _ = try await client.request("thread/settings/update", params: params)
    }

    func loadGoal(threadID: String) async throws -> AgentThreadGoal? {
        let response = try await client.request("thread/goal/get", params: ["threadId": threadID])
        guard let goal = response["goal"] as? [String: Any] else { return nil }
        return makeGoal(goal)
    }

    func setGoal(
        threadID: String,
        objective: String,
        status: AgentThreadGoalStatus = .active,
        tokenBudget: Int64? = nil
    ) async throws -> AgentThreadGoal? {
        var params: [String: Any] = [
            "threadId": threadID,
            "objective": objective,
            "status": status.rawValue
        ]
        params["tokenBudget"] = tokenBudget.map { NSNumber(value: $0) } ?? NSNull()
        let response = try await client.request("thread/goal/set", params: params)
        guard let goal = response["goal"] as? [String: Any] else { return nil }
        return makeGoal(goal)
    }

    func clearGoal(threadID: String) async throws {
        _ = try await client.request("thread/goal/clear", params: ["threadId": threadID])
    }

    func archiveThread(_ threadID: String) async throws {
        _ = try await client.request("thread/archive", params: ["threadId": threadID])
    }

    func deleteThread(_ threadID: String) async throws {
        _ = try await client.request("thread/delete", params: ["threadId": threadID])
    }

    func interrupt(threadID: String) async throws {
        guard let turnID = activeTurnIDs[threadID] else {
            throw CodexAppServerError.invalidResponse("No active turn is running for this thread.")
        }
        _ = try await client.request("turn/interrupt", params: [
            "threadId": threadID,
            "turnId": turnID
        ])
    }

    func startVoiceTranscription(threadID: String) async throws {
        guard await WatchVoiceCapture.requestPermission() else {
            throw CodexAppServerError.invalidResponse("Microphone access was denied.")
        }
        _ = try await client.request("thread/resume", params: [
            "threadId": threadID,
            "excludeTurns": true
        ])
        _ = try await client.request("thread/realtime/start", params: [
            "threadId": threadID,
            "outputModality": "text",
            "transport": ["type": "websocket"]
        ])

        let capture = WatchVoiceCapture()
        capture.onAudio = { [weak self] data, sampleRate, channels, frameCount in
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                try? await self?.appendVoiceAudio(
                    threadID: threadID,
                    data: data,
                    sampleRate: sampleRate,
                    channels: channels,
                    frameCount: frameCount
                )
            }
        }
        do {
            try capture.start()
            voiceCapture = capture
        } catch {
            _ = try? await client.request("thread/realtime/stop", params: ["threadId": threadID])
            throw error
        }
    }

    func stopVoiceTranscription(threadID: String) async throws {
        voiceCapture?.stop()
        voiceCapture = nil
        _ = try await client.request("thread/realtime/stop", params: ["threadId": threadID])
    }

    private func appendVoiceAudio(
        threadID: String,
        data: Data,
        sampleRate: Int,
        channels: Int,
        frameCount: Int
    ) async throws {
        _ = try await client.request("thread/realtime/appendAudio", params: [
            "threadId": threadID,
            "audio": [
                "data": data.base64EncodedString(),
                "sampleRate": sampleRate,
                "numChannels": channels,
                "samplesPerChannel": frameCount
            ]
        ])
    }

    func send(_ prompt: String, thread: AgentThread) async throws -> CodexTurnResult {
        var resumeParams: [String: Any] = [
            "threadId": thread.id,
            "excludeTurns": true
        ]
        if !ssh.remoteWorkspacePath.isEmpty { resumeParams["cwd"] = ssh.remoteWorkspacePath }
        if thread.activeModel != "default" { resumeParams["model"] = thread.activeModel }
        let resumed = try await client.request("thread/resume", params: resumeParams)
        let remoteThread = resumed["thread"] as? [String: Any]
        let sessionID = remoteThread?["sessionId"] as? String ?? thread.codexSessionID ?? thread.id

        var turnParams: [String: Any] = [
            "threadId": thread.id,
            "input": [["type": "text", "text": prompt]],
            "clientUserMessageId": UUID().uuidString
        ]
        if thread.activeModel != "default" { turnParams["model"] = thread.activeModel }
        let started = try await client.request("turn/start", params: turnParams)
        guard let turn = started["turn"] as? [String: Any],
              let turnID = turn["id"] as? String else {
            throw CodexAppServerError.invalidResponse("turn/start did not return a turn.")
        }

        activeTurnIDs[thread.id] = turnID
        defer { activeTurnIDs.removeValue(forKey: thread.id) }
        let completed = try await client.waitForTurn(turnID)
        let reply = lastAgentMessage(in: completed["items"] as? [[String: Any]] ?? [])
        if reply.isEmpty {
            let messages = try await readMessages(threadID: thread.id)
            guard let last = messages.last(where: { $0.sender == "agent" }) else {
                throw CodexAppServerError.invalidResponse("The turn completed without an assistant message.")
            }
            return CodexTurnResult(threadID: thread.id, turnID: turnID, sessionID: sessionID, reply: last.content)
        }
        return CodexTurnResult(threadID: thread.id, turnID: turnID, sessionID: sessionID, reply: reply)
    }

    func testConnection() async throws -> String {
        try await connect()
        let models = try await loadModels()
        return models.isEmpty ? "Codex app server connected" : "Codex app server connected · " + String(models.count) + " models"
    }

    private func makeThread(_ value: [String: Any]) -> AgentThread? {
        guard let id = value["id"] as? String else { return nil }
        let preview = value["preview"] as? String ?? ""
        let name = value["name"] as? String
        return AgentThread(
            id: id,
            title: name?.isEmpty == false ? name! : (preview.isEmpty ? "Untitled thread" : preview),
            lastMessage: preview.isEmpty ? "Ready" : preview,
            activeModel: "default",
            codexSessionID: value["sessionId"] as? String,
            connectionID: ssh.connectionID,
            status: makeStatus(value["status"]),
            isPinned: value["isPinned"] as? Bool ?? false,
            cwd: value["cwd"] as? String
        )
    }

    private func makeStatus(_ value: Any?) -> AgentThreadStatus {
        guard let raw = value as? [String: Any],
              let type = raw["type"] as? String,
              let kind = AgentThreadStatusKind(rawValue: type) else {
            return AgentThreadStatus()
        }
        let flags = (raw["activeFlags"] as? [String] ?? [])
            .compactMap(AgentThreadActiveFlag.init(rawValue:))
        return AgentThreadStatus(kind: kind, activeFlags: flags)
    }

    private func makeGoal(_ value: [String: Any]) -> AgentThreadGoal? {
        guard let threadID = value["threadId"] as? String,
              let objective = value["objective"] as? String,
              let statusValue = value["status"] as? String,
              let status = AgentThreadGoalStatus(rawValue: statusValue) else {
            return nil
        }
        return AgentThreadGoal(
            threadID: threadID,
            objective: objective,
            status: status,
            tokenBudget: (value["tokenBudget"] as? NSNumber)?.int64Value,
            tokensUsed: (value["tokensUsed"] as? NSNumber)?.int64Value ?? 0,
            timeUsedSeconds: (value["timeUsedSeconds"] as? NSNumber)?.int64Value ?? 0,
            updatedAt: (value["updatedAt"] as? NSNumber)?.int64Value ?? 0
        )
    }

    private func textFromUserInput(_ value: Any?) -> String {
        guard let inputs = value as? [[String: Any]] else { return "" }
        return inputs.compactMap { input in
            guard input["type"] as? String == "text" else { return nil }
            return input["text"] as? String
        }.joined()
    }

    private func lastAgentMessage(in items: [[String: Any]]) -> String {
        items.reversed().first(where: { $0["type"] as? String == "agentMessage" })?["text"] as? String ?? ""
    }
}
