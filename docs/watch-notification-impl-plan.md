# Apple Watch Notifications — Implementation Plan

> Design doc: [watch-notification-design.md](./watch-notification-design.md)
> Branch: `worktree-feat-watch-notification`

---

## Architecture Overview

```
┌─ Mac (inside the NotchTuneApp process) ──────────────────────────┐
│                                                                   │
│  Agent → Hook → BridgeServer → AppModel                           │
│                                    │                              │
│                                    │ listens for phase changes    │
│                                    ↓                              │
│                           WatchNotificationRelay                  │
│                                    │                              │
│                                    ↓                              │
│                           WatchHTTPEndpoint                       │
│                           ┌────────────────────┐                  │
│                           │ Bonjour broadcast   │                  │
│                           │ GET  /events (SSE)  │── push events ──┐│
│                           │ POST /resolution    │← decision back ─┐│
│                           │ POST /pair          │            ││   │
│                           │ GET  /status        │            ││   │
│                           └────────────────────┘            ││   │
└──────────────────────────────────────────────────────────────┼┼───┘
                                                               ││
                         ～～～ same WiFi ～～～                   ││
                                                               ││
┌─ iPhone (NotchTuneMobile) ──────────────────────────────────┼┼───┐
│                                                              ││   │
│  NWBrowser (Bonjour discovery) → SSEClient (long-lived) ←────┘│   │
│       │                                                       │   │
│       ↓ receives an event                                     │   │
│  UNNotificationRequest (local notification, with Action)       │   │
│       │                                                       │   │
│       │ automatic system mirroring                             │   │
│       ↓                                                       │   │
│  Apple Watch (notification card + Allow/Deny buttons)          │   │
│       │                                                       │   │
│       │ user taps                                              │   │
│       ↓                                                       │   │
│  UNNotificationCenter.delegate → HTTP POST /resolution ───────┘   │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Step 1: macOS side — WatchHTTPEndpoint

**Goal**: add a lightweight HTTP server + Bonjour broadcast inside the macOS app. Testable standalone with curl.

### New Files

| File | Responsibility |
|---|---|
| `Sources/NotchTuneCore/WatchHTTPEndpoint.swift` | NWListener TCP server, Bonjour broadcast, HTTP routing, pairing/token management |
| `Sources/NotchTuneCore/WatchNotificationRelay.swift` | Listens for AppModel state changes, builds SSE events, handles resolution callbacks |

### WatchHTTPEndpoint Detailed Design

- Create a TCP server with `NWListener` (Network.framework), which has built-in Bonjour support
- Service type: `_notchtune._tcp`, TXT record contains the device name
- Manually parse HTTP/1.1 requests (NWListener hands you raw TCP, so you need to parse HTTP yourself)
- SSE response: `Content-Type: text/event-stream`, keep the connection open

**Endpoints:**

| Path | Method | Auth | Function |
|---|---|---|---|
| `POST /pair` | JSON | None | Submit the 4-digit pairing code; on success, returns a session token |
| `GET /events` | SSE | Bearer token | Real-time event stream |
| `POST /resolution` | JSON | Bearer token | Watch action decision callback |
| `GET /status` | JSON | Bearer token | Connection status, number of active sessions |

**Pairing flow:**
- The macOS app generates a random 4-digit code on launch, valid for 2 minutes
- The user sees the pairing code on the macOS settings page or in a notification
- The iPhone app submits the pairing code → on verification success → a UUID session token is returned
- The token is persisted in the Keychain; subsequent requests skip pairing

### WatchNotificationRelay Detailed Design

- Holds a reference to `WatchHTTPEndpoint`
- Listens for `AppModel.state` changes (via the `applyTrackedEvent()` callback)
- Filters events that need to be pushed:
  - `sessionCompleted` → push a completion notification
  - `permissionRequested` → push a permission request (including the requestID)
  - `questionAsked` → push a question (including its options)
- On receiving a `/resolution` POST → find the corresponding session by requestID → call BridgeServer's resolution logic

### Files to Modify

| File | Change |
|---|---|
| `Sources/NotchTuneApp/AppModel.swift` | Add a `watchRelay` property; notify the relay after events are applied in `applyTrackedEvent()` (~L745) |
| `Sources/NotchTuneCore/BridgeServer.swift` | Expose `resolvePendingClaudeInteraction()` (~L1638) and `resolvePendingClaudeQuestion()` (~L1704), or forward via BridgeCommand |

### Verification

```bash
swift build

# After launching the app:
# 1. Pair
curl -X POST -d '{"code":"1234"}' http://<mac-ip>:<port>/pair
# Returns {"token":"uuid-xxx"}

# 2. Listen to SSE
curl -N -H "Authorization: Bearer uuid-xxx" http://<mac-ip>:<port>/events

# 3. Trigger an agent event → observe the curl output
# 4. Post back a decision
curl -X POST -H "Authorization: Bearer uuid-xxx" \
  -d '{"requestID":"req-456","action":"allow"}' \
  http://<mac-ip>:<port>/resolution
