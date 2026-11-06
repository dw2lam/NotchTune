import Foundation
import NotchTuneCore

/// What "Always Allow" would actually grant for a request, or `nil` when it
/// can't be offered honestly. The card button and ⌘⇧Y both go through this,
/// so the key can't do more than the label says.
struct AlwaysAllowOffer: Equatable, Sendable {
    enum Grant: Equatable, Sendable {
        /// Rule contents, directories, or a tool name.
        case scope(String)
        /// Every edit for the rest of the session (the CLI's `acceptEdits`).
        case allEdits
    }

    var grant: Grant
    var updates: [ClaudePermissionUpdate]

    var action: ApprovalAction {
        .allowWithUpdates(updates)
    }

    /// Only the Claude family applies `updatedPermissions`; anywhere else
    /// this would act as allow-once while saying "Always".
    init?(session: AgentSession) {
        guard session.tool.appliesPermissionUpdates,
              let request = session.permissionRequest else {
            return nil
        }

        let narrow = request.suggestedUpdates.filter(Self.isNarrow)
        if !narrow.isEmpty {
            updates = narrow
            grant = Self.grant(for: narrow)
            return
        }

        // The CLI suggested nothing. A whole-tool rule is what the label
        // says it is, unless the tool runs commands: then it is a blank
        // cheque for the shell, and ending plan mode has nothing to keep.
        guard let toolName = request.toolName,
              toolName != "ExitPlanMode",
              !TaskActivityClassifier.isShellTool(toolName) else {
            return nil
        }
        updates = [
            .addRules(
                destination: .session,
                rules: [ClaudePermissionRuleValue(toolName: toolName)],
                behavior: .allow
            ),
        ]
        grant = .scope(toolName)
    }

    /// Suggestions are passed through as the CLI wrote them, destination
    /// included, so this is the CLI's own "don't ask again". Anything that
    /// isn't a bounded grant is left out, however it got into the payload.
    private static func isNarrow(_ update: ClaudePermissionUpdate) -> Bool {
        switch update {
        case let .addRules(_, rules, behavior):
            behavior == .allow && !rules.isEmpty && rules.allSatisfy(isBounded)
        case let .addDirectories(_, directories):
            !directories.isEmpty
        case let .setMode(_, mode):
            mode == .acceptEdits
        case .replaceRules, .removeRules, .removeDirectories:
            false
        }
    }

    private static func isBounded(_ rule: ClaudePermissionRuleValue) -> Bool {
        guard TaskActivityClassifier.isShellTool(rule.toolName) else { return true }
        let content = rule.ruleContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !["", "*", ":*"].contains(content)
    }

    private static func grant(for updates: [ClaudePermissionUpdate]) -> Grant {
        let scopes = updates.flatMap { update -> [String] in
            switch update {
            case let .addRules(_, rules, _):
                rules.map { $0.ruleContent ?? $0.toolName }
            case let .addDirectories(_, directories):
                directories
            default:
                []
            }
        }
        return scopes.isEmpty ? .allEdits : .scope(scopes.joined(separator: ", "))
    }
}

extension AgentSession {
    var alwaysAllowOffer: AlwaysAllowOffer? {
        AlwaysAllowOffer(session: self)
    }
}
