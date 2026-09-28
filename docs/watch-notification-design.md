# Apple Watch Notification Design

## Motivation

When an agent is waiting for permission approval or an answer to a question, the developer may not notice — whether they're heads-down writing code on the Mac, or away getting a coffee.
A vibration on the wrist is a stronger sensory channel than the island on screen — it can't be blocked by other windows, and it won't be ignored while focused.
Watch notifications let the developer sense immediately that the agent needs attention, and act on it quickly.

## Design Principles

1. **Wrist = a quick decision panel**, not a full control panel. Only push events that need human intervention; don't show terminal output.
2. **Complete the interaction within 5 seconds.** See notification → understand context → take action.
3. **Silent by default.** A running session doesn't interrupt; it only vibrates when attention is needed.
4. **Fail open.** A broken push pipeline must not affect normal operation on the Mac side.
5. **Zero extra processes.** Reuse the existing macOS app's BridgeServer instead of introducing a new intermediary service.

---

## Interaction Design

### Which events get pushed?

| Event | Push? | Reason |
|---|---|---|
| `permissionRequested` | **Yes** | Agent is blocked, waiting for a human to approve |
| `questionAsked` | **Yes** | Agent is blocked, waiting for a human to answer |
| `sessionCompleted` | **Yes** | Task finished, worth knowing |
| `sessionStarted` | No | Started by the user themselves, no notification needed |
| `activityUpdated` | No | Too frequent, doesn't need attention |

### Notification Styles

#### 1. Permission Request Notification

```
┌─────────────────────────┐
│  🔧 Claude Code         │
│  ───────────────────     │
│  wants to run:           │
│  "rm -rf build/"         │
│                          │
│  📁 ~/Projects/my-app    │
│                          │
│  ┌─────────┐ ┌────────┐ │
│  │  Allow  │ │  Deny  │ │
│  └─────────┘ └────────┘ │
└─────────────────────────┘
```

**Field mapping:**
- Title: `PermissionRequest.title` (tool name)
- Body: `PermissionRequest.summary` (action summary)
- Subtitle: the session's working directory (from `JumpTarget.workingDirectory`)
- Action buttons: `primaryActionTitle` / `secondaryActionTitle`

**Watch interaction flow:**
1. Wrist vibrates (haptic: `.notification`)
2. Raise wrist to see the notification card
3. Tap Allow → relayed back via WCSession → macOS app executes `PermissionResolution.allowOnce`
4. Tap Deny → relayed back via WCSession → macOS app executes `PermissionResolution.deny`
5. No action → no effect, the Mac side is still waiting and the user can return to the computer to act

#### 2. Question / Answer Notification

```
┌─────────────────────────┐
│  💬 Codex               │
│  ───────────────────     │
│  asks:                   │
│  "Which database         │
│   should I use?"         │
│                          │
│  ┌───────────────────┐   │
│  │  PostgreSQL       │   │
│  │  SQLite           │   │
│  │  MySQL            │   │
│  └───────────────────┘   │
│                          │
│  ┌──────────────────┐    │
│  │ Open on Mac ↗    │    │
│  └──────────────────┘    │
└─────────────────────────┘
```

**Field mapping:**
- Title: `QuestionPrompt.title`
- Options list: `QuestionPrompt.options` (show up to 4; beyond that, show "Open on Mac")

**Watch interaction flow:**
1. Wrist vibrates
2. See the question and its options
3. Tap an option → relayed back via WCSession → macOS app submits `QuestionPromptResponse`
4. Too many or too complex options → tap "Open on Mac" → just marks as read, handle on the Mac

#### 3. Session Completed Notification (the most important one)

```
┌─────────────────────────┐
│  ✅ Claude Code          │
│  ───────────────────     │
│  Task completed          │
│  "Add user auth flow"    │
│                          │
│  ┌──────────────────┐    │
│  │   Dismiss        │    │
│  └──────────────────┘    │
└─────────────────────────┘
```

