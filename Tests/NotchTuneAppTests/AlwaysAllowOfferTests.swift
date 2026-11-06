import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

/// "Always Allow" must grant exactly what the button says, and only appear
/// where the agent acts on it.
struct AlwaysAllowOfferTests {
    private func session(
        tool: AgentTool = .claudeCode,
        toolName: String? = "Bash",
        suggestions: [ClaudePermissionUpdate] = []
    ) -> AgentSession {
        AgentSession(
            id: "s",
            title: "s",
            tool: tool,
            phase: .waitingForApproval,
            summary: "",
            updatedAt: Date(timeIntervalSince1970: 0),
            permissionRequest: PermissionRequest(
                title: "Allow",
                summary: "",
                affectedPath: "",
                toolName: toolName,
                suggestedUpdates: suggestions
            )
        )
    }

    private func rule(
        _ content: String?,
        tool: String = "Bash",
        destination: ClaudePermissionUpdateDestination = .localSettings,
        behavior: ClaudePermissionBehavior = .allow
    ) -> ClaudePermissionUpdate {
        .addRules(
            destination: destination,
            rules: [ClaudePermissionRuleValue(toolName: tool, ruleContent: content)],
            behavior: behavior
        )
    }

    @Test
    func theCLIsNarrowRuleIsUsedAndNamed() throws {
        let suggestion = rule("git add:*")
        let offer = try #require(session(suggestions: [suggestion]).alwaysAllowOffer)

        #expect(offer.updates == [suggestion])
        #expect(offer.grant == .scope("git add:*"))
    }

    @Test
    func aModeNeverRidesAlongUnderAnotherLabel() throws {
        let offer = try #require(AlwaysAllowOffer(session: session(
            toolName: "Edit",
            suggestions: [
                .addDirectories(destination: .session, directories: ["/other/repo"]),
                .setMode(destination: .session, mode: .acceptEdits),
            ]
        )))
        #expect(offer.grant == .scope("/other/repo"))
        #expect(offer.updates == [.addDirectories(destination: .session, directories: ["/other/repo"])])
    }

    @Test
    func bashWithNoNarrowRuleIsNotOffered() {
        #expect(session().alwaysAllowOffer == nil)
        #expect(session(suggestions: [rule(nil)]).alwaysAllowOffer == nil)
        #expect(session(suggestions: [rule("")]).alwaysAllowOffer == nil)
        #expect(session(suggestions: [rule("*")]).alwaysAllowOffer == nil)
        #expect(session(suggestions: [rule(":*")]).alwaysAllowOffer == nil)
    }

    @Test
    func otherAgentsCommandToolsAreNotOfferedABlanketRule() {
        for name in ["Shell", "run_shell_command", "Execute", "execute_command", "PowerShell"] {
            #expect(session(tool: .kimiCLI, toolName: name).alwaysAllowOffer == nil)
        }
    }

    @Test
    func aNonCommandToolFallsBackToASessionRuleForThatTool() throws {
        let offer = try #require(session(toolName: "WebFetch").alwaysAllowOffer)

        #expect(offer.grant == .scope("WebFetch"))
        #expect(offer.updates == [
            .addRules(
                destination: .session,
                rules: [ClaudePermissionRuleValue(toolName: "WebFetch")],
                behavior: .allow
            ),
        ])
    }

    @Test
    func onlyTheClaudeFamilyIsOffered() {
        let suggestion = rule("git add:*")
        for tool in AgentTool.allCases {
            let offered = session(tool: tool, suggestions: [suggestion]).alwaysAllowOffer != nil
            #expect(offered == tool.appliesPermissionUpdates, "\(tool)")
        }
        #expect(session(tool: .codex, toolName: "WebFetch").alwaysAllowOffer == nil)
        #expect(session(tool: .openCode, toolName: "WebFetch").alwaysAllowOffer == nil)
        #expect(session(tool: .cursor, toolName: "WebFetch").alwaysAllowOffer == nil)
    }

    @Test
    func unboundedOrSubtractiveSuggestionsAreDropped() throws {
        let bypass = ClaudePermissionUpdate.setMode(destination: .session, mode: .bypassPermissions)
        let deny = rule("rm:*", behavior: .deny)
        let replace = ClaudePermissionUpdate.replaceRules(
            destination: .session,
            rules: [ClaudePermissionRuleValue(toolName: "Bash", ruleContent: "git:*")],
            behavior: .allow
        )
        #expect(session(suggestions: [bypass, deny, replace]).alwaysAllowOffer == nil)

        let good = rule("git status:*")
        let offer = try #require(session(suggestions: [bypass, good]).alwaysAllowOffer)
        #expect(offer.updates == [good])
    }

    @Test
    func acceptEditsSaysSo() throws {
        let mode = ClaudePermissionUpdate.setMode(destination: .session, mode: .acceptEdits)
        let offer = try #require(session(toolName: "Edit", suggestions: [mode]).alwaysAllowOffer)

        #expect(offer.grant == .allEdits)
        #expect(offer.updates == [mode])
    }

    @Test
    func everyRuleAndDirectoryIsNamed() throws {
        let offer = try #require(session(suggestions: [
            rule("git add:*"),
            rule("git commit:*"),
            .addDirectories(destination: .session, directories: ["/tmp/out"]),
        ]).alwaysAllowOffer)

        #expect(offer.grant == .scope("git add:*, git commit:*, /tmp/out"))
    }

    @Test
    func endingPlanModeHasNothingToKeep() {
        #expect(session(toolName: "ExitPlanMode").alwaysAllowOffer == nil)
    }

    @Test
    func aRequestWithoutAToolIsNotOffered() {
        #expect(session(toolName: nil).alwaysAllowOffer == nil)
    }
}
