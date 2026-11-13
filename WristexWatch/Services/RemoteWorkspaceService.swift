import Foundation

@MainActor
public final class RemoteWorkspaceService {
    public static let shared = RemoteWorkspaceService()

    private let ssh = SSHManager.shared
    private let maximumFilePreviewBytes = 16_000
    private let maximumDiffPreviewBytes = 32_000

    private init() {}

    public func listDirectory(at remotePath: String) async throws -> [RemoteFileEntry] {
        let path = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw RemoteWorkspaceError.invalidPath }

        let output = try await ssh.executeCommand("cd \(Shell.quotePath(path)) && ls -la")
        return Self.parseDirectoryListing(output, directory: path)
    }

    public func readFile(at remotePath: String) async throws -> RemoteFileContents {
        let path = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw RemoteWorkspaceError.invalidPath }

        let quotedPath = Shell.quotePath(path)
        let marker = "__WRISTEX_FILE_SIZE__"
        let command = "if [ ! -f \(quotedPath) ]; then echo 'Not a regular text file' >&2; exit 2; fi; head -c \(maximumFilePreviewBytes) < \(quotedPath); printf '\\n\(marker)'; wc -c < \(quotedPath)"
        let output = try await ssh.executeCommand(command)
        guard let markerRange = output.range(of: marker, options: .backwards),
              let byteSize = Int64(output[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemoteWorkspaceError.invalidFileResponse
        }

        var contents = String(output[..<markerRange.lowerBound])
        if contents.hasSuffix("\n") { contents.removeLast() }
        return RemoteFileContents(
            text: contents,
            byteSize: byteSize,
            wasTruncated: byteSize > Int64(maximumFilePreviewBytes)
        )
    }

    public func readDiff(workspacePath: String, relativePath: String, isUntracked: Bool) async throws -> String {
        let workspace = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspace.isEmpty, Self.isSafeRelativePath(relativePath) else {
            throw RemoteWorkspaceError.invalidPath
        }

        let quotedFile = Shell.quote(relativePath)
        let outputLimit = maximumDiffPreviewBytes + 1
        let command: String
        if isUntracked {
            command = "cd \(Shell.quotePath(workspace)) && { git --literal-pathspecs diff --no-index --no-ext-diff --no-color --unified=2 -- /dev/null \(quotedFile) 2>&1 || [ $? -eq 1 ]; } | head -c \(outputLimit)"
        } else {
            command = "cd \(Shell.quotePath(workspace)) && { git --literal-pathspecs diff --no-ext-diff --no-color --unified=2 -- \(quotedFile) 2>&1 || [ $? -eq 1 ]; git --literal-pathspecs diff --cached --no-ext-diff --no-color --unified=2 -- \(quotedFile) 2>&1 || [ $? -eq 1 ]; } | head -c \(outputLimit)"
        }
        let output = try await ssh.executeCommand(command)
        guard !output.isEmpty else { return "No text diff is available for this file." }

        let bytes = Array(output.utf8)
        guard bytes.count > maximumDiffPreviewBytes else { return output }
        let preview = String(decoding: bytes.prefix(maximumDiffPreviewBytes), as: UTF8.self)
        return preview + "\n… diff preview truncated"
    }

    private static func parseDirectoryListing(_ output: String, directory: String) -> [RemoteFileEntry] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            let fields = line.split(maxSplits: 8, omittingEmptySubsequences: true) { $0.isWhitespace }
            guard fields.count == 9 else { return nil }

            let permissions = String(fields[0])
            guard let firstCharacter = permissions.first else { return nil }
            var name = String(fields[8])
            if firstCharacter == "l", let arrow = name.range(of: " -> ") {
                name = String(name[..<arrow.lowerBound])
            }
            guard name != ".", name != "..", !name.isEmpty else { return nil }

            let kind: RemoteFileKind
            switch firstCharacter {
            case "d": kind = .directory
            case "l": kind = .symbolicLink
            default: kind = .file
            }

            let path = directory.hasSuffix("/") ? directory + name : directory + "/" + name
            return RemoteFileEntry(
                path: path,
                name: name,
                kind: kind,
                byteSize: Int64(fields[4]) ?? 0
            )
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." }
    }
}

private enum RemoteWorkspaceError: LocalizedError {
    case invalidPath
    case invalidFileResponse

    var errorDescription: String? {
        switch self {
        case .invalidPath: return "This remote path is not valid."
        case .invalidFileResponse: return "The remote file preview could not be read."
        }
    }
}
