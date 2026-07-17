# Wristex Agent Guidelines & Specifications

This document defines how autonomous AI coding agents (such as OpenAI Codex, local workspaces, or future Antigravity runs) should interact with the **Wristex** watchOS client. 

Because Apple Watch screens are tiny and battery-constrained, agents must format outputs, messages, and approvals specifically to fit the wrist UI.

---

## 1. Thread Communication Guidelines

### Message Formatting
*   **Be extremely concise**: Avoid long intros, conversational filler, and extensive code explanations in threads.
*   **Summarize changes**: Instead of printing entire blocks of code, describe the action in 1-2 sentences.
    *   *Bad*: *"I have inspected the compiler logs and found that line 45 has a missing semicolon. Here is the full code: ... [100 lines of code] ... I've fixed it by adding the semicolon."*
    *   *Good*: *"Fixed syntax error in `NetworkManager.swift:45` (added missing semicolon). Build now succeeds!"*
*   **Markdown Support**: The watch app renders standard text labels. Limit markdown formatting to simple bullet points. Avoid complex nested markdown tables or blockquotes in chat bubbles.

---

## 2. Tool Approvals Specification

The Wristex app displays pending tool execution prompts in a high-priority approval queue. To make this readable on a ~41mm or ~45mm screen, the agent backend must structure `ApprovalRequest` details dynamically.

### Payload Schema for `GET /api/approvals`
```json
[
  {
    "id": "appr-1234",
    "toolName": "run_command",
    "details": "git commit -m 'feat: update styling'",
    "status": "pending",
    "timestamp": "2026-07-17T20:28:00.000Z"
  }
]
```

### Guidelines for different tools:

#### A. Command Line / Shell execution (`run_command`)
*   **Format**: Prepend command details with a `$` prompt indicator.
*   **Trimming**: If the command is extremely long, truncate parameters or arguments so the command's primary intent is visible.
    *   *Original*: `npx -y create-vite-app@latest ./ --template react-ts --skip-git --verbose`
    *   *Details for Watch*: `$ npx create-vite-app ... (react-ts)`

#### B. File Edits / File Writes (`write_file` / `replace_file_content`)
*   **Format**: Specify the target file and a short change delta summary rather than full diff contents.
*   **Details format**: `[Write] path/to/file.swift (+12 lines, -4 lines) - Added haptic cues`

---

## 3. Git Operations API

The watch app can trigger automated git operations. The agent should configure its hooks to handle these actions gracefully:

1.  **Pull (`POST /api/git/action` with `{"action": "pull"}`)**:
    *   The agent must fetch from the remote repository, merge/rebase, and check for conflicts.
    *   Return a message summarizing the fetch status (e.g. `"Pulled 3 commits. Branch up to date."`).
2.  **Commit (`POST /api/git/action` with `{"action": "commit", "commitMessage": "..."}`)**:
    *   Stage all current changes (`git add .` or equivalent).
    *   Commit with the user's dictated commit message.
3.  **Push (`POST /api/git/action` with `{"action": "push"}`)**:
    *   Push the active branch to the remote origin.
    *   If upstream is missing, configure it automatically.

---

## 4. LLM Intelligence & Model Selection

The agent system should expose its available model routes via `GET /api/models`. When a user toggles the model on their Apple Watch:
*   The watch makes a request to `POST /api/threads/{id}/model` specifying the desired model ID.
*   The agent must swap its underlying inference system for that thread's future interactions.

### Recommended Model Profiles:
*   `gemini-1-5` (or `pro`): For complex architectural questions, deep reasoning, and multi-file code editing.
*   `gpt-4o` (or similar standard models): For standard code modifications, commits, and rapid queries.
*   `claude-3-5` (or `flash`): For rapid iterations, refactoring, and quick explanations.
