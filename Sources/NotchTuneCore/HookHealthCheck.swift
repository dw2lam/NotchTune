import Foundation

/// Structured diagnostic result for a single hook integration.
public struct HookHealthReport: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        /// A real problem that may prevent hooks from working.
        case error
        /// Informational notice — hooks still work fine.
        case info
    }

    public enum Issue: Equatable, Sendable, CustomStringConvertible {
        /// The hooks binary is not found at any candidate location.
        case binaryNotFound
        /// The hooks binary exists but is not executable.
        case binaryNotExecutable(path: String)
        /// The config file (settings.json / hooks.json) contains invalid JSON.
        case configMalformedJSON(path: String)
        /// The config file exists but couldn't be read at all.
        case configUnreadable(path: String)
        /// The command path recorded in the config doesn't point to an existing binary.
        case staleCommandPath(recorded: String, configPath: String)
        /// Other hooks detected alongside NotchTune hooks (informational).
        case otherHooksDetected(names: [String])
        /// The manifest file is missing even though hooks appear installed.
        case manifestMissing(expectedPath: String)
        /// The OpenCode plugin file is missing even though it should be installed.
        case pluginMissing(expectedPath: String)
        /// The installed OpenCode plugin predates the current plugin API.
        case pluginOutdated(path: String)

        public var description: String {
            switch self {
            case .binaryNotFound:
                "Hook binary not found at any candidate location."
            case .binaryNotExecutable(let path):
                "Hook binary exists but is not executable: \(path)"
            case .configMalformedJSON(let path):
                "Config file is not valid JSON: \(path)"
            case .configUnreadable(let path):
                "Config file could not be read: \(path)"
            case .staleCommandPath(let recorded, let configPath):
                "Command path in \(configPath) points to missing binary: \(recorded)"
            case .otherHooksDetected(let names):
                "Other hooks coexist: \(names.joined(separator: ", "))"
            case .manifestMissing(let expectedPath):
                "Installation manifest missing: \(expectedPath)"
            case .pluginMissing(let expectedPath):
                "OpenCode plugin file is missing: \(expectedPath)"
            case .pluginOutdated(let path):
                "OpenCode plugin is out of date: \(path)"
            }
        }

        public var severity: Severity {
            switch self {
            case .otherHooksDetected:
                .info
            default:
                .error
            }
        }

        public var isAutoRepairable: Bool {
            switch self {
            case .staleCommandPath, .binaryNotExecutable, .manifestMissing, .pluginMissing, .pluginOutdated:
                true
            default:
                false
            }
        }
    }

    public var agent: String  // an AgentIdentifier raw value, or the legacy "claude" / "codex" / "opencode"
    public var issues: [Issue]
    public var binaryPath: String?
    public var configPath: String?

    /// True when there are no errors (info-level notices are fine).
    public var isHealthy: Bool { errors.isEmpty }

    /// Only error-severity issues.
    public var errors: [Issue] {
        issues.filter { $0.severity == .error }
    }

    /// Only info-severity notices.
    public var notices: [Issue] {
        issues.filter { $0.severity == .info }
    }

    /// Issues that can be fixed by re-running install.
    public var repairableIssues: [Issue] {
        issues.filter(\.isAutoRepairable)
    }

    public init(agent: String, issues: [Issue] = [], binaryPath: String? = nil, configPath: String? = nil) {
        self.agent = agent
        self.issues = issues
        self.binaryPath = binaryPath
        self.configPath = configPath
    }
}

/// Performs deep health checks on hook installations, beyond the simple "managed hooks present" check.
public enum HookHealthCheck {
    /// Check Claude Code hook health.
    public static func checkClaude(
        claudeDirectory: URL = ClaudeConfigDirectory.resolved(),
        hooksBinaryURL: URL? = nil,
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) -> HookHealthReport {
        var issues: [HookHealthReport.Issue] = []
        let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
        let manifestURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.fileName)

        // 1. Check binary
        let resolvedBinaryPath = resolveBinaryPath(
            explicit: hooksBinaryURL,
            managed: managedHooksBinaryURL,
            fileManager: fileManager
        )

        if let path = resolvedBinaryPath {
            if !fileManager.isExecutableFile(atPath: path) {
                issues.append(.binaryNotExecutable(path: path))
            }
        } else {
            issues.append(.binaryNotFound)
        }

