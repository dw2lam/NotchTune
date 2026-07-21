# NotchTune Code Graph

A navigation map for humans and AI agents. Read this before touching unfamiliar
subsystems; update it when you add/move/remove a subsystem, coordinator, or
cross-target contract. Line counts drift — treat sizes as relative, not exact.

Swift 6.2 package, macOS 14+. Four products + two test targets
(`Package.swift`): `NotchTuneCore` (library, no external deps),
`NotchTuneApp` (app; deps Core + MarkdownUI + Sparkle), `NotchTuneHooks`
(hook CLI), `NotchTuneSetup` (installer CLI).

## The one-paragraph mental model

Agent hooks shell out to the `NotchTuneHooks` CLI, which forwards the payload
over a Unix socket to the in-app `BridgeServer`. The server decodes per-agent
payloads into `AgentEvent`s; `AppModel.applyTrackedEvent` funnels every event
(bridge, Codex app-server, launch discovery) through `SessionState.apply(_:)`
— the **single source of truth** for session mutations — then pushes a state
snapshot back to the server (so hook responses can consult it) and the island
UI re-renders. Approvals/answers flow the reverse path as `BridgeCommand`s.
Hooks **fail open**: if the app is down, the agent runs unchanged.

```
agent → NotchTuneHooks CLI → unix socket (NDJSON/BridgeCodec) → BridgeServer
      → AgentEvent → AppModel.applyTrackedEvent → SessionState.apply
      → @Observable AppModel → IslandPanelView / notch surfaces
```

## AppModel ownership graph

`Sources/NotchTuneApp/AppModel.swift` (@Observable, central owner):

```
AppModel
├── state: SessionState                  // didSet → bridgeServer.updateStateSnapshot
├── hooks: HookInstallationCoordinator   // per-agent installs, usage monitors, intentStore
├── overlay: OverlayUICoordinator        // open/close/pop, fullscreen, pointer exit
│     └── OverlayPanelController         // NSPanel + NotchHostingView + NotchEventMonitors
├── tour: OnboardingTourController       // guided notch tour state machine
├── discovery: SessionDiscoveryCoordinator     // launch-time registry restore + transcript scan
├── monitoring: ProcessMonitoringCoordinator   // 2s liveness loop (idle-guarded)
├── codexAppServer: CodexAppServerCoordinator  // Codex.app thread events
├── playerManager: MusicPlayerManager    // Spotify/Apple Music via ScriptingBridge
├── myspaceStore: MyspaceStore           // thoughts/attachments/reminders (local JSON)
├── updateChecker: UpdateChecker         // Sparkle
├── watchRelay: WatchNotificationRelay?  // Watch/phone HTTP+SSE companion
└── bridgeServer/bridgeClient (private)  // socket server + observer stream
```

Back-references are `weak` (e.g. `OverlayUICoordinator.appModel`). Coordinators
get `stateAccessor` closures instead of holding state.

## Subsystem → file map

### NotchTuneCore
| Subsystem | Files |
|---|---|
| Session model + reducer | `SessionState.swift` (reducer; ONLY place sessions mutate), `AgentEvent.swift` (versioned schema), `AgentSession.swift` (+`SessionOrigin`: `.demo` is excluded from all persistence), `AgentHookIntent.swift` (`AgentIdentifier`), `AgentIntentStore.swift` (intents + onboarding progress, UserDefaults) |
| Bridge/IPC | `BridgeServer.swift` (per-agent `handleXHook`), `BridgeTransport.swift` (socket paths, codec), `BridgeCommandClient.swift` (sync, used by CLI), `LocalBridgeClient.swift` (async observer stream) |
| Per-agent integrations (pattern: `XHooks` payload + `XHookInstaller` + `XHookInstallationManager`) | Claude (`ClaudeHooks/…/ClaudeUsage/ClaudeSessionRegistry/ClaudeTranscriptDiscovery/ClaudeStatusLineInstallationManager`), Codex (`CodexHooks/CodexSessionTracking/CodexAppServer/CodexUsage`), Gemini, Cursor (+registry/transcript), Antigravity, Kimi (reuses Claude shape), OpenCode (plugin-based), Warp (`WarpProcessResolver/WarpSQLiteReader`). CC-forks Qoder/Qwen/Factory/CodeBuddy reuse the Claude installer with a different home dir |
| Install/health shared | `HookHealthCheck.swift`, `HooksBinaryLocator.swift`, `HookSkipConfiguration.swift`, `LegacyInstallMigration.swift` (OpenIsland→NotchTune data migration; runs first in `NotchTuneMain.main`) |
| Watch companion | `WatchHTTPEndpoint.swift`, `WatchNotificationRelay.swift` |

