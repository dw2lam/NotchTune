import Foundation

/// Tri-state record of whether the user wants a given agent's hooks installed.
///
/// `untouched` is the default for a never-seen agent. Once the user makes a
/// decision — in onboarding or settings — the value becomes either
/// `installed` or `uninstalled`. The startup flow must honour `uninstalled`
/// and never silently reinstall.
public enum AgentHookIntent: String, Codable, Sendable, CaseIterable {
    case untouched
    case installed
    case uninstalled
}

/// Canonical identifier for every agent whose hooks NotchTune manages.
///
/// Raw values are stable on-disk keys (used in UserDefaults); do not rename
/// existing cases without a migration.
public enum AgentIdentifier: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case cursor
    case qoder
    case qwenCode
    case factory
    case codebuddy
    case openCode
    case gemini
    case kimi
    case antigravity
    case claudeUsageBridge
}

public extension AgentIdentifier {
    /// The agent behind a hook CLI `--source` value.
    init?(hookSource: String) {
        switch hookSource {
        case "claude": self = .claudeCode
        case "codex": self = .codex
        case "cursor": self = .cursor
        case "qoder": self = .qoder
        case "qwen": self = .qwenCode
        case "factory", "droid": self = .factory
        case "codebuddy": self = .codebuddy
        case "opencode": self = .openCode
        case "gemini": self = .gemini
        case "kimi": self = .kimi
        case "antigravity": self = .antigravity
        default: return nil
        }
    }

    /// Every agent with hooks of its own; the usage bridge rides on Claude.
    static var hookAgents: [AgentIdentifier] {
        allCases.filter { $0 != .claudeUsageBridge }
    }
}
