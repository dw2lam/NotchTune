import Foundation

/// Automatic repair only ever restores what the user asked for. An agent they
/// never set up, or took out, keeps its config exactly as they left it, even
/// when a health check has something to say about it.
public enum HookRepairPolicy {
    public static func agentsToRepair(
        reports: [AgentIdentifier: HookHealthReport],
        intent: (AgentIdentifier) -> AgentHookIntent,
        hooksBinaryAvailable: Bool
    ) -> [AgentIdentifier] {
        AgentIdentifier.hookAgents.filter { agent in
            guard intent(agent) == .installed,
                  let report = reports[agent],
                  !report.repairableIssues.isEmpty else {
                return false
            }

            // OpenCode's plugin carries its own transport.
            return agent == .openCode || hooksBinaryAvailable
        }
    }
}
