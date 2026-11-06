import AppKit
import Foundation
import os

/// The terminal state one process-monitor "round" works from.
///
/// The attachment probe and the jump-target resolver both need Ghostty's and
/// Terminal.app's tab lists. They used to run the identical AppleScript twice
/// per tick (probe with a 1 s budget, resolver with 3 s); a round queries each
/// running terminal once with the resolver's budget and hands both consumers
/// the same answer. The probe still treats an answer that took longer than its
/// own budget as unavailable, exactly as its own timed-out query would have.
///
/// The resolver's other sources (tmux, WezTerm/Kaku CLIs) are fetched lazily
/// the first time the resolver asks and then kept for the rest of the round,
/// so a round can be reused across monitor ticks without re-querying anything.
final class TerminalSnapshotRound: Sendable {
    enum Fetch<Value: Sendable>: Sendable {
        case notRunning
        case failed
        /// Not asked, because it has kept failing (`TerminalQueryBackoff`).
        /// To its consumers this is `failed`: no answer, the app is running.
        case backingOff
        case fetched(Value, elapsed: TimeInterval)

        var isAppRunning: Bool {
            if case .notRunning = self {
                return false
            }

            return true
        }

        var isFailure: Bool {
            switch self {
            case .failed, .backingOff:
                return true
            case .notRunning, .fetched:
                return false
            }
        }

        var isBackingOff: Bool {
            if case .backingOff = self {
                return true
            }

            return false
        }
    }

    typealias GhosttySnapshot = TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot
    typealias TerminalTabSnapshot = TerminalSessionAttachmentProbe.TerminalTabSnapshot
    typealias SnapshotAvailability = TerminalSessionAttachmentProbe.SnapshotAvailability

    struct RunningApps: Equatable, Sendable {
        var ghostty: Bool
        var terminal: Bool
    }

    let createdAt: ContinuousClock.Instant
    let ghostty: Fetch<[GhosttySnapshot]>
    let terminal: Fetch<[TerminalTabSnapshot]>

    private struct LazySources: Sendable {
        var tmux: [TerminalJumpTargetResolver.TmuxPaneSnapshot]??
        var weztermFamily: [String: [TerminalJumpTargetResolver.WeztermFamilySnapshot]?] = [:]
    }

    private let lazySources = OSAllocatedUnfairLock(initialState: LazySources())

    init(
        createdAt: ContinuousClock.Instant = .now,
        ghostty: Fetch<[GhosttySnapshot]>,
        terminal: Fetch<[TerminalTabSnapshot]>
    ) {
        self.createdAt = createdAt
        self.ghostty = ghostty
        self.terminal = terminal
    }

    /// Queries every running terminal once (apps that are not running are
    /// never sent AppleScript, nor are those `held` back for now).
    static func fetch(
        using probe: TerminalSessionAttachmentProbe,
        held: TerminalQueryBackoff.Held = .init()
    ) -> TerminalSnapshotRound {
        let timeout = TerminalJumpTargetResolver.appleScriptTimeout
        let running = currentRunningApps()
        return TerminalSnapshotRound(
            ghostty: held.ghostty && running.ghostty ? .backingOff : probe.fetchGhosttySnapshots(timeout: timeout),
            terminal: held.terminal && running.terminal ? .backingOff : probe.fetchTerminalSnapshots(timeout: timeout)
        )
    }

    var runningApps: RunningApps {
        RunningApps(ghostty: ghostty.isAppRunning, terminal: terminal.isAppRunning)
    }

    /// Cheap check (no AppleScript) used to notice a terminal launching or
    /// quitting while a round is being reused.
    static func currentRunningApps() -> RunningApps {
        RunningApps(
            ghostty: !NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty").isEmpty,
            terminal: !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty
        )
    }

    /// A round whose probe-facing answers include a failure or a too-slow
    /// reply is not reused: the next tick queries again, as every tick did.
    /// A terminal being held back counts as settled, or one denied terminal
    /// would keep a healthy one re-queried on every tick.
    var isReusable: Bool {
        (ghostty.isBackingOff || ghosttyAvailability.isAuthoritative)
            && (terminal.isBackingOff || terminalAvailability.isAuthoritative)
    }

    /// Same tab lists as `other` (ignoring query timing).
    func hasSameTerminalState(as other: TerminalSnapshotRound) -> Bool {
        Self.payload(ghostty) == Self.payload(other.ghostty)
            && Self.payload(terminal) == Self.payload(other.terminal)
            && runningApps == other.runningApps
    }

    private static func payload<Value: Equatable>(_ fetch: Fetch<[Value]>) -> [Value]? {
        if case let .fetched(value, _) = fetch {
            return value
        }

        return fetch.isAppRunning ? nil : []
    }

    // MARK: - Attachment probe view (1 s budget)

    var ghosttyAvailability: SnapshotAvailability<GhosttySnapshot> {
        Self.probeAvailability(ghostty)
    }

