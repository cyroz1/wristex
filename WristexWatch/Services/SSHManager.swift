import Combine
import Foundation
import SwiftSH

@MainActor
public final class SSHManager: ObservableObject {
    public static let shared = SSHManager()

    @Published public var host: String {
        didSet { defaults.set(host, forKey: Keys.host) }
    }
    @Published public var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }
    @Published public var port: Int {
        didSet { defaults.set(port, forKey: Keys.port) }
    }
    @Published public var remoteWorkspacePath: String {
        didSet { defaults.set(remoteWorkspacePath, forKey: Keys.workspace) }
    }
    @Published public var password: String {
        didSet { KeychainStore.write(password, account: Keys.password) }
    }
    @Published public var privateKeyPEM: String {
        didSet { KeychainStore.write(privateKeyPEM, account: Keys.privateKeyPEM) }
    }
    @Published public var privateKeyPassphrase: String {
        didSet { KeychainStore.write(privateKeyPassphrase, account: Keys.privateKeyPassphrase) }
    }
    @Published public private(set) var connectionState = "Not tested"

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let host = "wristex_ssh_host"
        static let username = "wristex_ssh_username"
        static let port = "wristex_ssh_port"
        static let workspace = "wristex_ssh_workspace"
        static let password = "wristex_ssh_password"
        static let privateKeyPEM = "wristex_ssh_private_key_pem"
        static let privateKeyPassphrase = "wristex_ssh_private_key_passphrase"
        static let fingerprintPrefix = "wristex_ssh_fingerprint_"
    }

    private static let debugPrivateKeyEnvironment = "WRISTEX_SSH_PRIVATE_KEY"
    private static let debugPrivateKeyPassphraseEnvironment = "WRISTEX_SSH_PRIVATE_KEY_PASSPHRASE"
    private static let debugWorkspaceEnvironment = "WRISTEX_SSH_WORKSPACE"

    private init() {
        host = defaults.string(forKey: Keys.host) ?? ""
        username = defaults.string(forKey: Keys.username) ?? ""
        let savedPort = defaults.integer(forKey: Keys.port)
        port = savedPort == 0 ? 22 : savedPort
        remoteWorkspacePath = defaults.string(forKey: Keys.workspace) ?? ""
        password = KeychainStore.read(Keys.password)
        #if DEBUG
        let injectedPrivateKey = ProcessInfo.processInfo.environment[Self.debugPrivateKeyEnvironment]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        #else
        let injectedPrivateKey: String? = nil
        #endif

        privateKeyPEM = injectedPrivateKey ?? KeychainStore.read(Keys.privateKeyPEM)
        #if DEBUG
        let injectedPrivateKeyPassphrase = ProcessInfo.processInfo.environment[Self.debugPrivateKeyPassphraseEnvironment]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #else
        let injectedPrivateKeyPassphrase: String? = nil
        #endif

        privateKeyPassphrase = injectedPrivateKeyPassphrase ?? KeychainStore.read(Keys.privateKeyPassphrase)

        applySSHConfigDefaults()
        applyDebugEnvironmentOverrides()

        if let injectedPrivateKey {
            KeychainStore.write(injectedPrivateKey, account: Keys.privateKeyPEM)
        }
        if let injectedPrivateKeyPassphrase {
            KeychainStore.write(injectedPrivateKeyPassphrase, account: Keys.privateKeyPassphrase)
        }

        // Remove credentials left by early development builds.
        defaults.removeObject(forKey: Keys.password)
    }

    public var connectionID: String {
        "\(username)@\(host):\(port)"
    }

    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!password.isEmpty || !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (1...65_535).contains(port)
    }

    public func reloadConfigDefaults() {
        applySSHConfigDefaults()
    }

    public var hasPinnedFingerprint: Bool {
        defaults.string(forKey: fingerprintKey) != nil
    }

    public func forgetHostFingerprint() {
        defaults.removeObject(forKey: fingerprintKey)
        connectionState = "Host key forgotten"
    }

    public func testConnection() async throws -> String {
        connectionState = "Connecting…"
        do {
            let output = try await executeCommand(
                "command -v codex >/dev/null 2>&1 && codex --version || { echo 'Codex CLI not found'; exit 127; }"
            )
            let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
            connectionState = result
            return result
        } catch {
            connectionState = "Connection failed"
            throw error
        }
    }

    public func executeCommand(_ commandText: String) async throws -> String {
        let configuration = try snapshot()
        let session = try SSHSession(
            host: configuration.host,
            port: UInt16(configuration.port)
        )
        session.timeout = 20
        session.log.enabled = false

        do {
            try await connect(session)
            try validateFingerprint(session, configuration: configuration)
            try await authenticate(session, configuration: configuration)
            // Codex turns can legitimately run for several minutes.
            session.timeout = 600
            let output = try await run(commandText, on: session)
            await disconnect(session)
            return output
        } catch {
            await disconnect(session)
            throw error
        }
    }

    /// Opens an authenticated SSH session for a long-lived bidirectional channel.
    ///
    /// The Codex app server speaks JSON-RPC over stdin/stdout, so a one-shot
    /// command channel is not sufficient for approvals or streamed turn events.
    public func openAuthenticatedSession() async throws -> SSHSession {
        let configuration = try snapshot()
        let session = try SSHSession(
            host: configuration.host,
            port: UInt16(configuration.port)
        )
        session.timeout = 20
        session.log.enabled = false

        do {
            try await connect(session)
            try validateFingerprint(session, configuration: configuration)
            try await authenticate(session, configuration: configuration)
            session.timeout = 600
            session.setCallbackQueue(queue: .main)
            return session
        } catch {
            await disconnect(session)
            throw error
        }
    }

    public func openAuthenticatedShell() async throws -> SSHShell {
        let session = try await openAuthenticatedSession()
        do {
            return try SSHShell(session: session)
        } catch {
            await disconnect(session)
            throw error
        }
    }

    private struct Configuration: Sendable {
        let host: String
        let username: String
        let port: Int
        let password: String
        let privateKeyPEM: String
        let privateKeyPassphrase: String
    }

    private var fingerprintKey: String {
        Keys.fingerprintPrefix + connectionID
    }

    private func snapshot() throws -> Configuration {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, !cleanUser.isEmpty, (1...65_535).contains(port) else {
            throw SSHConnectionError.invalidSettings
        }
        guard !password.isEmpty || !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SSHConnectionError.missingCredentials
        }
        return Configuration(
            host: cleanHost,
            username: cleanUser,
            port: port,
            password: password,
            privateKeyPEM: privateKeyPEM,
            privateKeyPassphrase: privateKeyPassphrase
        )
    }

    private func applySSHConfigDefaults() {
        guard let config = SSHConfigLoader.load() else {
            return
        }

        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            host = config.host
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            username = config.username
        }
        if defaults.object(forKey: Keys.port) == nil {
            port = config.port
        }
        if privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let privateKeyPEM = config.privateKeyPEM {
            self.privateKeyPEM = privateKeyPEM
            KeychainStore.write(privateKeyPEM, account: Keys.privateKeyPEM)
        }
    }

    private func applyDebugEnvironmentOverrides() {
        #if DEBUG
        if let workspace = ProcessInfo.processInfo.environment[Self.debugWorkspaceEnvironment]
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
           !workspace.isEmpty {
            remoteWorkspacePath = workspace
        }
        #endif
    }

    private func connect(_ session: SSHSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.connect { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func authenticate(_ session: SSHSession, configuration: Configuration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let challenge: AuthenticationChallenge
            let keyText = configuration.privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
            if let key = keyText.data(using: .utf8), !key.isEmpty {
                challenge = .byPublicKeyFromMemory(
                    username: configuration.username,
                    password: configuration.privateKeyPassphrase,
                    publicKey: nil,
                    privateKey: key
                )
            } else {
                challenge = .byPassword(username: configuration.username, password: configuration.password)
            }
            session.authenticate(challenge) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func run(_ commandText: String, on session: SSHSession) async throws -> String {
        let command = try SSHCommand(session: session)
        let marker = "__WRISTEX_EXIT_STATUS__"
        let wrappedCommand = "(\(commandText)) 2>&1; wristex_status=$?; printf '\\n\(marker)%s\\n' \"$wristex_status\""
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            command.execute(wrappedCommand) { _, output, error in
                if let error { continuation.resume(throwing: error) }
                else {
                    let rawOutput = output ?? ""
                    guard let markerRange = rawOutput.range(of: marker, options: .backwards),
                          let status = Int(rawOutput[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                        continuation.resume(throwing: SSHConnectionError.missingExitStatus)
                        return
                    }
                    let cleanOutput = String(rawOutput[..<markerRange.lowerBound])
                        .trimmingCharacters(in: .newlines)
                    if status == 0 {
                        continuation.resume(returning: cleanOutput)
                    } else {
                        continuation.resume(throwing: RemoteCommandError(status: status, output: cleanOutput))
                    }
                }
            }
        }
    }

    private func disconnect(_ session: SSHSession) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.disconnect { continuation.resume() }
        }
    }

    private func validateFingerprint(_ session: SSHSession, configuration: Configuration) throws {
        guard let fingerprint = session.fingerprint[.sha1], !fingerprint.isEmpty else {
            throw SSHConnectionError.missingFingerprint
        }
        let key = Keys.fingerprintPrefix + "\(configuration.username)@\(configuration.host):\(configuration.port)"
        if let pinned = defaults.string(forKey: key), pinned != fingerprint {
            throw SSHConnectionError.hostKeyChanged
        }
        if defaults.string(forKey: key) == nil {
            defaults.set(fingerprint, forKey: key)
        }
    }
}

