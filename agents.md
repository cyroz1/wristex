# Wristex Agent Guidelines

Wristex is a watchOS client for controlling a remote Codex app server. Keep all user-facing summaries short and watch-readable.

## Communication

- Use one or two concise sentences for completed work.
- Prefer simple bullets and short labels.
- Avoid large code blocks, deeply nested Markdown, and desktop-sized explanations in watch-facing text.
- For approvals, show the primary intent first and truncate long command details.

## Integration boundary

The production transport is direct SSH through `WristexWatch/Services/SSHManager.swift`:

1. `SSHManager` authenticates with a Keychain-backed password or PEM private key.
2. It pins the remote host fingerprint per `username@host:port`.
3. `RemoteCodexService` opens a long-lived SSH shell and launches `codex app-server --stdio`.
4. JSON-RPC requests, streamed notifications, and server approval requests share that channel.

Do not reintroduce REST endpoints, fake remote JSON files, or simulated agent replies. `ThreadStore` is only a local cache and must never replace the Codex app server as the source of truth.

## Thread behavior

Thread operations should use the app-server protocol:

- `thread/list`, `thread/start`, `thread/name/set`, `thread/archive`, and `thread/delete` for lifecycle actions.
- `thread/items/list` for history.
- `thread/settings/update` for model, reasoning effort, personality, approval, sandbox, and summary settings.
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
- Use the app-server request’s original response method and RPC ID; do not write ad hoc approval files.

## Advanced controls

Settings must be sent to Codex through `thread/settings/update`. Do not hard-code a model’s reasoning options when the model catalog advertises supported efforts. Keep dangerous choices such as full sandbox access and `never` approval visibly labeled.

Goals should use the native goal methods and display status or usage when available. Keep the goal editor short enough for watch dictation.

## Git actions

Git actions operate in the configured remote workspace through SSH. The commit action intentionally stages the whole workspace with `git add .`; keep the status review visible before committing. Summarize pull, commit, and push results in one short sentence.

## Security and validation

- Keep credentials in Keychain, not `UserDefaults`.
- Preserve host-key verification and never add a bypass for convenience.
- Escape or structure remote command arguments safely.
- Treat remote tool requests and paths as untrusted input.
- Run `swiftc -frontend -parse $(rg --files WristexWatch -g '*.swift')` when Xcode is unavailable.
- Run a complete Xcode/watchOS build when Xcode and the watchOS SDK are available.