```

---

## Step 2: iOS App — skeleton + Bonjour discovery + pairing

**Goal**: create the new iOS app, implement Bonjour discovery and pairing.

### Project Structure

```
ios/
├── NotchTuneMobile.xcodeproj
└── NotchTuneMobile/
    ├── App.swift                    # SwiftUI entry point
    ├── ContentView.swift            # Home screen: connection status + notification history
    ├── Network/
    │   ├── BonjourDiscovery.swift   # NWBrowser search for _notchtune._tcp
    │   ├── SSEClient.swift          # HTTP SSE long-lived connection
    │   └── ConnectionManager.swift  # discover → pair → SSE lifecycle
    ├── Views/
    │   ├── PairingView.swift        # List of Macs + pairing code entry
    │   └── SettingsView.swift       # Notification type toggles
    ├── Models/
    │   └── WatchEvent.swift         # Event data model (shared definition with the macOS side)
    └── Info.plist                   # NSLocalNetworkUsageDescription + NSBonjourServices
```

### Key Info.plist Configuration

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Open Island needs to discover your Mac on the local network to receive agent notifications.</string>
<key>NSBonjourServices</key>
<array>
    <string>_notchtune._tcp</string>
</array>
```

### Verification

- Run on the iPhone → discovers the Mac → enter the pairing code → connects successfully
- SSE events are printed to the console

---

## Step 3: iOS App — local notifications + Watch mirroring

**Goal**: turn SSE events into local notifications, automatically mirrored to the Watch.

### New Files

| File | Responsibility |
|---|---|
| `NotificationManager.swift` | Registers category/action, converts events to notifications |

### Notification Category Definitions

```swift
// PERMISSION_REQUEST: Allow + Deny buttons
// QUESTION: dynamic options (up to 4 actions)
// SESSION_COMPLETED: no buttons, purely informational
```

### Verification

- Trigger an agent permission request → iPhone notification → mirrored to Watch → see the Allow/Deny buttons

---

## Step 4: Two-way interaction

**Goal**: Watch button tap → posted back to the Mac to execute.

### Key Implementation

- The `didReceive response` callback of `UNUserNotificationCenter.delegate`
- Determine the action from `response.actionIdentifier` (ALLOW/DENY/option text)
- `ConnectionManager.postResolution(requestID:action:)` → HTTP POST

### Verification

- End-to-end: agent requests permission → Watch vibrates → tap Allow → agent continues executing

---

## Step 5: Polish

- iOS app UI: connection status page, notification history list, paired device management
- macOS settings page: Watch notifications toggle, pairing code display, paired devices
- SSE background reconnection (the connection may be dropped by the system while the app is backgrounded)
- Edge cases: token expiry, re-pairing after a Mac restart, concurrent multi-session handling

---

## Key Code Path Reference

| Feature | File | Location |
|---|---|---|
| Event dispatch entry point | `AppModel.swift` | `applyTrackedEvent()` ~L745 |
| Permission approval | `AppModel.swift` | `approveFocusedPermission()` ~L564 |
| Question answering | `AppModel.swift` | `answerFocusedQuestion()` ~L577 |
| Permission resolution execution | `BridgeServer.swift` | `resolvePendingClaudeInteraction()` ~L1638 |
| Question resolution execution | `BridgeServer.swift` | `resolvePendingClaudeQuestion()` ~L1704 |
| Session phase definition | `AgentSession.swift` | `SessionPhase` ~L51 |
| Permission request model | `AgentSession.swift` | `PermissionRequest` ~L105 |
| Question model | `AgentSession.swift` | `QuestionPrompt` ~L168 |
| Existing bridge protocol | `BridgeTransport.swift` | `BridgeEnvelope` / `BridgeCodec` |

---

## Branching Strategy

Watch notifications are an experimental feature and must not pollute `main`. Use an **integration branch** pattern:

```
main (used for releases, kept clean)
  └── feat/watch-notification (integration branch)
        ├── Step 1 PR → target feat/watch-notification
        ├── Step 2 PR → target feat/watch-notification
        ├── Step 3 PR → target feat/watch-notification
        ├── Step 4 PR → target feat/watch-notification
        ├── Step 5 PR → target feat/watch-notification
        └── once the feature is complete → one PR merges into main
```

**Rules:**
- Each Step branches off `feat/watch-notification`, and its PR also targets `feat/watch-notification`
- **Do not** target `main`, and do not merge directly into `main`
- Once the feature is complete and stable, merge `feat/watch-notification` into `main` as a whole

**Branch naming:**
- Step 1: `feat/watch-http-endpoint`
- Step 2: `feat/watch-ios-app`
- Step 3: `feat/watch-notifications`
- Step 4: `feat/watch-bidirectional`
- Step 5: `feat/watch-polish`

Recommended to start with Step 1, purely on the macOS side, verified with curl.