enum SSHConnectionError: LocalizedError {
    case invalidSettings
    case missingCredentials
    case missingFingerprint
    case hostKeyChanged
    case missingExitStatus

    var errorDescription: String? {
        switch self {
        case .invalidSettings: return "Enter a valid host, username, and port."
        case .missingCredentials: return "Enter an SSH password or private key."
        case .missingFingerprint: return "The server did not provide a host fingerprint."
        case .hostKeyChanged: return "The SSH host key changed. Verify the server, then forget the saved key."
        case .missingExitStatus: return "The SSH command ended without an exit status."
        }
    }
}

struct RemoteCommandError: LocalizedError {
    let status: Int
    let output: String

    var errorDescription: String? {
        output.isEmpty ? "Remote command failed (exit \(status))." : output
    }
}

private struct SSHConfigSettings {
    let host: String
    let username: String
    let port: Int
    let privateKeyPEM: String?
}

private enum SSHConfigLoader {
    private struct HostBlock {
        let patterns: [String]
        var values: [String: String]
    }

    static func load() -> SSHConfigSettings? {
        for url in candidateURLs() {
            let blocks = parseFile(url, visited: [])
            guard let block = blocks.first(where: { block in
                block.patterns.contains { pattern in
                    !pattern.isEmpty && !pattern.contains("*") && !pattern.contains("?") && !pattern.hasPrefix("!")
                }
            }),
            let hostPattern = block.patterns.first(where: { pattern in
                !pattern.isEmpty && !pattern.contains("*") && !pattern.contains("?") && !pattern.hasPrefix("!")
            }) else {
                continue
            }

            let host = block.values["hostname"] ?? hostPattern
            let username = block.values["user"] ?? ""
            let port = Int(block.values["port"] ?? "22") ?? 22
            let privateKeyPEM = block.values["identityfile"].flatMap { identityPath in
                readPrivateKey(identityPath, relativeTo: url)
            }

            guard !host.isEmpty, !username.isEmpty, (1...65_535).contains(port) else {
                continue
            }
            return SSHConfigSettings(
                host: host,
                username: username,
                port: port,
                privateKeyPEM: privateKeyPEM
            )
        }

        if let bundledSettings = loadBundledDefaults() {
            return bundledSettings
        }
        return nil
    }

