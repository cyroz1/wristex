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

    private init() {
        host = defaults.string(forKey: Keys.host) ?? ""
        username = defaults.string(forKey: Keys.username) ?? ""
        let savedPort = defaults.integer(forKey: Keys.port)
        port = savedPort == 0 ? 22 : savedPort
        remoteWorkspacePath = defaults.string(forKey: Keys.workspace) ?? ""
        password = KeychainStore.read(Keys.password)
        privateKeyPEM = KeychainStore.read(Keys.privateKeyPEM)
        privateKeyPassphrase = KeychainStore.read(Keys.privateKeyPassphrase)

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