### NotchTuneApp
| Subsystem | Files |
|---|---|
| Shell | `NotchTuneApp.swift` (entry `NotchTuneMain` → migration → SwiftUI App), `AppModel.swift`, `AppModelTypes.swift` (NotchStatus/IslandTab/preferences enums) |
| Overlay windowing | `OverlayPanelController.swift` (panel widths live here), `OverlayUICoordinator.swift`, `OverlayDisplayConfiguration.swift`, `FullscreenDisplayDetection.swift`, `CGSSpacePrivate.swift`, `IslandChromeMetrics.swift`, `IslandSurface.swift` |
| Island UI | `Views/IslandPanelView.swift` (largest file; panel composition, header lanes, glass wiring, tour coach mount), `Views/V6NotchContent.swift` (closed pill + music surfaces + `IslandPreviewPill`), `Views/UnifiedBars.swift` (glyph; idle 8fps), `Views/LiquidGlass.swift` (settings + `IslandSurfaceBackground`), shapes (`NotchShape.swift` = `GrowingNotchShape`+clip modifier, `OpenedIslandSurfaceShape.swift`, `V6ClosedPillShape.swift` w/ `V6Palette`), `IslandDesignPalette.swift` (status tints) |
| Music | `Music/MusicPlayerManager.swift` (facade; 1s timer only while panel visible; paused-skip for Apple Events), backends `MusicSpotifyManager/MusicAppleMusicManager/MusicNoneManager` (: `MusicPlayerProtocol`), SB glue `MusicApplication/SpotifyApplication`, `Views/Music/*` panel views |
| Myspace | `MyspaceStore.swift` (thoughts/reminders/attachments; UserNotifications), `Views/MyspacePanelView.swift` (+Reminders) |
| Onboarding | `OnboardingTourController.swift` (phase machine; demo session id `onboarding-tour-demo`), `Views/Onboarding/` (wizard `OnboardingView`+`OnboardingSteps`, `OnboardingTheme`, `TourCoachView`) |
| Hooks (app side) | `HookInstallationCoordinator.swift` (install/uninstall + busy flags + usage monitors: Claude 20s / Gemini 60s / Codex 120s, diff-guarded writes) |
| Session tracking / jump-back | `ProcessMonitoringCoordinator.swift` (2s loop; AppleScript probes SKIPPED when no live sessions + no agent processes), `ActiveAgentProcessDiscovery.swift` (ps/lsof), `ForegroundTerminalSessionProbe.swift`, `TerminalSessionAttachmentProbe.swift`, `TerminalJumpService.swift`, `TerminalJumpTargetResolver.swift`, `TerminalTextSender.swift`, `KeystrokeInjector.swift` (AX) |
| Settings | `Views/SettingsView.swift` (tabs incl. Setup + Onboarding entries), `Views/AppearanceSettingsPane.swift`, `NudgeSettings.swift`, `NotificationSoundService.swift`, `LaunchAtLoginService.swift`, `UpdateChecker.swift`, `Localization/LanguageManager.swift`, `ResourceBundle.swift` |
| Harness/debug | `HarnessLaunchConfiguration/HarnessRuntimeMonitor/HarnessArtifactRecorder.swift`, `IslandDebugScenario.swift` (`loadDebugSnapshot` REPLACES SessionState — never use it for additive injection; use `SessionState.insertSession`) |

## Size outliers (organization candidates)

IslandPanelView (~3.3k), BridgeServer (~2.9k), AppModel (~2.4k),
AppearanceSettingsPane (~1.7k), CodexSessionTracking, SettingsView,
HookInstallationCoordinator, OverlayPanelController, ClaudeHooks,
TerminalSessionAttachmentProbe, TerminalJumpService (each ~1.3–1.5k).
These are god-files; prefer extracting cohesive subviews/handlers when touching
them rather than growing them further.

## Idle-performance contracts (don't regress these)

- Process monitor (2s): AppleScript terminal snapshots only run when there are
  tracked live sessions or discovered agent processes.
- Closed-pill glyph: idle 8fps / waiting 15fps / running display-rate;
  `glyphPaused` freezes it when opened/fullscreen/auto-hidden.
- Usage monitors: Claude 20s, Gemini 60s, Codex 120s; `@Observable` writes are
  diff-guarded (no-op refresh must not invalidate views).
- Music: 1s timer only while the music panel is visible; while paused only
  `pollForTrackChanges` talks to the player (no volume/seek/settings events).
- Glass: backdrop renders OUTSIDE the morph clip; after an opened-window
  resize settles, `glassResolveTick` re-renders it (blur-fallback fix).
- Registry persistence: debounced 250ms, off-main, filters `.demo` origin.

## Conventions (enforced by review)

- `SessionState.apply(_:)` is the single source of truth for session mutations.
- All Core models `Sendable + Codable`; Core has no UI imports.
- Hooks fail open; only a denied PreToolUse writes a blocking directive.
- Adding an agent = Core payload/installer/manager + `BridgeServer.handleXHook`
  + CLI `--source x` branch + AppModel passthroughs + Setup pane row.
- Never `git --amend`/`reset --hard`; conventional commits.
- Rename legacy: on-disk state contracts keep `open-island` names on purpose
  (sidecar manifests, managed-hook markers, /tmp cache/sockets) so existing
  installs stay recognized. See `LegacyInstallMigration`.

## Operational scripts (uncalled by CI but intentional)

- `scripts/clean-user-env.sh` — wipe a user environment of NotchTune (+legacy
  OpenIsland/VibeIsland generations) for fresh-install testing.
- `scripts/replay-bridge-scenarios.py` — manual UI verification via replayed
  bridge traffic.
- `scripts/verify-ghostty-jumps.sh` — drives the env-gated
  `TerminalJumpServiceTests` Ghostty integration test.

## Deeper docs

`docs/architecture.md`, `docs/product.md`, `docs/hooks.md`,
`docs/notch-surface-model.md`, `docs/session-state-refactor.md`,
`docs/releasing.md` (+`release-signing.md`, `packaging.md`),
`docs/worktree-workflow.md`, `AGENTS.md`, `CLAUDE.md`.