    private static func loadBundledDefaults() -> SSHConfigSettings? {
        guard let url = Bundle.main.url(forResource: "WristexSSHConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let propertyList = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let values = propertyList as? [String: Any],
              let host = values["host"] as? String,
              let username = values["username"] as? String,
              let port = values["port"] as? Int,
              !host.isEmpty,
              !username.isEmpty,
              (1...65_535).contains(port) else {
            return nil
        }

        return SSHConfigSettings(
            host: host,
            username: username,
            port: port,
            privateKeyPEM: nil
        )
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default

        if let configuredPath = ProcessInfo.processInfo.environment["WRISTEX_SSH_CONFIG"],
           !configuredPath.isEmpty {
            urls.append(URL(fileURLWithPath: expandTilde(in: configuredPath)))
        }

        urls.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("config/ssh-test.conf")
        )

        #if DEBUG
        // Xcode's debug app can read the project-local config when it exists.
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = sourceDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        urls.append(projectRoot.appendingPathComponent("config/ssh-test.conf"))
        #endif

        if let bundleURL = Bundle.main.url(forResource: "ssh-test", withExtension: "conf", subdirectory: "config") {
            urls.append(bundleURL)
        }
        if let bundleURL = Bundle.main.url(forResource: "ssh-test", withExtension: "conf") {
            urls.append(bundleURL)
        }

        var uniqueURLs: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                uniqueURLs.append(url)
            }
        }
        return uniqueURLs
    }

    private static func parseFile(_ url: URL, visited: Set<String>) -> [HostBlock] {
        let canonicalURL = url.standardizedFileURL
        guard !visited.contains(canonicalURL.path),
              let contents = try? String(contentsOf: canonicalURL, encoding: .utf8) else {
            return []
        }

        var visited = visited
        visited.insert(canonicalURL.path)
        var globalValues: [String: String] = [:]
        var blocks: [HostBlock] = []
        var currentBlock: HostBlock?

        func appendCurrentBlock() {
            guard var currentBlock else { return }
            for (key, value) in globalValues where currentBlock.values[key] == nil {
                currentBlock.values[key] = value
            }
            blocks.append(currentBlock)
        }

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = removeComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = tokens(in: line)
            guard let directive = parts.first?.lowercased(), parts.count > 1 else { continue }
            let values = Array(parts.dropFirst())

            if directive == "host" {
                appendCurrentBlock()
                currentBlock = HostBlock(patterns: values, values: [:])
            } else if directive == "include" {
                let includedBlocks = values.flatMap { includePath in
                    includeURLs(for: includePath, relativeTo: canonicalURL)
                        .flatMap { parseFile($0, visited: visited) }
                }
                blocks.append(contentsOf: includedBlocks)
            } else if let value = values.first {
                if currentBlock != nil {
                    currentBlock?.values[directive] = value
                } else {
                    globalValues[directive] = value
                }
            }
        }

        appendCurrentBlock()
        return blocks
    }

    private static func includeURLs(for path: String, relativeTo configURL: URL) -> [URL] {
        let expandedPath = expandTilde(in: path)
        let url: URL
        if expandedPath.hasPrefix("/") {
            url = URL(fileURLWithPath: expandedPath)
        } else {
            url = configURL.deletingLastPathComponent().appendingPathComponent(expandedPath)
        }

        if !expandedPath.contains("*") && !expandedPath.contains("?") {
            return [url]
        }

        let directory = url.deletingLastPathComponent()
        let pattern = url.lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { wildcardMatch(pattern, value: $0.lastPathComponent) }
    }

    private static func readPrivateKey(_ path: String, relativeTo configURL: URL) -> String? {
        let expandedPath = expandTilde(in: path)
        let url: URL
        if expandedPath.hasPrefix("/") {
            url = URL(fileURLWithPath: expandedPath)
        } else {
            url = configURL.deletingLastPathComponent().appendingPathComponent(expandedPath)
        }
        guard let privateKey = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmedKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedKey.isEmpty ? nil : trimmedKey
    }

    private static func expandTilde(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        let homeDirectory = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return homeDirectory + String(path.dropFirst())
    }

    private static func removeComment(from line: String) -> String {
        var quote: Character?
        for (index, character) in line.enumerated() {
            if character == "\"" || character == "'" {
                if quote == nil {
                    quote = character
                } else if quote == character {
                    quote = nil
                }
            } else if character == "#" && quote == nil {
                return String(line.prefix(index))
            }
        }
        return line
    }

    private static func tokens(in line: String) -> [String] {
        var result: [String] = []
        var token = ""
        var quote: Character?
        var escaped = false

        for character in line {
            if escaped {
                token.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" || character == "'" {
                if quote == nil {
                    quote = character
                } else if quote == character {
                    quote = nil
                } else {
                    token.append(character)
                }
            } else if character.isWhitespace && quote == nil {
                if !token.isEmpty {
                    result.append(token)
                    token = ""
                }
            } else {
                token.append(character)
            }
        }
        if escaped { token.append("\\") }
        if !token.isEmpty { result.append(token) }
        return result
    }

    private static func wildcardMatch(_ pattern: String, value: String) -> Bool {
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return value.range(of: "^\(escapedPattern)$", options: .regularExpression) != nil
    }
}