**Field mapping:**
- Title: agent tool name
- Body: `SessionCompleted.summary`

**This is the core value of Watch notifications** — after an agent finishes a task, a developer may not notice at all; the island on screen is easy to miss, but a vibration on the wrist isn't. Purely informational, no action required.

---

## Communication Architecture

### Approach: Bonjour + local HTTP (no cloud service, no extra process)

Communication happens in two segments, using different technologies:

- **macOS ↔ iPhone**: Bonjour LAN discovery + HTTP (requires the same WiFi network)
- **iPhone ↔ Watch**: WCSession (Apple Watch Connectivity framework, supports Bluetooth and WiFi)

Core idea: add a lightweight HTTP endpoint inside the existing macOS app; the iPhone app discovers and connects to it automatically via Bonjour. No extra process needed.

```
Claude Code / Codex
    │
    │  Hook (stdin/stdout)
    ↓
NotchTuneHooks (CLI)
    │
    │  Unix socket
    ↓
BridgeServer (inside the macOS app, already exists)
    │
    │  AppModel state change
    ↓
WatchHTTPEndpoint (new, macOS side)
    │  - Bonjour broadcast _notchtune._tcp
    │  - /events (real-time SSE push)
    │  - /resolution (receives the returned action)
    │
    │  HTTP (LAN, same WiFi)
    ↓
iPhone App (NotchTuneMobile)
    │  - Bonjour discovers the Mac
    │  - Receives SSE events → local notification
    │  - Relays to Watch via WCSession
    │
    │  WCSession (Bluetooth/WiFi)
    ↓
Watch (notification mirroring + UNNotificationAction)
    │
    │  User taps Allow / Deny / an option
    ↓
iPhone App
    │
    │  HTTP POST /resolution (returns the decision)
    ↓
WatchHTTPEndpoint (macOS side)
    │
    │  Calls AppModel to execute the resolution
    ↓
BridgeServer → hook process → agent continues
```

### Why Bonjour + HTTP

| Dimension | Bonjour + HTTP | CloudKit |
|---|---|---|
| Latency | Sub-second (direct LAN connection) | 1-3 seconds (relayed through the cloud) |
| Network dependency | Same WiFi, no internet required | Requires internet |
| Privacy | Data stays entirely local | Passes through Apple's servers |
| Extra process | None (reuses the macOS app) | None |
| Extra configuration | None | Requires a CloudKit container, schema, subscription |
| Complexity | Low | High |

**Limitation: the Mac and iPhone must be on the same WiFi network.** In practice this is almost never a problem — while developing, the Mac and phone are usually on the same network. When leaving WiFi, the notification pipeline breaks, but this doesn't affect normal Mac-side operation (fail open).

### HTTP Endpoint Design

A lightweight HTTP server (reusing NWListener) added inside the macOS app, exposing the following endpoints:

| Endpoint | Method | Description |
|---|---|---|
| `/events` | GET (SSE) | Real-time event stream; the iPhone keeps a long connection open to receive pushes |
| `/resolution` | POST | iPhone relays back the user's decision made on the Watch |
| `/status` | GET | Current connection status, number of active sessions |

### Event Push Format (SSE)

```
event: permissionRequested
data: {"sessionID":"abc-123","agentTool":"claudeCode","title":"Bash: rm -rf build/","summary":"Remove build directory","workingDirectory":"~/Projects/my-app","primaryAction":"Allow","secondaryAction":"Deny","requestID":"req-456"}

event: sessionCompleted
data: {"sessionID":"abc-123","agentTool":"codex","summary":"Add user auth flow"}
```

### Action Callback Format (HTTP POST)

```json
POST /resolution
{
    "requestID": "req-456",
    "action": "allow"          // "allow" | "deny" | option text
}
```

### Pairing Mechanism

The first connection needs identity confirmation, to prevent connecting to someone else's Mac.

**Pairing flow:**