    var terminalAvailability: SnapshotAvailability<TerminalTabSnapshot> {
        Self.probeAvailability(terminal)
    }

    private static func probeAvailability<Snapshot>(_ fetch: Fetch<[Snapshot]>) -> SnapshotAvailability<Snapshot> {
        switch fetch {
        case .notRunning:
            return .available([], appIsRunning: false)
        case .failed, .backingOff:
            return .unavailable(appIsRunning: true)
        case let .fetched(snapshots, elapsed):
            guard elapsed <= TerminalSessionAttachmentProbe.appleScriptTimeout else {
                return .unavailable(appIsRunning: true)
            }

            return .available(snapshots, appIsRunning: true)
        }
    }

    // MARK: - Jump-target resolver view (3 s budget)

    /// Resolver sources backed by this round. `isTmuxRunning == false` (no
    /// tmux process exists) answers tmux as unavailable without spawning it —
    /// `tmux list-panes` would fail with "no server running" anyway.
    /// `live` supplies tmux / WezTerm-family listings on first use.
    func resolverSources(
        live: TerminalJumpTargetResolver.SnapshotSources,
        isTmuxRunning: Bool?
    ) -> TerminalJumpTargetResolver.SnapshotSources {
        let ghostty = ghostty
        let terminal = terminal
        let lazySources = lazySources

        return TerminalJumpTargetResolver.SnapshotSources(
            ghostty: {
                Self.resolverSnapshots(ghostty).map { snapshots in
                    snapshots.map {
                        TerminalJumpTargetResolver.GhosttyTerminalSnapshot(
                            sessionID: $0.sessionID,
                            workingDirectory: $0.workingDirectory,
                            title: $0.title
                        )
                    }
                }
            },
            terminal: {
                Self.resolverSnapshots(terminal).map { snapshots in
                    snapshots.map {
                        TerminalJumpTargetResolver.TerminalTabSnapshot(tty: $0.tty, customTitle: $0.customTitle)
                    }
                }
            },
            tmux: {
                if isTmuxRunning == false {
                    return nil
                }

                if let cached = lazySources.withLock({ $0.tmux }) {
                    return cached
                }

                let fetched = live.tmux()
                lazySources.withLock { $0.tmux = .some(fetched) }
                return fetched
            },
            weztermFamily: { bundleIdentifier in
                if let cached = lazySources.withLock({ $0.weztermFamily[bundleIdentifier] }) {
                    return cached
                }

                let fetched = live.weztermFamily(bundleIdentifier)
                lazySources.withLock { $0.weztermFamily[bundleIdentifier] = .some(fetched) }
                return fetched
            }
        )
    }

    private static func resolverSnapshots<Snapshot>(_ fetch: Fetch<[Snapshot]>) -> [Snapshot]? {
        switch fetch {
        case .notRunning:
            return []
        case .failed, .backingOff:
            return nil
        case let .fetched(snapshots, _):
            return snapshots
        }
    }
}

/// Stops asking a terminal that keeps refusing. With Automation denied every
/// query fails the same way, and failed rounds aren't reused, so the monitor
/// ran osascript every 2–5 s for as long as the app was open. Each terminal
/// backs off on its own: Ghostty being denied says nothing about Terminal.app.
struct TerminalQueryBackoff: Sendable {
    struct Held: Equatable, Sendable {
        var ghostty = false
        var terminal = false
    }

    private struct Track: Sendable {
        var failures = 0
        var nextAttempt: ContinuousClock.Instant?

        func isHeld(at now: ContinuousClock.Instant) -> Bool {
            nextAttempt.map { now < $0 } ?? false
        }

        mutating func record<Value>(_ fetch: TerminalSnapshotRound.Fetch<Value>, at now: ContinuousClock.Instant) {
            switch fetch {
            case .backingOff:
                break
            case .failed:
                failures += 1
                nextAttempt = TerminalQueryBackoff.delay(afterFailures: failures).map { now + $0 }
            case .notRunning, .fetched:
                self = Track()
            }
        }
    }

    /// One bad answer is a terminal being busy, not a refusal.
    private static let toleratedFailures = 3
    private static let firstDelay: Duration = .seconds(15)
    /// Also how long a grant in System Settings can take to be noticed.
    private static let maxDelay: Duration = .seconds(60)

    private var ghostty = Track()
    private var terminal = Track()

    /// How long to hold off after `failures` in a row; `nil` to keep asking.
    static func delay(afterFailures failures: Int) -> Duration? {
        guard failures >= toleratedFailures else { return nil }
        let doublings = min(failures - toleratedFailures, 8)
        return min(firstDelay * (1 << doublings), maxDelay)
    }

    func held(at now: ContinuousClock.Instant = .now) -> Held {
        Held(ghostty: ghostty.isHeld(at: now), terminal: terminal.isHeld(at: now))
    }

    mutating func record(_ round: TerminalSnapshotRound, at now: ContinuousClock.Instant = .now) {
        ghostty.record(round.ghostty, at: now)
        terminal.record(round.terminal, at: now)
    }
}
