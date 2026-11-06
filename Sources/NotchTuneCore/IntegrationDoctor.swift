import Foundation

/// One agent's answer to "is NotchTune actually hearing from it?"
public struct IntegrationDiagnosis: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case working
        case noEventsYet
        case needsRepair
        case notInstalled
    }

    /// What's wrong, in the order worth fixing. Copy lives in the app.
    public enum Finding: Equatable, Sendable {
        case hooksMissing
        case configMalformed(path: String)
        case configUnreadable(path: String)
        case binaryMissing
        case binaryNotExecutable(path: String)
        case staleCommand(path: String)
        case pluginMissing
        case pluginOutdated
        case claudeHooksDisabled
        case claudeManagedHooksOnly
        case codexHooksOff
        case codexHooksNeedReview(count: Int)
    }

    public enum Fix: Equatable, Sendable {
        /// Installing again fixes it.
        case reinstall
        /// Only the user can: their config, or a decision in the agent.
        case openConfig(URL)
    }

    public var agent: AgentIdentifier
    public var displayName: String
    public var status: Status
    public var findings: [Finding]
    public var fix: Fix?
    public var lastEventAt: Date?
    public var droppedEvents: Int
    public var lastDroppedEvent: String?
    public var toolPresent: Bool

    public var id: AgentIdentifier { agent }
}

public enum IntegrationDoctor {
    public struct Input: Sendable {
        public var descriptor: HookAgentDescriptor
        public var intent: AgentHookIntent
        public var hooksPresent: Bool
        public var toolPresent: Bool
        public var health: HookHealthReport
        public var lastEventAt: Date?
        public var drops: HookDropLog.Entry?
        public var claudePolicy: ClaudeHookPolicy?
        public var codexHooksDisabledInConfig: Bool
        public var codexTrust: CodexHookTrust?

        public init(
            descriptor: HookAgentDescriptor,
            intent: AgentHookIntent,
            hooksPresent: Bool,
            toolPresent: Bool,
            health: HookHealthReport,
            lastEventAt: Date? = nil,
            drops: HookDropLog.Entry? = nil,
            claudePolicy: ClaudeHookPolicy? = nil,
            codexHooksDisabledInConfig: Bool = false,
            codexTrust: CodexHookTrust? = nil
        ) {
            self.descriptor = descriptor
            self.intent = intent
            self.hooksPresent = hooksPresent
            self.toolPresent = toolPresent
            self.health = health
            self.lastEventAt = lastEventAt
            self.drops = drops
            self.claudePolicy = claudePolicy
            self.codexHooksDisabledInConfig = codexHooksDisabledInConfig
            self.codexTrust = codexTrust
        }
    }

    public static func diagnose(_ input: Input) -> IntegrationDiagnosis {
        var findings: [IntegrationDiagnosis.Finding] = []

        if input.hooksPresent || input.intent == .installed {
            findings += input.health.errors.compactMap(finding(for:))

            if !input.hooksPresent, !findings.contains(.pluginMissing) {
                findings.insert(.hooksMissing, at: 0)
            }
        }

        if input.hooksPresent {
            if input.claudePolicy?.allowManagedHooksOnly == true {
                findings.append(.claudeManagedHooksOnly)
            }
            if input.claudePolicy?.disableAllHooks == true {
                findings.append(.claudeHooksDisabled)
            }
            if input.codexHooksDisabledInConfig {
                findings.append(.codexHooksOff)
            }
            if case let .needsReview(count) = input.codexTrust {
                findings.append(.codexHooksNeedReview(count: count))
            }
        }

        let status: IntegrationDiagnosis.Status
        if !findings.isEmpty {
            status = .needsRepair
        } else if !input.hooksPresent {
            status = .notInstalled
        } else {
            status = input.lastEventAt == nil ? .noEventsYet : .working
        }

        return IntegrationDiagnosis(
            agent: input.descriptor.agent,
            displayName: input.descriptor.displayName,
            status: status,
            findings: findings,
            fix: fix(for: findings, descriptor: input.descriptor),
            lastEventAt: input.lastEventAt,
            droppedEvents: input.drops?.count ?? 0,
            lastDroppedEvent: input.drops?.lastEvent,
            toolPresent: input.toolPresent
        )
    }

    private static func finding(for issue: HookHealthReport.Issue) -> IntegrationDiagnosis.Finding? {
        switch issue {
        case .binaryNotFound:
            .binaryMissing
        case let .binaryNotExecutable(path):
            .binaryNotExecutable(path: path)
        case let .configMalformedJSON(path):
            .configMalformed(path: path)
        case let .configUnreadable(path):
            .configUnreadable(path: path)
        case let .staleCommandPath(recorded, _):
            .staleCommand(path: recorded)
        case .pluginMissing:
            .pluginMissing
        case .pluginOutdated:
            .pluginOutdated
        // Reinstalling restores a manifest, but hooks run without one.
        case .manifestMissing, .otherHooksDetected:
            nil
        }
    }

    /// Reinstalling can't fix a file we refuse to touch or a choice that isn't
    /// ours, so those point at the file instead.
    private static func fix(
        for findings: [IntegrationDiagnosis.Finding],
        descriptor: HookAgentDescriptor
    ) -> IntegrationDiagnosis.Fix? {
        guard let first = findings.first else {
            return nil
        }

        switch first {
        case .configMalformed, .configUnreadable, .claudeHooksDisabled, .claudeManagedHooksOnly, .codexHooksOff:
            return .openConfig(descriptor.configURL)
        case .codexHooksNeedReview:
            return nil
        case .hooksMissing, .binaryMissing, .binaryNotExecutable, .staleCommand, .pluginMissing, .pluginOutdated:
            return .reinstall
        }
    }
}
