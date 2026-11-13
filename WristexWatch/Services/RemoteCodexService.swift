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
    case timeout(String)

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
        case .timeout(let method):
            return "Codex app-server did not respond to \(method). Check that the remote CLI is running and try again."
        }
    }
}

@MainActor
final class WatchVoiceCapture {
    private let audioEngine = AVAudioEngine()
    private let capturedAudio: CapturedPCMBuffer
    private var audioSession: AVAudioSession?

    init(maximumAudioBytes: Int = 20 * 1024 * 1024) {
        capturedAudio = CapturedPCMBuffer(maximumBytes: maximumAudioBytes)
    }

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
        let capturedAudio = self.capturedAudio
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard capturedAudio.beginCapture() else { return }
            defer { capturedAudio.endCapture() }
            let data = Self.pcm16Data(from: buffer)
            let sampleRate = Int(buffer.format.sampleRate)
            let channels = Int(buffer.format.channelCount)
            capturedAudio.append(data, sampleRate: sampleRate, channels: channels)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    @discardableResult
    func stop() -> (data: Data, sampleRate: Int, channels: Int) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? audioSession?.setActive(false)
        audioSession = nil
        return capturedAudio.finish()
    }

    nonisolated private static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data {
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

private final class CapturedPCMBuffer: @unchecked Sendable {
    private let condition = NSCondition()
    private let maximumBytes: Int
    private var data = Data()
    private var sampleRate = 16_000
    private var channels = 1
    private var activeCaptures = 0
    private var acceptingCaptures = true
    private var isFinished = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func beginCapture() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard acceptingCaptures else { return false }
        activeCaptures += 1
        return true
    }

    func append(_ chunk: Data, sampleRate: Int, channels: Int) {
        condition.lock()
        defer { condition.unlock() }
        guard !isFinished, !chunk.isEmpty, data.count < maximumBytes else { return }
        data.append(chunk.prefix(maximumBytes - data.count))
        self.sampleRate = sampleRate
        self.channels = channels
    }

    func endCapture() {
        condition.lock()
        activeCaptures -= 1
        if activeCaptures == 0 { condition.broadcast() }
        condition.unlock()
    }

    func finish() -> (data: Data, sampleRate: Int, channels: Int) {
        condition.lock()
        acceptingCaptures = false
        while activeCaptures > 0 {
            condition.wait()
        }
        isFinished = true
        let result = (data, sampleRate, channels)
        condition.unlock()
        return result
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
    /// Hard cap on the retained bytes of one unterminated JSON-RPC line.
    /// Complete lines are drained in `receive`; only a peer that withholds
    /// the newline can grow the buffer, and it is stopped at this bound.
    private static let maxReadBufferBytes = 16 * 1024 * 1024
    private var nextRequestID = 1
    private var isInitialized = false
    private var isConnecting = false
    private var connectionGeneration = 0
    private var pendingResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var requestTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var pendingApprovalMethods: [String: String] = [:]
    private var pendingApprovalRPCIDs: [String: Any] = [:]
    private var pendingPermissionProfiles: [String: [String: Any]] = [:]
    private var pendingElicitationModes: [String: String] = [:]
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
        connectionGeneration += 1
        let attemptGeneration = connectionGeneration
        defer {
            if connectionGeneration == attemptGeneration {
                isConnecting = false
            }
        }

        do {
            let newSession = try await ssh.openAuthenticatedSession()
            guard connectionGeneration == attemptGeneration else {
                await disconnect(newSession)
                throw CodexAppServerError.transport("The connection attempt was cancelled.")
            }
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
            guard connectionGeneration == attemptGeneration else {
                throw CodexAppServerError.transport("The connection attempt was cancelled.")
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
            guard connectionGeneration == attemptGeneration,
                  isConnecting,
                  session === newSession,
                  shell === newShell else {
                throw CodexAppServerError.transport("The SSH channel closed during initialization.")
            }
            sendNotification(method: "initialized", params: [:])
            isInitialized = true
        } catch {
            if connectionGeneration == attemptGeneration {
                await disconnect(keepingConnectAttempt: true)
            }
            throw error
        }
    }

    func disconnect(keepingConnectAttempt: Bool = false) async {
        isInitialized = false
        if !keepingConnectAttempt {
            connectionGeneration += 1
            isConnecting = false
        }
        let closedShell = shell
        let closedSession = session
        shell = nil
        session = nil
        readBuffer.removeAll(keepingCapacity: false)

        let error = CodexAppServerError.transport("The SSH channel closed.")
        requestTimeoutTasks.values.forEach { $0.cancel() }
        requestTimeoutTasks.removeAll()
        pendingResponses.values.forEach { $0.resume(throwing: error) }
        pendingResponses.removeAll()
        pendingApprovalMethods.removeAll()
        pendingApprovalRPCIDs.removeAll()
        pendingPermissionProfiles.removeAll()
        pendingElicitationModes.removeAll()
        pendingApprovals.removeAll()
        turnWaiters.values.flatMap { $0 }.forEach { $0.resume(throwing: error) }
        turnWaiters.removeAll()
        completedTurns.removeAll()

        closedShell?.close(nil)
        if let closedSession {
            await disconnect(closedSession)
        }
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

    func respondToApproval(
        id: String,
        approve: Bool,
        permissionScope: String = "turn",
        answers: [String: [String]] = [:],
        elicitationContent: [String: Any] = [:]
    ) async throws {
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
            var answerValues: [String: Any] = [:]
            for (questionID, values) in answers where !values.isEmpty {
                answerValues[questionID] = ["answers": values]
            }
            response = ["answers": answerValues]
        case "mcpServer/elicitation/request":
            if approve {
                let supportedModes = ["form", "openai/form", "openaiForm", "url"]
                guard let mode = pendingElicitationModes[id], supportedModes.contains(mode) else {
                    throw CodexAppServerError.invalidResponse(
                        "This MCP request requires a response type Wristex cannot provide. Use a Codex client that supports it."
                    )
                }
            }
            let content: Any = pendingElicitationModes[id] == "url" ? NSNull() : elicitationContent
            response = [
                "action": approve ? "accept" : "decline",
                "content": approve ? content : NSNull(),
                "_meta": NSNull()
            ]
        case "item/permissions/requestApproval":
            let requestedPermissions = pendingPermissionProfiles[id] ?? [:]
            var grantedPermissions: [String: Any] = [:]
            if approve {
                for key in ["network", "fileSystem"] {
                    if let requested = requestedPermissions[key] as? [String: Any] {
                        grantedPermissions[key] = requested
                    }
                }
            }
            let scope = approve && permissionScope == "session" ? "session" : "turn"
            response = ["permissions": grantedPermissions, "scope": scope]
        default:
            throw CodexAppServerError.invalidResponse("Unsupported approval type.")
        }

        try sendResponse(id: rpcID, result: response)
        pendingApprovalMethods.removeValue(forKey: id)
        pendingApprovalRPCIDs.removeValue(forKey: id)
        pendingPermissionProfiles.removeValue(forKey: id)
        pendingElicitationModes.removeValue(forKey: id)
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
            requestTimeoutTasks[id] = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    return
                }
                guard let self,
                      let timedOut = self.pendingResponses.removeValue(forKey: id) else { return }
                self.requestTimeoutTasks.removeValue(forKey: id)
                timedOut.resume(throwing: CodexAppServerError.timeout(method))
            }
            shell.write(data) { [weak self] error in
                guard let self, let error else { return }
                Task { @MainActor in
                    guard let continuation = self.pendingResponses.removeValue(forKey: id) else { return }
                    self.requestTimeoutTasks.removeValue(forKey: id)?.cancel()
                    continuation.resume(
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
        guard let data else {
            // SwiftSH reports a clean EOF as a final nil/nil callback. Without
            // handling it here, the client would keep stale connected state
            // and leave in-flight JSON-RPC requests suspended forever.
            guard error == nil else { return }
            handleChannelClosed()
            return
        }
        guard !data.isEmpty else { return }
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

        // Whatever remains buffered is one incomplete line. A peer that
        // never sends the terminating newline must not grow it without
        // bound, so past the cap the connection is failed with an error
        // instead of retaining data until watchOS kills the app.
        guard readBuffer.count <= Self.maxReadBufferBytes else {
            readBuffer.removeAll(keepingCapacity: false)
            failPending(CodexAppServerError.transport(
                "Codex sent an unterminated message larger than the receive limit."
            ))
            Task { await disconnect() }
            return
        }
    }

    private func handleChannelClosed() {
        guard isInitialized || isConnecting || !pendingResponses.isEmpty || !turnWaiters.isEmpty else { return }

        let closedSession = session
        connectionGeneration += 1
        isInitialized = false
        isConnecting = false
        let error = CodexAppServerError.transport("The SSH channel closed.")
        failPending(error)
        pendingApprovalMethods.removeAll()
        pendingApprovalRPCIDs.removeAll()
        pendingPermissionProfiles.removeAll()
        pendingElicitationModes.removeAll()
        pendingApprovals.removeAll()
        shell = nil
        session = nil

        // Invalidate any in-progress attempt. The closed session is captured
        // here so cleanup cannot affect a later reconnect.
        if let closedSession {
            Task { await disconnect(closedSession) }
        }
    }

    private func disconnect(_ session: SSHSession) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.disconnect { continuation.resume() }
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
        requestTimeoutTasks.removeValue(forKey: id)?.cancel()

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
        // A second server request reusing a pending approval's ID would
        // silently replace the request the wearer is being shown, and the
        // wearer's decision would then answer the wrong request. Keep the
        // original pending approval and reject the duplicate.
        guard pendingApprovalRPCIDs[id] == nil else {
            try? sendError(id: rawID, code: -32603, message: "Duplicate approval request ID.")
            return
        }
        pendingApprovalMethods[id] = method
        pendingApprovalRPCIDs[id] = rawID
        if method == "item/permissions/requestApproval" {
            pendingPermissionProfiles[id] = params["permissions"] as? [String: Any] ?? [:]
        }
        let elicitationMode = params["mode"] as? String
        if method == "mcpServer/elicitation/request", let elicitationMode {
            pendingElicitationModes[id] = elicitationMode
        }
        let questions = (params["questions"] as? [[String: Any]] ?? []).compactMap(makeApprovalQuestion)
        let request = ApprovalRequest(
            id: id,
            toolName: toolName(for: method),
            details: approvalDetails(for: method, params: params),
            status: "pending",
            timestamp: approvalDate(params),
            responseMethod: method,
            threadID: params["threadId"] as? String,
            turnID: params["turnId"] as? String,
            questions: questions,
            isBlocking: params["isBlocking"] as? Bool ?? (method == "item/tool/requestUserInput"),
            formFields: method == "mcpServer/elicitation/request" ? makeApprovalFormFields(params) : [],
            elicitationMode: elicitationMode,
            elicitationURL: params["url"] as? String
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
        requestTimeoutTasks.values.forEach { $0.cancel() }
        requestTimeoutTasks.removeAll()
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

    private func makeApprovalQuestion(_ raw: [String: Any]) -> ApprovalQuestion? {
        guard let id = raw["id"] as? String,
              let question = raw["question"] as? String else { return nil }
        let options = (raw["options"] as? [[String: Any]])?.compactMap { option -> ApprovalQuestionOption? in
            guard let label = option["label"] as? String else { return nil }
            return ApprovalQuestionOption(
                label: label,
                description: option["description"] as? String ?? ""
            )
        }
        return ApprovalQuestion(
            id: id,
            header: raw["header"] as? String ?? "Answer",
            question: question,
            isOther: raw["isOther"] as? Bool ?? false,
            isSecret: raw["isSecret"] as? Bool ?? false,
            options: options
        )
    }

    private func makeApprovalFormFields(_ params: [String: Any]) -> [ApprovalFormField] {
        let schema = params["requestedSchema"] as? [String: Any] ?? [:]
        let properties = schema["properties"] as? [String: Any] ?? [:]
        let required = Set(schema["required"] as? [String] ?? [])

        return properties.keys.sorted().compactMap { name in
            guard let field = properties[name] as? [String: Any] else { return nil }
            let rawType = field["type"] as? String ?? "string"
            let arrayItems = field["items"] as? [String: Any]
            let optionSchema = rawType == "array" ? (arrayItems ?? field) : field
            let options = formOptions(from: optionSchema)
            let kind = options.isEmpty
                ? rawType
                : (rawType == "array" ? "multiSelect" : "singleSelect")
            let defaultValue: String?
            if let values = field["default"] as? [String] {
                defaultValue = values.joined(separator: ",")
            } else {
                defaultValue = field["default"].map { String(describing: $0) }
            }
            return ApprovalFormField(
                name: name,
                title: field["title"] as? String ?? name,
                description: field["description"] as? String ?? "",
                kind: kind,
                required: required.contains(name),
                isSecret: field["format"] as? String == "password",
                defaultValue: defaultValue,
                options: options.isEmpty ? nil : options
            )
        }
    }

    private func formOptions(from schema: [String: Any]) -> [ApprovalQuestionOption] {
        if let choices = (schema["oneOf"] as? [[String: Any]]) ?? (schema["anyOf"] as? [[String: Any]]) {
            return choices.compactMap { option in
                guard let value = option["const"] as? String else { return nil }
                return ApprovalQuestionOption(
                    label: option["title"] as? String ?? value,
                    description: value
                )
            }
        }
        guard let values = schema["enum"] as? [String] else { return [] }
        let labels = schema["enumNames"] as? [String] ?? values
        return values.enumerated().map { index, value in
            ApprovalQuestionOption(
                label: labels.indices.contains(index) ? labels[index] : value,
                description: value
            )
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
        if method == "item/permissions/requestApproval" {
            let summary = permissionSummary(
                params["permissions"] as? [String: Any] ?? [:],
                cwd: params["cwd"] as? String
            )
            if let reason = params["reason"] as? String, !reason.isEmpty {
                return reason + "\n" + summary
            }
            return summary
        }
        if let reason = params["reason"] as? String, !reason.isEmpty { return reason }
        if method == "mcpServer/elicitation/request" {
            if params["mode"] as? String == "openai/userVerification" {
                let title = params["title"] as? String ?? "Device verification"
                let description = params["description"] as? String ?? ""
                return description.isEmpty ? title : title + "\n" + description
            }
            let server = params["serverName"] as? String ?? "MCP server"
            let message = params["message"] as? String ?? ""
            return message.isEmpty ? server : server + "\n" + message
        }
        if let server = params["serverName"] as? String { return "MCP server: " + server }
        if let questions = params["questions"] as? [[String: Any]] {
            return questions.compactMap { $0["question"] as? String }.joined(separator: "\n")
        }
        return "Codex is waiting for a decision."
    }

    private func permissionSummary(_ profile: [String: Any], cwd: String?) -> String {
        var lines: [String] = []
        if let network = profile["network"] as? [String: Any], network["enabled"] as? Bool == true {
            lines.append("Network access")
        }
        if let fileSystem = profile["fileSystem"] as? [String: Any] {
            for access in ["read", "write"] {
                let paths = fileSystem[access] as? [String] ?? []
                for path in paths {
                    lines.append("\(access.capitalized): \(path)")
                }
            }
            for entry in fileSystem["entries"] as? [[String: Any]] ?? [] {
                let access = entry["access"] as? String ?? "access"
                let path = entry["path"] as? [String: Any] ?? [:]
                let value = permissionPathLabel(path, cwd: cwd)
                lines.append("\(access.capitalized): \(value)")
            }
        }
        return lines.isEmpty ? "Codex requested additional permissions." : lines.joined(separator: "\n")
    }

    private func permissionPathLabel(_ path: [String: Any], cwd: String?) -> String {
        if let path = path["path"] as? String { return path }
        if let pattern = path["pattern"] as? String { return pattern }
        if let special = path["value"] as? [String: Any] {
            let kind = special["kind"] as? String ?? "special path"
            switch kind {
            case "project_roots":
                let subpath = special["subpath"] as? String
                return subpath.map { "project roots/\($0)" } ?? "project roots"
            case "unknown":
                let path = special["path"] as? String ?? "unknown path"
                let subpath = special["subpath"] as? String
                return subpath.map { "\(path)/\($0)" } ?? path
            default:
                return kind.replacingOccurrences(of: "_", with: " ")
            }
        }
        return cwd ?? "requested path"
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

    /// Aggregate pagination ceilings. A server that always answers with a
    /// fresh cursor must not keep a loader running (and retaining results)
    /// forever; reaching a ceiling returns what was collected so far.
    private static let maxThreadListPages = 25
    private static let maxMessageListPages = 50

    private let client = CodexAppServerClient.shared
    private let ssh = SSHManager.shared
    private var activeTurnIDs: [String: String] = [:]

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

    func respondToApproval(
        id: String,
        approve: Bool,
        permissionScope: String = "turn",
        answers: [String: [String]] = [:],
        elicitationContent: [String: Any] = [:]
    ) async throws {
        try await client.respondToApproval(
            id: id,
            approve: approve,
            permissionScope: permissionScope,
            answers: answers,
            elicitationContent: elicitationContent
        )
    }

    func listThreads() async throws -> [AgentThread] {
        var params: [String: Any] = [
            "archived": false,
            "limit": 100,
            "sortKey": "recency_at",
            "sortDirection": "desc",
            "sourceKinds": ["cli", "vscode", "exec", "appServer"]
        ]

        var threads: [AgentThread] = []
        var seenIDs = Set<String>()
        var seenCursors = Set<String>()
        var pageCount = 0
        while true {
            let response = try await client.request("thread/list", params: params)
            let data = response["data"] as? [[String: Any]] ?? []
            for value in data {
                guard let thread = makeThread(value), seenIDs.insert(thread.id).inserted else { continue }
                threads.append(thread)
            }
            pageCount += 1

            guard pageCount < Self.maxThreadListPages,
                  let cursor = response["nextCursor"] as? String,
                  !cursor.isEmpty,
                  seenCursors.insert(cursor).inserted else { break }
            params["cursor"] = cursor
        }
        return threads
    }

    func createThread(title: String, cwd: String? = nil) async throws -> AgentThread {
        var params: [String: Any] = [
            "sandbox": "workspace-write",
            "approvalPolicy": "on-request"
        ]
        let cleanCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanCWD.isEmpty {
            params["cwd"] = cleanCWD
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
        named.settings = ThreadSettings(
            approvalPolicy: .onRequest,
            sandboxPolicy: .workspaceWrite
        )
        if named.cwd == nil, !cleanCWD.isEmpty {
            named.cwd = cleanCWD
        }
        return named
    }

    func readMessages(threadID: String) async throws -> [ThreadMessage] {
        do {
            return try await readPaginatedMessages(threadID: threadID)
        } catch let error as CodexAppServerError {
            guard case .server(let message) = error,
                  message.localizedCaseInsensitiveContains("thread/items/list is not supported") else {
                throw error
            }
            return try await readLegacyMessages(threadID: threadID)
        }
    }

    private func readPaginatedMessages(threadID: String) async throws -> [ThreadMessage] {
        var params: [String: Any] = [
            "threadId": threadID,
            "limit": 200,
            "sortDirection": "asc"
        ]
        var messages: [ThreadMessage] = []
        var seenItemIDs = Set<String>()
        var seenCursors = Set<String>()
        var pageCount = 0

        while true {
            let response = try await client.request("thread/items/list", params: params)
            let entries = response["data"] as? [[String: Any]] ?? []
            for entry in entries {
                guard let item = entry["item"] as? [String: Any],
                      let type = item["type"] as? String else { continue }
                let startedAtMs = (entry["startedAtMs"] as? NSNumber)
                    ?? (item["startedAtMs"] as? NSNumber)
                let timestamp = startedAtMs.map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
                appendMessage(from: item, type: type, timestamp: timestamp, to: &messages, seenItemIDs: &seenItemIDs)
            }
            pageCount += 1

            guard pageCount < Self.maxMessageListPages,
                  let cursor = response["nextCursor"] as? String,
                  !cursor.isEmpty,
                  seenCursors.insert(cursor).inserted else { break }
            params["cursor"] = cursor
        }
        return messages
    }

    private func readLegacyMessages(threadID: String) async throws -> [ThreadMessage] {
        let response = try await client.request("thread/read", params: [
            "threadId": threadID,
            "includeTurns": true
        ])
        guard let thread = response["thread"] as? [String: Any],
              let turns = thread["turns"] as? [[String: Any]] else {
            throw CodexAppServerError.invalidResponse("thread/read did not include turns.")
        }

        var messages: [ThreadMessage] = []
        var seenItemIDs = Set<String>()
        for turn in turns {
            for item in turn["items"] as? [[String: Any]] ?? [] {
                guard let type = item["type"] as? String else { continue }
                let timestamp = (item["startedAtMs"] as? NSNumber)
                    .map { Date(timeIntervalSince1970: $0.doubleValue / 1_000) }
                appendMessage(from: item, type: type, timestamp: timestamp, to: &messages, seenItemIDs: &seenItemIDs)
            }
        }
        return messages
    }

    private func appendMessage(
        from item: [String: Any],
        type: String,
        timestamp: Date?,
        to messages: inout [ThreadMessage],
        seenItemIDs: inout Set<String>
    ) {
        let itemID = item["id"] as? String ?? ""
        if !itemID.isEmpty, !seenItemIDs.insert(itemID).inserted { return }

        let sender: String
        let content: String
        switch type {
        case "userMessage":
            sender = "user"
            content = textFromUserInput(item["content"])
        case "agentMessage", "plan":
            sender = "agent"
            content = item["text"] as? String ?? ""
        default:
            return
        }
        guard !content.isEmpty else { return }
        let id = UUID(uuidString: itemID) ?? UUID()
        messages.append(ThreadMessage(id: id, sender: sender, content: content, timestamp: timestamp ?? Date()))
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
            return ModelOption(
                id: id,
                name: name,
                reasoningEfforts: reasoningEfforts
            )
        }
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
            "origin": "user",
            "objective": objective,
            "status": status.rawValue
        ]
        params["tokenBudget"] = tokenBudget.map { NSNumber(value: $0) } ?? NSNull()
        let response = try await client.request("thread/goal/set", params: params)
        guard let goal = response["goal"] as? [String: Any] else { return nil }
        return makeGoal(goal)
    }

    func clearGoal(threadID: String) async throws {
        _ = try await client.request("thread/goal/clear", params: [
            "threadId": threadID,
            "origin": "user"
        ])
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

    func send(_ prompt: String, thread: AgentThread) async throws -> CodexTurnResult {
        let requestedCWD = thread.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRequestedCWD = !(requestedCWD?.isEmpty ?? true)
        var resumeParams: [String: Any] = [
            "threadId": thread.id,
            "excludeTurns": true,
            "approvalPolicy": thread.settings.approvalPolicy.rawValue
        ]
        if hasRequestedCWD, let requestedCWD {
            resumeParams["cwd"] = requestedCWD
        } else {
            resumeParams["cwd"] = NSNull()
        }
        if let sandbox = thread.settings.sandboxPolicy.resumeValue {
            resumeParams["sandbox"] = sandbox
        } else {
            resumeParams["sandbox"] = NSNull()
        }
        if thread.activeModel == "default" {
            resumeParams["model"] = NSNull()
        } else {
            resumeParams["model"] = thread.activeModel
        }
        let resumed = try await client.request("thread/resume", params: resumeParams)
        let remoteThread = resumed["thread"] as? [String: Any]
        let sessionID = remoteThread?["sessionId"] as? String ?? thread.codexSessionID ?? thread.id
        let remoteCWD = (remoteThread?["cwd"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveCWD = hasRequestedCWD ? requestedCWD : (remoteCWD?.isEmpty == false ? remoteCWD : nil)

        var turnParams: [String: Any] = [
            "threadId": thread.id,
            "input": [["type": "text", "text": prompt, "text_elements": []]],
            "clientUserMessageId": UUID().uuidString,
            "approvalPolicy": thread.settings.approvalPolicy.rawValue,
            "summary": thread.settings.reasoningSummary.serverValue
        ]
        if let sandboxPolicy = thread.settings.sandboxPolicy.turnValue(cwd: effectiveCWD) {
            turnParams["sandboxPolicy"] = sandboxPolicy
        } else {
            turnParams["sandboxPolicy"] = NSNull()
        }
        if thread.activeModel == "default" {
            turnParams["model"] = NSNull()
        } else {
            turnParams["model"] = thread.activeModel
        }
        if let reasoningEffort = thread.settings.reasoningEffort {
            turnParams["effort"] = reasoningEffort
        } else {
            turnParams["effort"] = NSNull()
        }
        if let effectiveCWD, !effectiveCWD.isEmpty { turnParams["cwd"] = effectiveCWD }
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
            activeModel: value["model"] as? String ?? "default",
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
