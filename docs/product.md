# Product Scope

## Problem

CLI coding agents are powerful, but they pull attention away from the editor and terminal. Developers need a lightweight control surface to monitor work, approve actions, answer questions, and return to the right session quickly — without handing their machine over to a closed-source paid app.

## Target User

- macOS developers using terminal-based coding agents daily
- Users running more than one agent or more than one terminal session
- Users who care about low latency, native behavior, and open-source transparency

## Product Principles

- **Open source** — all code is public, all contributions are AI-produced
- **Local first** — no server dependency, no accounts, no analytics
- **Native macOS** — SwiftUI + AppKit, not a web wrapper
- **Terminal-native** — built to support the terminal workflow, not replace it
- **Fail open** — if the app or bridge is unavailable, agents keep running unchanged

## Supported Code Agents

| Agent | Status | Notes |
|---|---|---|
| **Claude Code** | Supported | Hook integration, JSONL session discovery, status line bridge, usage tracking |
| **Codex** | Supported | Full hook integration (SessionStart, UserPromptSubmit, Stop), usage tracking |
| **OpenCode** | Supported | JS plugin integration, permission/question flows, process detection |
| **Qoder** | Supported | Claude Code fork — same hook format, config at `~/.qoder/settings.json` |
| **Qwen Code** | Supported | Claude Code fork — same hook format, config at `~/.qwen/settings.json` |
| **Factory** | Supported | Claude Code fork — same hook format, config at `~/.factory/settings.json` |
| **CodeBuddy** | Supported | Claude Code fork — same hook format, config at `~/.codebuddy/settings.json` |
| **Gemini CLI** | Supported | Hook integration (`SessionStart`, `BeforeAgent`, `AfterAgent`, `SessionEnd`, `Notification`), session tracking, terminal jump metadata, completion-card compatibility handling |
| **Cursor** | Supported | Hook integration via `~/.cursor/hooks.json`, session registry and transcript discovery |
| **Antigravity** | Supported | Hook integration via `~/.gemini/config/hooks.json` |
| **Kimi CLI** | Supported | Hook integration via `~/.kimi/config.toml` `[[hooks]]` (Moonshot AI). Kimi's hook payload is byte-compatible with Claude Code, so runtime reuses the Claude decode path; a dedicated TOML installer preserves user-authored hooks |

## Supported Terminals

| Terminal | Status | Notes |
|---|---|---|
| **Terminal.app** | Full Support | Jump-back with TTY targeting |
| **Ghostty** | Full Support | Jump-back with ID matching |
| **cmux** | Full Support | Jump-back via Unix socket API |
| **Kaku** | Full Support | Jump-back via CLI pane targeting |
| **WezTerm** | Full Support | Jump-back via CLI pane targeting |
| **iTerm2** | Full Support | Jump-back with session ID / TTY matching |
| **tmux** (multiplexer) | Full Support | Jump-back with session/window/pane targeting |
| **Warp** | Supported | Jump-back to the matching tab using Warp's local database; needs Accessibility |

NotchTune also jumps back to Codex.app and to editors with integrated terminals: Cursor, VS Code (and Insiders), Windsurf, Trae and the JetBrains IDEs.

## Features

- **Notch overlay** — sits in the notch area on notch Macs, falls back to a compact top-center bar on external displays or non-notch Macs
- **Settings** — General (with version and updates), Setup (hook install/uninstall), Appearance, Display, Sound, Music
- **Onboarding** — a setup assistant and guided notch tour on first launch, both reopened from Settings → General
- **Notification mode** — auto-height panel for permission requests and session events
- **Notification sounds** — configurable system sounds with mute toggle
- **i18n** — English only
- **Session discovery** — auto-discover from local transcripts, persist across launches
- **Process discovery** — match active agents from the process table (in-process sysctl/libproc, `ps`/`lsof` fallback)
- **DMG packaging** — stable self-signed builds, released by hand (see `docs/releasing.md`)
- **Auto-update** — Sparkle background downloads with delta patches, a quiet Update button, and an opt-out
- **Myspace** — local thoughts, dictated text, copied file/image attachments, and reminders

## Success Criteria

- Agent events appear in the overlay with low latency
- Approval and answer actions round-trip back to the source process
- The app can restore focus to the owning terminal window reliably
- Idle resource usage remains low enough for all-day background use

## Future Directions

- Sound packs, themes, and onboarding polish
- Deeper terminal split targeting
- Opt-in, privacy-reviewed screen context for AI assistance
