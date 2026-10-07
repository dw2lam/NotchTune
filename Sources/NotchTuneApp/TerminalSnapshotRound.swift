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
        case fetched(Value, elapsed: TimeInterval)

        var isAppRunning: Bool {
            if case .notRunning = self {
                return false
            }

            return true
        }

        var isFailure: Bool {
            if case .failed = self {
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
    /// never sent AppleScript).
    static func fetch(using probe: TerminalSessionAttachmentProbe) -> TerminalSnapshotRound {
        let timeout = TerminalJumpTargetResolver.appleScriptTimeout
        return TerminalSnapshotRound(
            ghostty: probe.fetchGhosttySnapshots(timeout: timeout),
            terminal: probe.fetchTerminalSnapshots(timeout: timeout)
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
    var isReusable: Bool {
        ghosttyAvailability.isAuthoritative && terminalAvailability.isAuthoritative
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
        case .failed:
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
        case .failed:
            return nil
        case let .fetched(snapshots, _):
            return snapshots
        }
    }
}