        // 2. Check config file
        let settingsPath = settingsURL.path
        if fileManager.fileExists(atPath: settingsPath) {
            if let data = try? Data(contentsOf: settingsURL) {
                // Check JSON validity
                if (try? JSONSerialization.jsonObject(with: data)) == nil {
                    issues.append(.configMalformedJSON(path: settingsPath))
                } else {
                    // Check command paths in hooks
                    let staleCommands = findStaleCommandPaths(
                        in: data,
                        fileManager: fileManager
                    )
                    for cmd in staleCommands {
                        issues.append(.staleCommandPath(recorded: cmd, configPath: settingsPath))
                    }

                    // Check for other hooks (informational)
                    var otherNames = findThirdPartyHookNames(in: data, agent: "claude")
                    if containsClaudeIslandHook(in: data) {
                        otherNames.append("claude-island")
                    }
                    if !otherNames.isEmpty {
                        issues.append(.otherHooksDetected(names: otherNames.sorted()))
                    }
                }
            } else {
                issues.append(.configUnreadable(path: settingsPath))
            }
        }

        // 3. Check manifest
        if fileManager.fileExists(atPath: settingsPath),
           hasNotchTuneHooks(in: settingsURL, fileManager: fileManager) {
            let legacyManifestURL = claudeDirectory.appendingPathComponent(ClaudeHookInstallerManifest.legacyFileName)
            if !fileManager.fileExists(atPath: manifestURL.path) && !fileManager.fileExists(atPath: legacyManifestURL.path) {
                issues.append(.manifestMissing(expectedPath: manifestURL.path))
            }
        }