```
Mac                              iPhone
 │                                 │
 │  1. Bonjour broadcast          │
 │  _notchtune._tcp               │
 │  TXT: { name: "Wang's MacBook Pro" } │
 │ ──────────────────────────────→ │
 │                                 │  2. Discovers the Mac, shows the device name
 │                                 │     User taps to connect
 │                                 │
 │  3. Mac displays a 4-digit pairing code │
 │  (macOS app settings page / notification) │
 │                                 │
 │                                 │  4. iPhone enters the pairing code
 │  ←──────────────────────────── │
 │                                 │
 │  5. Verification passes         │
 │     generates a session token   │
 │     returns it to the iPhone    │
 │ ──────────────────────────────→ │
 │                                 │  6. Saves the token
 │                                 │     future requests include the token, no re-pairing needed
```

**Design points:**
- 4-digit numeric code (more concise than claude-watch's 6-digit code; secure enough for a LAN scenario)
- The pairing code is valid for 2 minutes, then regenerates
- Once paired, the iPhone saves the session token and connects automatically afterward
- On the Mac side, the settings page can list paired devices and revoke pairing
- When multiple Macs on the same WiFi are discovered, the iPhone lists device names for the user to pick from

### User Setup Flow

1. Download the iPhone app from the App Store (one-time)
2. Open the iPhone app → grant notification permission (one-time)
3. Mac and iPhone on the same WiFi → iPhone automatically discovers the Mac
4. Mac shows a 4-digit pairing code → enter it on the iPhone → pairing complete (one-time)
5. Connects automatically afterward, no further action needed

---

## Engineering Breakdown

### New Targets Needed

| Target | Type | Responsibility |
|---|---|---|
| `NotchTuneMobile` | iOS App | Discover the Mac via Bonjour, receive SSE events, local notifications, relay to Watch via WCSession |
| `NotchTuneShared` | Shared Framework | Message type definitions and encoding/decoding, shared between macOS and iOS |

**No standalone watchOS App target needed** (v1). Watch notifications are implemented through the iOS app's `UNNotificationCategory` + `UNNotificationAction`, leveraging automatic system mirroring.

### macOS-Side Changes

Add a new `WatchHTTPEndpoint` inside `NotchTuneApp`:

```swift
/// Starts a lightweight HTTP server inside the macOS app, broadcast via Bonjour.
/// The iPhone app connects and receives events over SSE, and posts back action decisions.
class WatchHTTPEndpoint {
    let appModel: AppModel

    // Bonjour broadcast _notchtune._tcp
    func startAdvertising() { ... }

    // SSE: push an event when the session phase changes to waitingForApproval / waitingForAnswer / completed
    func handleEventsStream(_ connection: NWConnection) { ... }

    // POST /resolution: receives the action decision relayed back from the iPhone, drives AppModel to execute it
    func handleResolution(_ request: HTTPRequest) { ... }
}
```

### iOS App (NotchTuneMobile)

**Minimal, but with enough content to pass review:**

1. **Home screen**: connection status + recent notification list (permission requests / questions / completions)
2. **Settings screen**: notification type toggles, silent mode
3. **Background capabilities:**
   - Bonjour discovers the macOS app → receives events over a long-lived SSE connection
   - On receiving an event → creates a `UNNotificationRequest` (with category and action) → automatically mirrors to the Watch
   - User taps an action on the Watch → `UNUserNotificationCenter.delegate` callback → HTTP POST relays it back to the Mac
   - WCSession communicates with the Watch (relaying Watch actions back)

**Notification Category definitions:**

```swift
// Permission request
let allowAction = UNNotificationAction(identifier: "ALLOW", title: "Allow", options: [])
let denyAction = UNNotificationAction(identifier: "DENY", title: "Deny", options: [.destructive])
let permissionCategory = UNNotificationCategory(
    identifier: "PERMISSION_REQUEST",
    actions: [allowAction, denyAction],
    intentIdentifiers: []
)

// Question / answer — dynamically generated category (options differ per question)
// Encode option info in the category identifier, e.g. "QUESTION_opt1_opt2_opt3"
```

---

## User Configuration

New additions to the macOS app's settings:

- **Watch notifications toggle** (off by default)
- **Notification type checkboxes**: permission requests / questions / completion notifications
- **Silent mode**: completion notifications don't vibrate
- **Connection status**: shows whether the iPhone is paired and whether the Watch is reachable

---

## Implementation Steps

### Step 1: macOS side — WatchHTTPEndpoint
- Start an HTTP server inside the macOS app with `NWListener`
- Register the Bonjour service `_notchtune._tcp`
- Implement the `/events` SSE endpoint: listen for `AppModel` session phase changes, push JSON events
- Implement the `/resolution` POST endpoint: receive the decision, call `AppModel` to execute it
- **Can be developed and tested purely on the Mac side** (use curl to simulate an iPhone connection and verify SSE pushes)

### Step 2: iOS App — skeleton + Bonjour discovery + pairing
- Create a new Xcode project (NotchTuneMobile)
- Use `NWBrowser` to search for `_notchtune._tcp`, show the device name once the Mac is discovered
- Implement the pairing flow: user selects the Mac → enters the 4-digit pairing code → obtains a session token
- Connect via SSE, print received events to the console
- **Verify the Mac ↔ iPhone communication link + pairing mechanism**

### Step 3: iOS App — local notifications + Watch mirroring
- Register `UNNotificationCategory` (permission request, question, completion)
- On receiving an SSE event → create a `UNNotificationRequest` → fire a local notification
- **Wear the Watch to verify notification mirroring works correctly**

### Step 4: Two-way interaction
- `UNUserNotificationCenter.delegate` handles button taps on the Watch
- Tap → HTTP POST `/resolution` relays it back to the Mac
- Mac side executes `PermissionResolution` → agent continues
- **End-to-end verification: agent requests permission → Watch vibrates → tap Allow → agent continues**

### Step 5: Polish
- iOS app UI (connection status page, notification history list, paired device management)
- macOS settings page (Watch notifications toggle, pairing code display, paired device list)
- Background SSE reconnection logic
- Error handling and edge cases

### Future Extensions (optional)
- If notification mirroring isn't enough, develop a standalone watchOS App target
- Session list overview, Complication showing the count of pending items

---

## Open Questions

1. **iOS app review** — needs enough UI content. Plan: recent notification history list + settings page + connection status page.
2. **Background SSE connection** — the SSE long connection may be dropped by the system while the iPhone app is in the background. Need to handle reconnection logic, and evaluate whether Background Modes are needed (e.g. `background fetch` or `remote notifications`).
3. **Multiple-Mac discovery** — when multiple Macs on the same WiFi are running Open Island, Bonjour will discover multiple services. The iPhone lists device names for the user to choose from and pair; the token mechanism ensures subsequent connections go to the correct Mac.
4. **Xcode project structure** — the current project uses Swift Package Manager; the iOS target needs an Xcode project or workspace. Need to evaluate whether to add it inside `Package.swift` or create a separate Xcode project.
5. **Local network permission** — on iOS 14+, the first access to the local network triggers a permission prompt; need to declare `NSLocalNetworkUsageDescription` and the Bonjour service type in Info.plist.

---

## References

- [claude-watch](https://github.com/shobhit99/claude-watch) — a similar project, using a Node.js bridge + Bonjour + WCSession approach. Our approach is simpler: it reuses the existing macOS app instead of requiring an extra Node.js process.
- [NWListener (Network.framework)](https://developer.apple.com/documentation/network/nwlistener) — lightweight HTTP server on the macOS side
- [NWBrowser (Bonjour)](https://developer.apple.com/documentation/network/nwbrowser) — LAN service discovery on the iOS side
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession) — iPhone ↔ Watch communication
- [UNNotificationAction](https://developer.apple.com/documentation/usernotifications/unnotificationaction) — Watch notification action buttons
