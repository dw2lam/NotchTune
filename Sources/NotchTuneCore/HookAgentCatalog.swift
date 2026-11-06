import Foundation

/// Where one agent keeps its hooks, and how to tell it's on this Mac.
public struct HookAgentDescriptor: Equatable, Sendable {
    public var agent: AgentIdentifier
    public var displayName: String
    /// The hook CLI's `--source`; `nil` for OpenCode, whose plugin talks to
    /// the bridge itself.
    public var hookSource: String?
    public var directory: URL
    public var configURL: URL
    public var executableNames: [String]
    public var applicationNames: [String]
    /// A path only this tool creates. Defaults to `directory`.
    public var marker: URL

    public init(
        agent: AgentIdentifier,
        displayName: String,
        hookSource: String?,
        directory: URL,
        configURL: URL,
        executableNames: [String],
        applicationNames: [String] = [],
        marker: URL? = nil
    ) {
        self.agent = agent
        self.displayName = displayName
        self.hookSource = hookSource
        self.directory = directory
        self.configURL = configURL
        self.executableNames = executableNames
        self.applicationNames = applicationNames
        self.marker = marker ?? directory
    }
}

public enum HookAgentCatalog {
    public static func descriptors(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        claudeDirectory: URL = ClaudeConfigDirectory.resolved(),
        kimiDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> [HookAgentDescriptor] {
        let kimi = kimiDirectory ?? KimiHookInstallationManager.resolvedDirectory(home: home, fileManager: fileManager)
        let gemini = home.appendingPathComponent(".gemini", isDirectory: true)
        let openCode = home.appendingPathComponent(".config/opencode", isDirectory: true)
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        let cursor = home.appendingPathComponent(".cursor", isDirectory: true)

        func claudeFork(_ agent: AgentIdentifier, _ name: String, _ folder: String, source: String, executable: String) -> HookAgentDescriptor {
            let directory = home.appendingPathComponent(folder, isDirectory: true)
            return HookAgentDescriptor(
                agent: agent,
                displayName: name,
                hookSource: source,
                directory: directory,
                configURL: directory.appendingPathComponent("settings.json"),
                executableNames: [executable]
            )
        }

        return [
            HookAgentDescriptor(
                agent: .claudeCode,
                displayName: "Claude Code",
                hookSource: "claude",
                directory: claudeDirectory,
                configURL: claudeDirectory.appendingPathComponent("settings.json"),
                executableNames: ["claude"]
            ),
            HookAgentDescriptor(
                agent: .codex,
                displayName: "Codex",
                hookSource: "codex",
                directory: codex,
                configURL: codex.appendingPathComponent("hooks.json"),
                executableNames: ["codex"],
                applicationNames: ["Codex.app"]
            ),
            HookAgentDescriptor(
                agent: .openCode,
                displayName: "OpenCode",
                hookSource: nil,
                directory: openCode,
                configURL: openCode
                    .appendingPathComponent("plugins", isDirectory: true)
                    .appendingPathComponent(OpenCodePluginInstallationManager.pluginFileName),
                executableNames: ["opencode"]
            ),
            claudeFork(.qoder, "Qoder", ".qoder", source: "qoder", executable: "qodercli"),
            claudeFork(.qwenCode, "Qwen Code", ".qwen", source: "qwen", executable: "qwen"),
            claudeFork(.factory, "Factory", ".factory", source: "factory", executable: "droid"),
            claudeFork(.codebuddy, "CodeBuddy", ".codebuddy", source: "codebuddy", executable: "codebuddy"),
            HookAgentDescriptor(
                agent: .cursor,
                displayName: "Cursor",
                hookSource: "cursor",
                directory: cursor,
                configURL: cursor.appendingPathComponent("hooks.json"),
                executableNames: ["cursor-agent", "cursor"],
                applicationNames: ["Cursor.app"]
            ),
            HookAgentDescriptor(
                agent: .gemini,
                displayName: "Gemini CLI",
                hookSource: "gemini",
                directory: gemini,
                configURL: gemini.appendingPathComponent("settings.json"),
                executableNames: ["gemini"],
                // ~/.gemini alone proves nothing: Antigravity shares it.
                marker: gemini.appendingPathComponent("oauth_creds.json")
            ),
            HookAgentDescriptor(
                agent: .antigravity,
                displayName: "Antigravity",
                hookSource: "antigravity",
                directory: gemini.appendingPathComponent("config", isDirectory: true),
                configURL: gemini.appendingPathComponent("config/hooks.json"),
                executableNames: ["agy"],
                applicationNames: ["Antigravity.app"],
                marker: gemini.appendingPathComponent("antigravity", isDirectory: true)
            ),
            HookAgentDescriptor(
                agent: .kimi,
                displayName: "Kimi CLI",
                hookSource: "kimi",
                directory: kimi,
                configURL: kimi.appendingPathComponent("config.toml"),
                executableNames: ["kimi"]
            ),
        ]
    }

    /// Stat calls only. GUI apps don't inherit a shell `PATH`, so this looks
    /// where the installers of these tools put them.
    public static func isToolPresent(
        _ descriptor: HookAgentDescriptor,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Bool {
        if fileManager.fileExists(atPath: descriptor.marker.path) {
            return true
        }

        let binDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent("bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".opencode/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
        ]
        for directory in binDirectories {
            for name in descriptor.executableNames
            where fileManager.isExecutableFile(atPath: "\(directory)/\(name)") {
                return true
            }
        }

        let appDirectories = ["/Applications", home.appendingPathComponent("Applications").path]
        for directory in appDirectories {
            for name in descriptor.applicationNames
            where fileManager.fileExists(atPath: "\(directory)/\(name)") {
                return true
            }
        }

        return false
    }
}