        return HookHealthReport(
            agent: "claude",
            issues: issues,
            binaryPath: resolvedBinaryPath,
            configPath: settingsPath
        )
    }

    /// Check Codex hook health.
    public static func checkCodex(
        codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true),
        hooksBinaryURL: URL? = nil,
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) -> HookHealthReport {
        var issues: [HookHealthReport.Issue] = []
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let manifestURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName)

        // 1. Check binary
        let resolvedBinaryPath = resolveBinaryPath(
            explicit: hooksBinaryURL,
            managed: managedHooksBinaryURL,
            fileManager: fileManager
        )

        if let path = resolvedBinaryPath {
            if !fileManager.isExecutableFile(atPath: path) {
                issues.append(.binaryNotExecutable(path: path))
            }
        } else {
            issues.append(.binaryNotFound)
        }

        // 2. Check config file
        let hooksPath = hooksURL.path
        if fileManager.fileExists(atPath: hooksPath) {
            if let data = try? Data(contentsOf: hooksURL) {
                if (try? JSONSerialization.jsonObject(with: data)) == nil {
                    issues.append(.configMalformedJSON(path: hooksPath))
                } else {
                    let staleCommands = findStaleCommandPaths(in: data, fileManager: fileManager)
                    for cmd in staleCommands {
                        issues.append(.staleCommandPath(recorded: cmd, configPath: hooksPath))
                    }

                    let otherNames = findThirdPartyHookNames(in: data, agent: "codex")
                    if !otherNames.isEmpty {
                        issues.append(.otherHooksDetected(names: otherNames.sorted()))
                    }
                }
            } else {
                issues.append(.configUnreadable(path: hooksPath))
            }
        }

        // 3. Check manifest
        if fileManager.fileExists(atPath: hooksPath),
           hasNotchTuneHooks(in: hooksURL, fileManager: fileManager) {
            let legacyManifestURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.legacyFileName)
            if !fileManager.fileExists(atPath: manifestURL.path) && !fileManager.fileExists(atPath: legacyManifestURL.path) {
                issues.append(.manifestMissing(expectedPath: manifestURL.path))
            }
        }

        return HookHealthReport(
            agent: "codex",
            issues: issues,
            binaryPath: resolvedBinaryPath,
            configPath: hooksPath
        )
    }

    /// Check OpenCode plugin health.
    public static func checkOpenCode(
        opencodeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/opencode", isDirectory: true),
        fileManager: FileManager = .default
    ) -> HookHealthReport {
        var issues: [HookHealthReport.Issue] = []
        let pluginsDir = opencodeDirectory.appendingPathComponent("plugins", isDirectory: true)
        let pluginFileURL = pluginsDir.appendingPathComponent("open-island.js")

        if !fileManager.fileExists(atPath: pluginFileURL.path) {
            // Only report as an issue if the plugins directory itself exists,
            // implying OpenCode is likely installed and intended to be used.
            if fileManager.fileExists(atPath: opencodeDirectory.path) {
                issues.append(.pluginMissing(expectedPath: pluginFileURL.path))
            }
        } else if OpenCodePluginInstallationManager.pluginRevision(in: try? Data(contentsOf: pluginFileURL))
                    < OpenCodePluginInstallationManager.currentPluginRevision {
            issues.append(.pluginOutdated(path: pluginFileURL.path))
        }

        return HookHealthReport(
            agent: "opencode",
            issues: issues,
            binaryPath: nil,
            configPath: pluginFileURL.path
        )
    }

    /// Health of any agent, from its catalog entry.
    public static func check(
        _ descriptor: HookAgentDescriptor,
        hooksBinaryURL: URL? = nil,
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) -> HookHealthReport {
        var report: HookHealthReport
        switch descriptor.agent {
        case .claudeCode, .qoder, .qwenCode, .factory, .codebuddy:
            report = checkClaude(
                claudeDirectory: descriptor.directory,
                hooksBinaryURL: hooksBinaryURL,
                managedHooksBinaryURL: managedHooksBinaryURL,
                fileManager: fileManager
            )
        case .codex:
            report = checkCodex(
                codexDirectory: descriptor.directory,
                hooksBinaryURL: hooksBinaryURL,
                managedHooksBinaryURL: managedHooksBinaryURL,
                fileManager: fileManager
            )
        case .openCode:
            report = checkOpenCode(opencodeDirectory: descriptor.directory, fileManager: fileManager)
        case .cursor, .gemini, .antigravity, .kimi, .claudeUsageBridge:
            report = checkConfigFile(
                descriptor,
                hooksBinaryURL: hooksBinaryURL,
                managedHooksBinaryURL: managedHooksBinaryURL,
                fileManager: fileManager
            )
        }

        report.agent = descriptor.agent.rawValue
        return report
    }

    /// The commands in an agent's config that run our binary. Works on the
    /// nested shapes each agent uses, because it only looks for the
    /// `command` key; Kimi's TOML keeps one per `[[hooks]]` block.
    public static func installedCommands(in descriptor: HookAgentDescriptor) -> [String] {
        guard let data = try? Data(contentsOf: descriptor.configURL) else {
            return []
        }

        let commands: [String]
        if descriptor.configURL.pathExtension == "toml" {
            commands = String(decoding: data, as: UTF8.self)
                .components(separatedBy: .newlines)
                .compactMap(tomlCommand(in:))
        } else {
            commands = (try? JSONSerialization.jsonObject(with: data)).map(allCommands(in:)) ?? []
        }

        return commands.filter(isOurCommand)
    }

    /// The executable a hook command launches, unquoted.
    public static func binaryPath(ofCommand command: String) -> String {
        extractBinaryPath(from: command)
    }

    // MARK: - Private helpers

    private static func checkConfigFile(
        _ descriptor: HookAgentDescriptor,
        hooksBinaryURL: URL?,
        managedHooksBinaryURL: URL,
        fileManager: FileManager
    ) -> HookHealthReport {
        var issues: [HookHealthReport.Issue] = []
        let resolvedBinaryPath = resolveBinaryPath(
            explicit: hooksBinaryURL,
            managed: managedHooksBinaryURL,
            fileManager: fileManager
        )

        if let path = resolvedBinaryPath {
            if !fileManager.isExecutableFile(atPath: path) {
                issues.append(.binaryNotExecutable(path: path))
            }
        } else {
            issues.append(.binaryNotFound)
        }

        let configPath = descriptor.configURL.path
        if fileManager.fileExists(atPath: configPath) {
            if let data = try? Data(contentsOf: descriptor.configURL) {
                if descriptor.configURL.pathExtension != "toml",
                   (try? JSONSerialization.jsonObject(with: data)) == nil {
                    issues.append(.configMalformedJSON(path: configPath))
                }

                let paths = Set(installedCommands(in: descriptor).map(extractBinaryPath(from:)))
                for path in paths.sorted() where !fileManager.fileExists(atPath: path) {
                    issues.append(.staleCommandPath(recorded: path, configPath: configPath))
                }
            } else {
                issues.append(.configUnreadable(path: configPath))
            }
        }

        return HookHealthReport(
            agent: descriptor.agent.rawValue,
            issues: issues,
            binaryPath: resolvedBinaryPath,
            configPath: configPath
        )
    }

    private static func allCommands(in value: Any) -> [String] {
        if let object = value as? [String: Any] {
            return object.flatMap { key, nested -> [String] in
                if key == "command", let command = nested as? String {
                    return [command]
                }
                return allCommands(in: nested)
            }
        }

        if let list = value as? [Any] {
            return list.flatMap(allCommands(in:))
        }

        return []
    }

    private static func tomlCommand(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("command"),
              let equals = trimmed.firstIndex(of: "=") else {
            return nil
        }

        let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote else {
            return nil
        }

        let body = String(value.dropFirst().dropLast())
        return quote == "'"
            ? body
            : body.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func isOurCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return normalized.contains("notchtunehooks") || normalized.contains("openislandhooks")
    }

    private static func resolveBinaryPath(
        explicit: URL?,
        managed: URL,
        fileManager: FileManager
    ) -> String? {
        if let explicit, fileManager.fileExists(atPath: explicit.path) {
            return explicit.path
        }

        if fileManager.fileExists(atPath: managed.path) {
            return managed.path
        }

        // Check all candidate URLs
        for candidate in ManagedHooksBinary.candidateURLs(fileManager: fileManager) {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }

        return nil
    }

    /// Extracts command paths from hooks JSON and checks if they point to existing files.
    private static func findStaleCommandPaths(
        in data: Data,
        fileManager: FileManager
    ) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return []
        }

        var staleCommands: [String] = []
        var seenCommands: Set<String> = []

        for (_, eventValue) in hooks {
            guard let groups = eventValue as? [[String: Any]] else { continue }
            for group in groups {
                guard let hookEntries = group["hooks"] as? [[String: Any]] else { continue }
                for hook in hookEntries {
                    guard let command = hook["command"] as? String else { continue }

                    // Only check Open Island / Vibe Island commands
                    let normalized = command.lowercased()
                    guard normalized.contains("notchtunehooks") || normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks")
                        || normalized.contains("open-island") || normalized.contains("vibe-island") else {
                        continue
                    }

                    // Extract the actual binary path from the shell-quoted command
                    let binaryPath = extractBinaryPath(from: command)
                    guard !seenCommands.contains(binaryPath) else { continue }
                    seenCommands.insert(binaryPath)

                    if !fileManager.fileExists(atPath: binaryPath) {
                        staleCommands.append(binaryPath)
                    }
                }
            }
        }

        return staleCommands
    }

    /// Finds third-party (non-NotchTune) hook command names for display.
    private static func findThirdPartyHookNames(in data: Data, agent: String) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return []
        }

        var names: Set<String> = []

        for (_, eventValue) in hooks {
            guard let groups = eventValue as? [[String: Any]] else { continue }
            for group in groups {
                guard let hookEntries = group["hooks"] as? [[String: Any]] else { continue }
                for hook in hookEntries {
                    guard let command = hook["command"] as? String else { continue }
                    let normalized = command.lowercased()

                    // Skip Open Island / Vibe Island hooks
                    if normalized.contains("notchtunehooks") || normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks")
                        || normalized.contains("open-island") || normalized.contains("vibe-island") {
                        continue
                    }

                    // Skip claude-island (reported separately)
                    if normalized.contains("claude-island") {
                        continue
                    }

                    // Extract a short name from the command for display
                    let name = extractCommandName(from: command)
                    if !name.isEmpty {
                        names.insert(name)
                    }
                }
            }
        }

        return names.sorted()
    }

    /// Checks if settings.json contains claude-island hooks.
    private static func containsClaudeIslandHook(in data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }

        for (_, eventValue) in hooks {
            guard let groups = eventValue as? [[String: Any]] else { continue }
            for group in groups {
                guard let hookEntries = group["hooks"] as? [[String: Any]] else { continue }
                for hook in hookEntries {
                    if let command = hook["command"] as? String,
                       command.contains("claude-island-state.py") {
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Checks whether any NotchTune managed hooks exist in a config file.
    private static func hasNotchTuneHooks(in url: URL, fileManager: FileManager) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }

        for (_, eventValue) in hooks {
            guard let groups = eventValue as? [[String: Any]] else { continue }
            for group in groups {
                guard let hookEntries = group["hooks"] as? [[String: Any]] else { continue }
                for hook in hookEntries {
                    if let command = hook["command"] as? String {
                        let normalized = command.lowercased()
                        if normalized.contains("notchtunehooks") || normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks") {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    /// Extracts the binary path from a potentially shell-quoted command string.
    /// e.g. "'/path/to/binary' --source claude" → "/path/to/binary"
    private static func extractBinaryPath(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("'") {
            // Shell-quoted path: find closing quote
            if let endQuote = trimmed.dropFirst().firstIndex(of: "'") {
                return String(trimmed[trimmed.index(after: trimmed.startIndex)..<endQuote])
            }
        }

        if trimmed.hasPrefix("\"") {
            if let endQuote = trimmed.dropFirst().firstIndex(of: "\"") {
                return String(trimmed[trimmed.index(after: trimmed.startIndex)..<endQuote])
            }
        }

        // No quoting — take the first word
        return String(trimmed.prefix(while: { !$0.isWhitespace }))
    }

    /// Extracts a human-readable name from a hook command.
    private static func extractCommandName(from command: String) -> String {
        let binaryPath = extractBinaryPath(from: command)
        let lastComponent = (binaryPath as NSString).lastPathComponent
        return lastComponent.isEmpty ? binaryPath : lastComponent
    }
}
