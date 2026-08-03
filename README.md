# Wristex

Wristex is a watchOS remote control for Codex running on any reachable SSH host. It connects directly to that host over SSH and speaks JSON-RPC to `codex app-server --stdio`; there is no REST backend or relay service. Oracle Cloud Linux is one example, not a requirement.

## Features

- List, create, name, archive, delete, and resume remote Codex threads.
- Read thread history and send prompts with streamed agent replies.
- Show live thread status: ready, working, needs approval, needs input, or error.
- Interrupt a running turn.
- Select the host’s available models and supported reasoning-effort options.
- Configure per-thread goals and view goal progress/status.
- Configure personality, approval policy, sandbox policy, and reasoning summaries.
- Review and answer app-server approval requests for commands, file changes, user input, and MCP elicitation.
- Dictate with Codex realtime transcription over SSH, with native watchOS dictation fallback.
- Inspect remote Git status and run pull, commit, and push actions.
- Switch to Chat mode for a separate OpenAI API conversation with streamed replies and GPT transcription.
- Keep Chat history on the watch; configure the API key and model in Settings.
- Cache the last known threads and messages locally for short offline periods.

## Architecture

```text
Apple Watch
    ├── Direct HTTPS ──► OpenAI Responses API (Chat mode)
    │
    └── Direct authenticated SSH ──► Remote SSH host (Codex mode)
                                      │
                                      └── codex app-server --stdio
                                               │
                                               ├── JSON-RPC thread and turn APIs
                                               ├── streamed events and thread status
                                               ├── approval requests
                                               ├── model and settings APIs
                                               └── realtime voice transcription
```

`SSHManager` handles authentication, host-key fingerprint pinning, one-shot commands, and the long-lived bidirectional shell used by the app server. `RemoteCodexService` is the app-server JSON-RPC client. Codex remains the source of truth; `ThreadStore` only caches the last successful data in the watch app’s local preferences.

`ChatService` is intentionally separate from Codex: it sends the local Chat transcript directly to OpenAI’s Responses API, streams `response.output_text.delta` events, and keeps the API key in Keychain. Chat microphone recordings are wrapped as WAV and sent to the [file transcription endpoint](https://developers.openai.com/api/docs/guides/speech-to-text) with `gpt-transcribe`; native watchOS dictation remains the fallback. Chat does not create Codex threads or receive Codex approvals. See the [Responses API](https://platform.openai.com/docs/api-reference/responses) and [streaming events](https://platform.openai.com/docs/api-reference/responses-streaming) documentation for the upstream protocol.

## SSH host requirements

The configured SSH account on any supported host must have:

1. The Codex CLI installed and available on `PATH`.
2. Codex authentication configured for that account.
3. `codex app-server --stdio` available in the installed CLI version.
4. SSH access reachable from the Apple Watch’s network.
5. The target repository path configured in Wristex’s SSH settings.

Verify the CLI before configuring the watch:

```bash
ssh user@your-host 'command -v codex && codex --version && codex app-server --help'
```

The app server protocol is experimental in Codex CLI, so keep the server CLI and Wristex deployment aligned when upgrading.

## Xcode setup

The repository includes `Wristex.xcodeproj` and a watchOS scheme.

1. Open `Wristex.xcodeproj` in Xcode.
2. Select the `Wristex` watchOS target and a watchOS Simulator or paired Apple Watch.
3. Build and run.
4. Open **SSH Settings** in Wristex and enter the server, username, port, and workspace path.
5. Authenticate with either an SSH password or a PEM private key and passphrase.
6. Tap **Save & Test**, then accept the server’s first host-key fingerprint if it is correct.
7. In **Chat API**, enter an OpenAI API key and a model enabled for your OpenAI project, then tap **Test Chat API**.

SwiftSH and its libssh2 bridge are vendored under `Vendor/SwiftSH` so the direct SSH transport is available to the Xcode target.

## SSH security

- Passwords, private keys, and key passphrases are stored in the Apple Keychain.
- Host fingerprints are pinned per `username@host:port` on first successful connection.
- A changed fingerprint blocks the connection until the stored fingerprint is explicitly forgotten.
- The app server uses a persistent SSH channel so streamed turns and approval requests are not reduced to one-shot shell output.
- Do not use full-access sandbox or `never` approval policy unless the remote workspace and server account are trusted.

## Watch workflows

### Threads

The Threads tab loads remote threads from `thread/list`. Thread detail loads history from `thread/items/list`, starts turns with `turn/start`, and listens for streamed `item/agentMessage/delta` events. Status changes arrive through `thread/status/changed`.

The **Thread Controls** screen exposes:

- Goal objective and goal state.
- Model-specific reasoning effort.
- Automatic, friendly, or pragmatic personality.
- Ask-when-needed, untrusted-only, or never approval policy.
- Host default, read-only, workspace-write, or full-access sandbox.
- Automatic, concise, detailed, or hidden reasoning summaries.

### Approvals

The Approvals tab subscribes to live app-server requests and shows compact, watch-friendly details. Command and file-change approvals use the server’s native response methods. Permission-scope approvals are denied from the tiny UI until a dedicated scope picker is available.

### Voice

The microphone button first attempts Codex realtime transcription through the remote app server. If that capability is unavailable, Wristex falls back to the native watchOS dictation controller.

### Git

The Git tab runs status, pull, commit, and push commands in the configured remote workspace. Commit stages all files in that workspace, so review the status list before using it.

### Chat

Chat is a separate local conversation. Each send includes the saved Chat transcript in a stateless Responses API request; the API key is stored in Keychain and is never sent through the Codex SSH channel. The microphone records until tapped again, then transcribes the bounded WAV with GPT before sending it. Clear Chat removes the locally cached transcript.

## Repository layout

```text
WristexWatch/
├── Models/       Threads, statuses, goals, settings, messages, approvals, Git, models
├── Services/     SSH, Keychain, app-server JSON-RPC, Chat API, local cache, haptics
├── ViewModels/   Remote thread, Chat, approval, Git, and settings state
└── Views/        Watch UI for Chat, threads, controls, approvals, Git, and settings
Vendor/SwiftSH/   Vendored SSH/libssh2 transport
Wristex.xcodeproj Xcode project and watchOS scheme
```

## Current limitations

- The app currently depends on an active SSH connection for live streaming and approvals; server-to-watch push notifications and durable background task supervision are not implemented.
- Pure SSH cannot reliably wake a suspended watchOS app. Background completion alerts require a future push path such as APNs from a trusted server component.
- The watch UI is intentionally a compact control surface, not a pixel-for-pixel desktop replacement; large diffs, rich artifacts, browser views, and full terminal output still need dedicated screens.
- There is no automated test suite in the repository. Swift syntax and isolated service typechecks can run without Xcode, but a complete watchOS build requires Xcode and the watchOS SDK.
