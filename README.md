# Wristex

Wristex is a standalone watchOS remote control for Codex running on a remote
Linux development host. The watch opens SSH directly to the host and launches
`codex app-server --stdio` inside that SSH session; there is no Wristex relay
or HTTP service in the middle.

## Requirements

- Xcode 26 or newer
- watchOS 10 or newer
- A reachable SSH host with password authentication enabled, or a private key pasted into Wristex Settings
- Codex CLI installed and authenticated on that host
- A Git repository on the host for the configured workspace

On the Linux host, authenticate Codex once for the SSH user and verify that
the same user can run `codex app-server --stdio`. Wristex starts that process
itself after SSH authentication; you do not need to expose an HTTP port or
enable Codex remote-control pairing.

## Build

1. Open `Wristex.xcodeproj` in Xcode.
2. Select your Apple development team for the **Wristex** target.
3. Select an Apple Watch or watchOS simulator and run.

The SwiftSH source is pinned under `Vendor/SwiftSH`; Xcode resolves its pinned libssh2 watchOS binary through Swift Package Manager.

## Connect

Open **Settings** on the watch and enter the SSH hostname, username, port,
remote workspace, and either a password or a dedicated PEM private key. Tap
**Save & Test**. The first successful connection pins the host's SHA-1
fingerprint; later key changes are rejected.

The Codex app server is the source of truth for threads, history, models,
turns, streamed events, and approval prompts. The watch only caches the last
known thread/message state for offline display. Git actions still run directly
inside the configured remote workspace.

The app-server protocol is experimental and versioned with the installed Codex
CLI. Keep the host's CLI reasonably current and test `codex app-server --help`
after upgrades.

The voice button first uses Codex's experimental realtime audio/transcription
methods over SSH and sends the resulting transcript as a turn. If the remote
Codex build does not expose realtime voice, Wristex falls back to the native
watchOS dictation controller.

Keep the watch app in the foreground while a turn is running. watchOS may
suspend a direct SSH socket in the background, so reliable background alerts
would require an explicitly approved notification/push design.

Passwords, private keys, and key passphrases are stored in Keychain. Only
connect to hosts you control.
