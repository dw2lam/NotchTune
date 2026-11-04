# NotchTune
<img width="1024" height="1024" alt="app-icon-v6" src="https://github.com/user-attachments/assets/593c9462-70fb-44d1-9967-e8ad9aeef3b1" />

Monitor your agents and music all in one place.

**NotchTune** is a native macOS companion that turns your Mac's notch, or a compact top bar on external displays, into a live control surface for music and terminal-native AI agents. It combines playback controls, agent monitoring, approvals, questions, and session jump-back in one lightweight local app.

## Highlights

- **Dynamic notch switching**: NotchTune moves between Music and Agents automatically, so the island can show the thing that matters now: current playback, active agent work, permission prompts, questions, or recently completed sessions.
- **Music controls**: Control Spotify or Apple Music from the notch, including playback, track details, artwork, progress, shuffle, repeat, love, volume, and quick open actions.
- **Agent monitoring**: Track local coding-agent sessions from the menu bar or notch, including running state, waiting approvals, questions, completions, subagents, and usage summaries.
- **Myspace**: Save dictated thoughts, drop in images or files, and keep time-based reminders in a local personal space.
- **Mirror**: A tab that turns the notch into a hand mirror: your camera, flipped like a mirror, with zoom and a camera picker. The camera is only on while the tab is open.
- **Haptics**: On a Force Touch trackpad, feel the notch's buttons, tab switches, a full ripple for play and pause, a lighter flick for skip and back, a rising "yes" for Allow and Send, a double knock for Deny and delete, a swoosh when you jump to a terminal, and a soft nudge when an agent finishes. Each one can be retuned or turned off in Personalization.
- **Character personalization**: Choose from twenty pixel characters for the island, from the dino and Claude's Clawd to a goopy blob and Italian-brainrot favourites like Tung Tung Tung Sahur, set how much they move (Calm, Lively or Still), and style the MacBook notch and an external display separately or together with Sync.
- **Notification sounds**: 32 original bundled sounds, loudness-matched to the macOS alerts, alongside system and custom sounds.
- **Finished-task summaries**: When Claude Code or Codex finishes, the completion card shows what changed (files edited, tests run and their result, turn time), worked out locally from the session's own events.
- **Meeting heads-up**: Opt in to see your next calendar meeting in the notch a few minutes ahead, with a Join button for video links and an optional quiet mode during meetings. Calendars are read on your Mac only.
- **Notch-aware layouts**: Runs as a real notch surface on MacBook displays and falls back to a clean top-center bar on external or non-notch screens.
- **Local, native, and open source**: Built with SwiftUI and AppKit. No Electron shell, no telemetry, and no remote server dependency.
- **Automatic updates**: NotchTune updates itself quietly in the background, the way Figma does. It downloads only what changed since your version (a small Sparkle delta patch, with the full app as the fallback), prepares it, and shows an **Update** button in the notch and **Restart to Update** in Settings. One click swaps in the new version and relaunches, with no installer or disk image; leave it, and it installs the next time NotchTune quits.

## Supported Integrations

NotchTune currently supports Spotify and Apple Music for playback.

For coding agents, it supports Claude Code, Codex, OpenCode, Gemini CLI, Kimi CLI, Qoder, Qwen Code, Factory, and CodeBuddy through local hooks, transcript discovery, and process matching where available.

Supported terminal jump-back includes Terminal.app, Ghostty, cmux, Kaku, WezTerm, iTerm2, and tmux. Warp support is planned.

## Quick Start

### Install The App

Download the latest `NotchTune.dmg` from [Releases](https://github.com/dw2lam/NotchTune/releases), open it, and drag `NotchTune.app` into Applications.

This release is currently unsigned. If macOS blocks the first launch, right-click `NotchTune.app`, choose **Open**, then confirm the Gatekeeper prompt.

Open NotchTune, go to **Settings → Setup**, and install hooks for the coding agents you use. Grant Accessibility permission if macOS asks; NotchTune uses it to detect terminal windows and jump back to active sessions.

### Updates

You only install NotchTune once. After that it keeps itself up to date:

1. It checks for a new version every hour (or right away from **Settings → General → Check for Updates…**).
2. It downloads the update in the background. Usually that is a small patch with just what changed, often under 1 MB; if there's no patch for your version, it downloads the full app instead.
3. When the update is ready, an **Update** button appears in the notch and **Restart to Update** in Settings. Click either one and NotchTune swaps in the new version and relaunches in a second or two, with no disk image or installer.
4. If you never click it, the update installs the next time NotchTune quits.

Permissions you grant (camera for Mirror, calendars, Accessibility) are remembered between launches. While releases are unsigned, macOS may ask again once after an update, because it ties those grants to the app's signature.

### Run From Source

Clone the repo and run the app locally:

```bash
git clone https://github.com/dw2lam/NotchTune.git
cd NotchTune
zsh scripts/launch-dev-app.sh
```

To build the hook helper used by agent integrations:

```bash
swift build -c release
```

Or open the package in Xcode:

```bash
open Package.swift
```

## Development

This repository is a Swift package with native app, core bridge, hook helper, and setup targets. For more details on the project architecture, read the [documentation index](docs/index.md).

The helper scripts are the recommended way to exercise app-bundle behavior locally because they refresh the generated assets, helper binaries, and local dev bundle.

Useful commands:

```bash
swift build
swift test
zsh scripts/harness.sh
zsh scripts/launch-dev-app.sh
zsh scripts/package-app.sh
zsh scripts/make-release-deltas.sh <tag>   # delta patches + appcast for a release
```

## Credits

NotchTune builds on work from:

- [Tuneful](https://github.com/martinfekete10/Tuneful), originally developed by [Martin Fekete](https://github.com/martinfekete10), for native macOS playback controls and interface ideas.
- [Octane0411](https://github.com/Octane0411), for the dynamic notch integration and terminal-native AI tracking foundations that helped shape NotchTune.

## What's Next

Opt-in screen context for AI assistance, more connectors, personalization options, and deeper agent workflows are planned as NotchTune continues to grow into a local-first control surface for music, personal notes, and coding agents.
