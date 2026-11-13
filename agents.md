# Wristex Agent Guidelines

Wristex is a watchOS client for controlling a remote Codex app server over SSH. The host may be Oracle/Linux, macOS, or another supported SSH environment; the only transport requirement is that it can launch `codex app-server --stdio`. Keep all user-facing summaries short and watch-readable.

## Communication

- Use one or two concise sentences for completed work.
- Prefer simple bullets and short labels.
- Avoid large code blocks, deeply nested Markdown, and desktop-sized explanations in watch-facing text.
- For approvals, show the primary intent first and truncate long command details.

## Integration boundary

The production transport is direct SSH through `WristexWatch/Services/SSHManager.swift`:

1. `SSHManager` authenticates with a Keychain-backed password or PEM private key.
2. It displays the SHA256 fingerprint and requires explicit first-use trust before authentication, then pins it per `username@host:port`.
3. `RemoteCodexService` opens a long-lived SSH shell and launches `codex app-server --stdio`.
4. JSON-RPC requests, streamed notifications, and server approval requests share that channel.

Chat mode is a separate direct HTTPS integration in `WristexWatch/Services/ChatService.swift`:

1. It calls the OpenAI Responses API directly from the watch.
2. The API key is stored in Keychain and never placed in `UserDefaults` or sent through the Codex SSH channel.
3. Local Chat history is included in each stateless request and streamed text is rendered incrementally.
4. Chat microphone audio uses the OpenAI file transcription endpoint with `gpt-transcribe`; native watchOS dictation is the fallback.

Do not reintroduce REST endpoints, fake remote JSON files, or simulated agent replies. `ThreadStore` is only a local cache and must never replace the Codex app server as the source of truth.
The Chat API is an intentional separate integration and must not be used as a substitute for Codex thread state, approvals, goals, or Git actions.

Thread dictation uses `ChatService` transcription when the API key is configured, then lets the user review and send the text. Otherwise, use native watchOS dictation and put the result in the composer. Do not use Codex `thread/realtime` as a transcription-only input; that voice mode can hand speech to Codex before the client can review it.

## Thread behavior

Thread operations should use the app-server protocol:

- `thread/list`, `thread/start`, `thread/name/set`, `thread/archive`, and `thread/delete` for lifecycle actions.
- `thread/items/list` for history.
- `thread/resume` and `turn/start` for model, reasoning effort, approval, sandbox, folder, and summary overrides.
- `thread/goal/get`, `thread/goal/set`, and `thread/goal/clear` for goal mode.
- `thread/status/changed` for live status updates.
- `turn/start`, `turn/completed`, and `turn/interrupt` for turn control.

Preserve these watch-friendly statuses:

- `READY`
- `RUNNING`
- `APPROVE`
- `INPUT`
- `ERROR`

When adding a new status or event, update both the model mapping and the compact watch presentation.

## Approval behavior

Approval details must fit a 41 mm or 45 mm watch:

- Commands begin with `$`.
- Long commands should show the executable and primary intent.
- File changes should show the target path and a short delta summary.
- Never silently approve a permission-scope expansion from a tiny UI.
- Show requested filesystem and network permissions, and require a deliberate turn or session scope before granting them.
- Collect `request_user_input` answers in the UI, preserving secret fields and the server's question IDs.
- Render supported MCP elicitation form fields and return their content with the original server request ID.
- Use the app-server request’s original response method and RPC ID; do not write ad hoc approval files.

## Advanced controls

Thread controls are saved locally and applied through the supported `thread/resume` and `turn/start` parameters when the next turn is sent. Do not call an unsupported settings endpoint. Do not hard-code a model’s reasoning options when the model catalog advertises supported efforts. Keep dangerous choices such as full sandbox access and `never` approval visibly labeled.

Goals should use the native goal methods and display status or usage when available. Keep the goal editor short enough for watch dictation.

## Git actions

Git actions operate in the configured remote workspace through SSH. The commit action intentionally stages the whole workspace with `git add .`; keep the status review visible before committing. Summarize pull, commit, and push results in one short sentence.
For a branch without an upstream, publish it using `branch.<name>.pushRemote`, `remote.pushDefault`, `branch.<name>.remote`, or an unambiguous configured remote. Do not guess between multiple remotes when no default is set.

The Git status screen links each changed or untracked path to a bounded diff preview. The workspace browser lists direct children of the configured or thread project folder and opens text previews capped at 16 KB. Do not follow symbolic links from the browser.

## Security and validation

- Keep credentials in Keychain, not `UserDefaults`.
- Preserve host-key verification and never add a bypass for convenience.
- Escape or structure remote command arguments safely.
- Treat remote tool requests and paths as untrusted input.
- Run `swiftc -frontend -parse $(rg --files WristexWatch -g '*.swift')` when Xcode is unavailable.
- Run a complete Xcode/watchOS build when Xcode and the watchOS SDK are available.
