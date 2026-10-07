import Foundation
import NotchTuneCore

struct ActiveAgentProcessDiscovery {
    private static let processCommandTimeout: TimeInterval = 0.5
    private static let lsofCommandTimeout: TimeInterval = 0.2

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    struct ProcessSnapshot: Equatable, Sendable {
        var tool: AgentTool
        var sessionID: String?
        var workingDirectory: String?
        var terminalTTY: String?
        var terminalApp: String?
        var transcriptPath: String?
        var tmuxTarget: String?
        var tmuxSocketPath: String?

        init(
            tool: AgentTool,
            sessionID: String?,
            workingDirectory: String?,
            terminalTTY: String?,
            terminalApp: String? = nil,
            transcriptPath: String? = nil,
            tmuxTarget: String? = nil,
            tmuxSocketPath: String? = nil
        ) {
            self.tool = tool
            self.sessionID = sessionID
            self.workingDirectory = workingDirectory
            self.terminalTTY = terminalTTY
            self.terminalApp = terminalApp
            self.transcriptPath = transcriptPath
            self.tmuxTarget = tmuxTarget
            self.tmuxSocketPath = tmuxSocketPath
        }
    }

    /// Result of one discovery pass.
    struct DiscoveryResult: Sendable {
        var snapshots: [ProcessSnapshot]
        /// PIDs of the processes behind `snapshots` (used as exit-watch hints).
        var agentProcessIDs: [Int32]
        /// Whether any `tmux` process exists; `nil` when unknown (the `ps`
        /// fallback has no kernel short names). Without a tmux process every
        /// `tmux list-*` query fails, so callers can skip spawning tmux.
        var isTmuxRunning: Bool?
    }

    /// One process-table row — `ps -Ao pid=,ppid=,tty=,command=`. The command
    /// line is loaded lazily on the native path: only agent candidates (TTY
    /// processes) and the parents walked to find their terminal need it.
    private final class RunningProcess {
        let pid: String
        let parentPID: String
        let terminalTTY: String?
        /// Kernel short name; `nil` on the `ps` path.
        let shortName: String?
        private var loadedCommand: String?
        private let nativePID: pid_t
        private let commandLineReader: NativeProcessInspector.CommandLineReader?

        init(pid: String, parentPID: String, terminalTTY: String?, command: String) {
            self.pid = pid
            self.parentPID = parentPID
            self.terminalTTY = terminalTTY
            self.shortName = nil
            self.loadedCommand = command
            self.nativePID = 0
            self.commandLineReader = nil
        }

        init(entry: NativeProcessInspector.ProcessEntry, reader: NativeProcessInspector.CommandLineReader) {
            self.pid = String(entry.pid)
            self.parentPID = String(entry.parentPID)
            self.terminalTTY = entry.terminalTTY
            self.shortName = entry.shortName
            self.loadedCommand = nil
            self.nativePID = entry.pid
            self.commandLineReader = reader
        }

        var command: String {
            if let loadedCommand {
                return loadedCommand
            }

            let value = commandLineReader?.commandLine(pid: nativePID, shortName: shortName ?? "") ?? ""
            loadedCommand = value
            return value
        }
    }

    /// Per-`discover()` memo: the process table plus tmux answers that are the
    /// same for every agent in the pass (previously re-queried per agent).
    private final class DiscoveryPass {
        let processes: [RunningProcess]
        let processesByPID: [String: RunningProcess]
        let isTmuxRunning: Bool?
        var tmuxPath: String??
        var tmuxServerSocketPath: String??
        var tmuxPaneOutputs: [String: String?] = [:]
        var tmuxClientOutputs: [String: String?] = [:]

        init(processes: [RunningProcess], isTmuxRunning: Bool?) {
            self.processes = processes
            self.isTmuxRunning = isTmuxRunning
            var byPID: [String: RunningProcess] = [:]
            byPID.reserveCapacity(processes.count)
            for process in processes {
                byPID[process.pid] = process
            }
            self.processesByPID = byPID
        }
    }

    /// The working directory and open file paths of a process — the parts of
    /// `lsof -a -p <pid> -Fn` discovery reads.
    private typealias OpenFiles = NativeProcessInspector.OpenFiles

    typealias CommandRunner = @Sendable (_ executablePath: String, _ arguments: [String]) -> String?

    private let commandRunner: CommandRunner
    /// `true` for the production discovery: read the process table and open
    /// files in-process (sysctl/libproc) and only fall back to spawning
    /// `ps`/`lsof` through `commandRunner` when the kernel refuses a query.
    /// Injected runners (tests) keep the text-parsing path.
    private let usesNativeProcessAPIs: Bool

    init() {
        self.commandRunner = Self.commandOutput
        self.usesNativeProcessAPIs = true
    }

    init(commandRunner: @escaping CommandRunner) {
        self.commandRunner = commandRunner
        self.usesNativeProcessAPIs = false
    }

    func discover() -> [ProcessSnapshot] {
        discoverDetailed().snapshots
    }

    func discoverDetailed() -> DiscoveryResult {
        let pass = makeDiscoveryPass()
        let processes = pass.processes
        guard !processes.isEmpty else {
            return DiscoveryResult(snapshots: [], agentProcessIDs: [], isTmuxRunning: pass.isTmuxRunning)
        }

        let processesByPID = pass.processesByPID

        var snapshots: [ProcessSnapshot] = []
        var agentProcessIDs: [Int32] = []
        var claimedKeys: Set<String> = []

        for process in processes {
            guard process.terminalTTY != nil else {
                continue
            }

            if isCodexProcess(command: process.command) {
                guard let snapshot = codexSnapshot(for: process, pass: pass) else {
                    continue
                }

                let claimKey = "codex:\(snapshot.sessionID ?? process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(snapshot)
                agentProcessIDs.append(Int32(process.pid) ?? 0)
                continue
            }

            if isClaudeProcess(command: process.command) {
                guard let snapshot = claudeSnapshot(for: process, pass: pass) else {
                    continue
                }

                let claimKey = "claude:\(snapshot.sessionID ?? snapshot.terminalTTY ?? snapshot.workingDirectory ?? process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(snapshot)
                agentProcessIDs.append(Int32(process.pid) ?? 0)
                continue
            }

            if isOpenCodeProcess(command: process.command) {
                let cwd = openFiles(pid: process.pid, includeDescriptors: false)?.workingDirectory

                // Deduplicate by TTY and working directory instead of PID.
                // Wrappers like `npm exec` and their child `node` process share the same TTY and CWD.
                // Treat a missing cwd as a wildcard for the TTY to match existing claims, but let concrete cwd overwrite wildcard.
                let ttyId = process.terminalTTY ?? process.pid
                
                if cwd == nil {
                    // Only insert wildcard if no concrete claim exists for this TTY.
                    if claimedKeys.contains(where: { $0.hasPrefix("opencode:\(ttyId):") && $0 != "opencode:\(ttyId):" }) {
                        continue
                    }
                } else {
                    // Concrete CWD: remove any existing wildcard claim for this TTY before claiming.
                    if claimedKeys.remove("opencode:\(ttyId):") != nil {
                        // Also remove the orphaned snapshot that was previously appended.
                        snapshots.removeAll {
                            $0.tool == .openCode && $0.terminalTTY == process.terminalTTY && $0.workingDirectory == nil
                        }
                    }
                }

                let claimKey = "opencode:\(ttyId):\(cwd ?? "")"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                var snapshot = ProcessSnapshot(
                    tool: .openCode,
                    sessionID: nil,
                    workingDirectory: cwd,
                    terminalTTY: process.terminalTTY,
                    terminalApp: terminalApp(for: process, processesByPID: processesByPID)
                )

                if snapshot.terminalApp == nil, let agentTTY = process.terminalTTY {
                    if let (tmuxTarget, hostTerminalApp, socketPath) = resolveTmuxInfo(
                        agentTTY: agentTTY,
                        pass: pass
                    ) {
                        snapshot.terminalApp = hostTerminalApp
                        snapshot.tmuxTarget = tmuxTarget
                        snapshot.tmuxSocketPath = socketPath
                    }
                }

                snapshots.append(snapshot)
                agentProcessIDs.append(Int32(process.pid) ?? 0)
                continue
            }

            if isGeminiProcess(command: process.command) {
                let claimKey = "gemini:\(process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(ProcessSnapshot(
                    tool: .geminiCLI,
                    sessionID: nil,
                    workingDirectory: openFiles(pid: process.pid, includeDescriptors: false)?.workingDirectory,
                    terminalTTY: process.terminalTTY,
                    terminalApp: terminalApp(for: process, processesByPID: processesByPID)
                ))
                agentProcessIDs.append(Int32(process.pid) ?? 0)
                continue
            }

            if isAntigravityProcess(command: process.command) {
                let claimKey = "antigravity:\(process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(ProcessSnapshot(
                    tool: .antigravity,
                    sessionID: nil,
                    workingDirectory: openFiles(pid: process.pid, includeDescriptors: false)?.workingDirectory,
                    terminalTTY: process.terminalTTY,
                    terminalApp: terminalApp(for: process, processesByPID: processesByPID)
                ))
                agentProcessIDs.append(Int32(process.pid) ?? 0)
                continue
            }

            if isKimiProcess(command: process.command) {
                let claimKey = "kimi:\(process.pid)"
                guard claimedKeys.insert(claimKey).inserted else {
                    continue
                }

                snapshots.append(ProcessSnapshot(
                    tool: .kimiCLI,
                    sessionID: nil,
                    workingDirectory: openFiles(pid: process.pid, includeDescriptors: false)?.workingDirectory,
                    terminalTTY: process.terminalTTY,
                    terminalApp: terminalApp(for: process, processesByPID: processesByPID)
                ))
                agentProcessIDs.append(Int32(process.pid) ?? 0)
                continue
            }
        }

        return DiscoveryResult(
            snapshots: snapshots,
            agentProcessIDs: agentProcessIDs,
            isTmuxRunning: pass.isTmuxRunning
        )
    }

    private func makeDiscoveryPass() -> DiscoveryPass {
        if usesNativeProcessAPIs, let entries = NativeProcessInspector.processTable() {
            let reader = NativeProcessInspector.CommandLineReader()
            // `ps -A` orders rows by controlling-terminal device, then pid; the
            // claim keys below are first-come-first-served, so keep that order.
            let processes = entries
                .sorted { lhs, rhs in
                    lhs.ttyDevice != rhs.ttyDevice ? lhs.ttyDevice < rhs.ttyDevice : lhs.pid < rhs.pid
                }
                .map { RunningProcess(entry: $0, reader: reader) }
            let isTmuxRunning = entries.contains { $0.shortName == "tmux" }
            return DiscoveryPass(processes: processes, isTmuxRunning: isTmuxRunning)
        }

        return DiscoveryPass(processes: psRunningProcesses(), isTmuxRunning: nil)
    }

    private func psRunningProcesses() -> [RunningProcess] {
        guard let output = commandRunner("/bin/ps", ["-Ao", "pid=,ppid=,tty=,command="]) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> RunningProcess? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }

                let components = trimmed.split(maxSplits: 3, whereSeparator: \.isWhitespace)
                guard components.count == 4 else {
                    return nil
                }

                let pid = String(components[0])
                let parentPID = String(components[1])
                let tty = normalizedTTY(String(components[2]))
                let command = String(components[3]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !command.isEmpty else {
                    return nil
                }

                return RunningProcess(pid: pid, parentPID: parentPID, terminalTTY: tty, command: command)
            }
    }

    private func codexSnapshot(
        for process: RunningProcess,
        pass: DiscoveryPass
    ) -> ProcessSnapshot? {
        guard let openFiles = openFiles(pid: process.pid, includeDescriptors: true),
              let transcriptPath = bestCodexTranscriptPath(in: openFiles),
              let sessionID = firstUUID(in: transcriptPath) else {
            return nil
        }

        var snapshot = ProcessSnapshot(
            tool: .codex,
            sessionID: sessionID,
            workingDirectory: openFiles.workingDirectory,
            terminalTTY: process.terminalTTY,
            terminalApp: terminalApp(for: process, processesByPID: pass.processesByPID)
        )

        // If terminalApp is nil and we have a TTY, try to resolve tmux info
        if snapshot.terminalApp == nil, let agentTTY = process.terminalTTY {
            if let (tmuxTarget, hostTerminalApp, socketPath) = resolveTmuxInfo(
                agentTTY: agentTTY,
                pass: pass
            ) {
                snapshot.terminalApp = hostTerminalApp
                snapshot.tmuxTarget = tmuxTarget
                snapshot.tmuxSocketPath = socketPath
            }
        }

        return snapshot
    }

    private func bestCodexTranscriptPath(in openFiles: OpenFiles) -> String? {
        let paths = allMatchingPaths(in: openFiles, containing: "/.codex/sessions/", suffix: ".jsonl")
        guard !paths.isEmpty else {
            return nil
        }

        return paths.max {
            codexRolloutSortKey(for: $0) < codexRolloutSortKey(for: $1)
        }
    }

    private func codexRolloutSortKey(for path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    private func isClaudeSubagentWorktree(_ path: String) -> Bool {
        path.contains("/.claude/worktrees/agent-")
    }

    private func claudeSnapshot(
        for process: RunningProcess,
        pass: DiscoveryPass
    ) -> ProcessSnapshot? {
        let openFiles = openFiles(pid: process.pid, includeDescriptors: true)
        let workingDirectory = openFiles?.workingDirectory

        // Subagent processes run in .claude/worktrees/agent-*/ directories.
        // They are tracked as metadata on the parent session, not as separate sessions.
        if let cwd = workingDirectory, isClaudeSubagentWorktree(cwd) {
            return nil
        }

        let transcriptPath = openFiles.flatMap {
            bestClaudeTranscriptPath(in: $0, workingDirectory: workingDirectory)
        }
        let sessionID = transcriptPath.flatMap(firstUUID(in:))
            ?? claudeSessionID(from: process.command)

        guard workingDirectory != nil || sessionID != nil else {
            return nil
        }

        var snapshot = ProcessSnapshot(
            tool: .claudeCode,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            terminalTTY: process.terminalTTY,
            terminalApp: terminalApp(for: process, processesByPID: pass.processesByPID),
            transcriptPath: transcriptPath
        )

        // If terminalApp is nil and we have a TTY, try to resolve tmux info
        if snapshot.terminalApp == nil, let agentTTY = process.terminalTTY {
            if let (tmuxTarget, hostTerminalApp, socketPath) = resolveTmuxInfo(
                agentTTY: agentTTY,
                pass: pass
            ) {
                snapshot.terminalApp = hostTerminalApp
                snapshot.tmuxTarget = tmuxTarget
                snapshot.tmuxSocketPath = socketPath
            }
        }

        return snapshot
    }

    private func bestClaudeTranscriptPath(in openFiles: OpenFiles, workingDirectory: String?) -> String? {
        let paths = allMatchingPaths(in: openFiles, containing: "/.claude/projects/", suffix: ".jsonl")
        guard !paths.isEmpty else {
            return nil
        }

        if paths.count == 1 {
            return paths[0]
        }

        if let cwd = workingDirectory {
            let encodedCWD = cwd.replacingOccurrences(of: "/", with: "-")
            if let preferred = paths.first(where: { $0.contains(encodedCWD) }) {
                return preferred
            }
        }

        return paths.first
    }

    private func allMatchingPaths(in openFiles: OpenFiles, containing fragment: String, suffix: String) -> [String] {
        openFiles.paths.filter { $0.contains(fragment) && $0.hasSuffix(suffix) }
    }

    private func terminalApp(
        for process: RunningProcess,
        processesByPID: [String: RunningProcess]
    ) -> String? {
        var currentParentPID = process.parentPID
        var visited: Set<String> = []

        while !currentParentPID.isEmpty,
              currentParentPID != "0",
              currentParentPID != "1",
              visited.insert(currentParentPID).inserted,
              let parent = processesByPID[currentParentPID] {
            let parentCommand = parent.command
            // `ps` rows with an empty command were dropped from the table, which
            // ended the walk; keep that behaviour for lazily loaded commands.
            guard !parentCommand.isEmpty else {
                return nil
            }

            if let terminalApp = recognizedTerminalApp(for: parentCommand) {
                return terminalApp
            }

            currentParentPID = parent.parentPID
        }

        return nil
    }

    private func recognizedTerminalApp(for command: String) -> String? {
        let lowered = command.lowercased()

        if lowered.contains("/codex.app/contents/macos/") {
            return "Codex.app"
        }

        if lowered.contains("/cmux.app/contents/macos/cmux") {
            return "cmux"
        }

        if lowered.contains("/ghostty.app/contents/macos/ghostty") || lowered.hasSuffix("/ghostty") {
            return "Ghostty"
        }

        if lowered.contains("/terminal.app/contents/macos/terminal") {
            return "Terminal"
        }

        if lowered.contains("/iterm.app/contents/macos/iterm2") {
            return "iTerm"
        }

        if lowered.contains("/kaku.app/contents/macos/kaku-gui") || lowered.hasSuffix("/kaku-gui") {
            return "Kaku"
        }

        if lowered.contains("/wezterm.app/contents/macos/wezterm-gui") || lowered.hasSuffix("/wezterm-gui") {
            return "WezTerm"
        }

        if lowered.contains("/warp.app/") || lowered.hasSuffix("/warp") {
            return "Warp"
        }

        if lowered.hasSuffix("/zellij") {
            return "Zellij"
        }

        // VS Code family — check forks BEFORE plain VS Code so fork apps that
        // retain the upstream "Code Helper" naming inside their Electron
        // framework aren't misidentified as VS Code (#415).
        if lowered.contains("/cursor.app/") {
            return "Cursor"
        }
        if lowered.contains("/windsurf.app/") {
            return "Windsurf"
        }
        if lowered.contains("/trae.app/") {
            return "Trae"
        }
        if lowered.contains("/qoder.app/") {
            return "Qoder"
        }
        if lowered.contains("/codebuddy.app/") {
            return "CodeBuddy"
        }
        if lowered.contains("/visual studio code - insiders.app/") {
            return "VS Code Insiders"
        }
        if lowered.contains("/visual studio code.app/") {
            return "VS Code"
        }

        // JetBrains IDEs
        if lowered.contains("/intellij idea.app/") || lowered.contains("/idea.app/") {
            return "IntelliJ IDEA"
        }
        if lowered.contains("/webstorm.app/") {
            return "WebStorm"
        }
        if lowered.contains("/pycharm.app/") {
            return "PyCharm"
        }
        if lowered.contains("/goland.app/") {
            return "GoLand"
        }
        if lowered.contains("/clion.app/") {
            return "CLion"
        }
        if lowered.contains("/rubymine.app/") {
            return "RubyMine"
        }
        if lowered.contains("/phpstorm.app/") {
            return "PhpStorm"
        }
        if lowered.contains("/rider.app/") {
            return "Rider"
        }
        if lowered.contains("/rustrover.app/") {
            return "RustRover"
        }

        return nil
    }

    /// Working directory (and, with `includeDescriptors`, open file paths) of
    /// a process: libproc on the native path, `lsof -a -p <pid> -Fn` otherwise
    /// or when libproc refuses.
    private func openFiles(pid: String, includeDescriptors: Bool) -> OpenFiles? {
        if usesNativeProcessAPIs,
           let pidValue = pid_t(pid),
           let openFiles = NativeProcessInspector.openFiles(pid: pidValue, includeDescriptors: includeDescriptors) {
            return openFiles
        }

        guard let output = commandRunner("/usr/sbin/lsof", ["-a", "-p", pid, "-Fn"]) else {
            return nil
        }

        return OpenFiles(
            workingDirectory: workingDirectory(from: output),
            paths: output
                .split(whereSeparator: \.isNewline)
                .filter { $0.first == "n" }
                .map { String($0.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func workingDirectory(from lsofOutput: String) -> String? {
        let lines = lsofOutput.split(whereSeparator: \.isNewline).map(String.init)
        for index in lines.indices {
            guard lines[index] == "fcwd",
                  lines.indices.contains(index + 1) else {
                continue
            }

            let nextLine = lines[index + 1]
            guard nextLine.first == "n" else {
                continue
            }

            let value = String(nextLine.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/") {
                return value
            }
        }

        return nil
    }

    private static let uuidRegex = try? NSRegularExpression(
        pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    )

    private func firstUUID(in text: String) -> String? {
        guard let regex = Self.uuidRegex else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        return String(text[matchRange]).lowercased()
    }

    private func claudeSessionID(from command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return nil
        }

        for index in tokens.indices {
            let token = tokens[index]

            if token == "--resume" || token == "-r" || token == "--session-id" {
                let nextIndex = tokens.index(after: index)
                guard tokens.indices.contains(nextIndex) else {
                    continue
                }

                if let sessionID = firstUUID(in: tokens[nextIndex]) {
                    return sessionID
                }
            }

            if token.hasPrefix("--resume=") || token.hasPrefix("--session-id=") {
                let value = String(token.split(separator: "=", maxSplits: 1).last ?? "")
                if let sessionID = firstUUID(in: value) {
                    return sessionID
                }
            }
        }

        return nil
    }

    private func normalizedTTY(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "??" else {
            return nil
        }

        if trimmed.hasPrefix("/dev/") {
            return trimmed
        }

        return "/dev/\(trimmed)"
    }

    private func isCodexProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        guard let firstToken = lowered.split(separator: " ").first.map(String.init) else {
            return false
        }

        return firstToken == "codex"
            || firstToken.hasSuffix("/codex")
            || lowered.contains("/codex/codex")
    }

    private func isOpenCodeProcess(command: String) -> Bool {
        let lowered = command.lowercased()

        guard let firstToken = lowered.split(separator: " ").first.map(String.init) else {
            return false
        }

        // Fast path: explicitly launched as opencode or opencode-ai
        if firstToken == "opencode"
            || firstToken == "opencode-ai"
            || firstToken.hasSuffix("/opencode")
            || firstToken.hasSuffix("/opencode-ai")
        {
            return true
        }

        guard lowered.contains("opencode") else {
            return false
        }

        // Wrappers: npx, npm exec, yarn, pnpm dlx, bunx
        let isPackageRunner = firstToken == "npx" || firstToken.hasSuffix("/npx")
            || firstToken == "pnpx" || firstToken.hasSuffix("/pnpx")
            || firstToken == "bunx" || firstToken.hasSuffix("/bunx")
            || ((firstToken == "npm" || firstToken.hasSuffix("/npm")) && (lowered.contains(" exec ") || lowered.contains(" run ")))
            || ((firstToken == "pnpm" || firstToken.hasSuffix("/pnpm")) && (lowered.contains(" dlx ") || lowered.contains(" exec ") || lowered.contains(" run ")))
            || firstToken == "yarn" || firstToken.hasSuffix("/yarn")

        if isPackageRunner {
            let tokens = lowered.split(separator: " ")
            let packageIndex = tokens.firstIndex { token in
                if token.hasPrefix("@opencode-ai/") {
                    return true
                }
                let baseToken = token.hasPrefix("@") ? String(token) : (token.split(separator: "@").first.map(String.init) ?? String(token))
                return baseToken == "opencode" || baseToken == "opencode-ai"
            }
            
            if let packageIndex = packageIndex {
                let installLike: Set<Substring> = ["install", "i", "add", "remove", "rm", "uninstall", "update", "upgrade", "up", "unlink"]
                let isInstallCommand = tokens[..<packageIndex].contains(where: { installLike.contains($0) })
                if !isInstallCommand {
                    return true
                }
            }
        }

        // Node / Bun executing the specific CLI script
        let isNode = firstToken == "node" || firstToken.hasSuffix("/node") || firstToken == "bun" || firstToken.hasSuffix("/bun")
        if isNode && (
            lowered.contains("/opencode-ai/")
            || lowered.contains("/@opencode-ai/")
            || lowered.contains("/node_modules/opencode/")
            || lowered.contains("/node_modules/opencode-ai/")
            || lowered.contains("/node_modules/@opencode-ai/")
            || lowered.hasSuffix("/.bin/opencode")
            || lowered.contains("/.bin/opencode ")
            || lowered.hasSuffix("/.bin/opencode-ai")
            || lowered.contains("/.bin/opencode-ai ")
            || lowered.hasSuffix("/.bin/@opencode-ai")
            || lowered.contains("/.bin/@opencode-ai ")
        ) {
            return true
        }

        return false
    }

    private func isGeminiProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        guard let firstToken = lowered.split(separator: " ").first.map(String.init) else {
            return false
        }

        return firstToken == "gemini"
            || firstToken.hasSuffix("/gemini")
            || lowered.contains("/bin/gemini")
            || lowered.contains("/google/gemini-cli")
            || lowered.contains("/@google/gemini-cli")
    }

    private func isAntigravityProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        guard let firstToken = lowered.split(separator: " ").first.map(String.init) else {
            return false
        }

        let binaryName = (firstToken as NSString).lastPathComponent
        return binaryName == "agy"
            || binaryName == "antigravity"
            || firstToken == "antigravity"
            || firstToken.hasSuffix("/antigravity")
            || lowered.contains("/google/antigravity")
            || lowered.contains("/google/antigravity-cli")
            || lowered.contains("/antigravity-cli")
    }

    /// Matches the `kimi` CLI (Moonshot) entry-point. `kimi-info` / `kimi-mcp` /
    /// `kimi-term` / `kimi-vis` / `kimi-web` are auxiliary subcommands shipped
    /// alongside the main binary and must not be picked up as agent sessions.
    private func isKimiProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        guard let firstToken = lowered.split(separator: " ").first.map(String.init) else {
            return false
        }

        let binaryName = (firstToken as NSString).lastPathComponent
        guard binaryName == "kimi" else {
            return false
        }

        return firstToken == "kimi" || firstToken.hasSuffix("/kimi")
    }

    /// Returns `true` when the given `ps` command string belongs to a Claude Code process.
    /// Matches the official `~/.local/bin/claude` path as well as any absolute path whose
    /// last component is `claude` (e.g. `~/.codefuse/.../claude`).
    private func isClaudeProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        if lowered.contains("/.local/bin/claude") {
            return true
        }

        guard let firstToken = lowered.split(separator: " ").first.map(String.init) else {
            return false
        }

        return firstToken == "claude"
            || firstToken.hasSuffix("/claude")
    }

    static func commandOutput(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        let completionGroup = DispatchGroup()
        completionGroup.enter()
        process.terminationHandler = { _ in
            completionGroup.leave()
        }
        let outputGroup = DispatchGroup()
        outputGroup.enter()
        let outputBox = OutputBox()
        DispatchQueue.global(qos: .utility).async {
            outputBox.data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputGroup.leave()
        }
        let timeout: TimeInterval = executablePath.hasSuffix("/lsof")
            ? Self.lsofCommandTimeout
            : Self.processCommandTimeout

        do {
            try process.run()
            MonitorInstrumentation.recordSpawn(executablePath: executablePath)
        } catch {
            return nil
        }

        let waitResult = completionGroup.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            process.terminate()
            _ = completionGroup.wait(timeout: .now() + 0.1)
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        _ = outputGroup.wait(timeout: .now() + 0.1)
        guard let output = String(data: outputBox.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        return output
    }

    // MARK: - Tmux support

    private func resolveTmuxPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }

        // Fallback to 'which'
        guard let output = commandRunner("/usr/bin/which", ["tmux"]) else {
            return nil
        }

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private func resolveTmuxInfo(
        agentTTY: String,
        pass: DiscoveryPass
    ) -> (target: String, hostTerminalApp: String?, socketPath: String?)? {
        // No tmux process at all: every `tmux list-*` query below would fail
        // ("no server running"), so skip spawning tmux (and `which`).
        if pass.isTmuxRunning == false {
            return nil
        }

        if pass.tmuxPath == nil {
            pass.tmuxPath = .some(resolveTmuxPath())
        }
        guard let tmuxPath = pass.tmuxPath ?? nil else {
            return nil
        }

        // Find tmux-server process to extract socket path if custom.
        // Computed once per pass: it is the same for every agent.
        if pass.tmuxServerSocketPath == nil {
            pass.tmuxServerSocketPath = .some(tmuxServerSocketPath(in: pass))
        }
        let socketPath = pass.tmuxServerSocketPath ?? nil

        // Query tmux list-panes to find the pane matching our TTY
        guard let tmuxTarget = queryTmuxTarget(agentTTY: agentTTY, tmuxPath: tmuxPath, socketPath: socketPath, pass: pass) else {
            return nil
        }

        // Find the terminal app hosting the tmux client connected to this pane
        guard let hostTerminalApp = findTmuxClientTerminal(tmuxPath: tmuxPath, socketPath: socketPath, pass: pass) else {
            return nil
        }

        return (tmuxTarget, hostTerminalApp, socketPath)
    }

    private func tmuxServerSocketPath(in pass: DiscoveryPass) -> String? {
        for process in pass.processes {
            // On the native path the kernel short name identifies tmux
            // processes without loading every command line in the table.
            if let shortName = process.shortName, shortName != "tmux" {
                continue
            }

            if isTmuxServerProcess(command: process.command) {
                // Extract socket path from tmux-server command line
                let parts = process.command.split(separator: " ").map(String.init)
                for (index, part) in parts.enumerated() {
                    if (part == "-S" || part == "-L"), parts.indices.contains(index + 1) {
                        return String(parts[index + 1])
                    }
                }
                return nil
            }
        }

        return nil
    }

    private func queryTmuxTarget(agentTTY: String, tmuxPath: String, socketPath: String?, pass: DiscoveryPass) -> String? {
        let cacheKey = socketPath ?? ""
        let output: String?
        if let cached = pass.tmuxPaneOutputs[cacheKey] {
            output = cached
        } else {
            var args: [String] = ["list-panes", "-a", "-F", "#{pane_tty}\t#{session_name}:#{window_index}.#{pane_index}"]

            if let socketPath = socketPath {
                args = ["-S", socketPath] + args
            }

            output = commandRunner(tmuxPath, args)
            pass.tmuxPaneOutputs[cacheKey] = .some(output)
        }

        guard let output else {
            return nil
        }

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            let ptrTTY = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let target = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if ptrTTY == agentTTY {
                return target
            }
        }

        return nil
    }

    private func findTmuxClientTerminal(
        tmuxPath: String,
        socketPath: String?,
        pass: DiscoveryPass
    ) -> String? {
        let cacheKey = socketPath ?? ""
        let output: String?
        if let cached = pass.tmuxClientOutputs[cacheKey] {
            output = cached
        } else {
            var args: [String] = ["list-clients", "-F", "#{client_tty}"]

            if let socketPath = socketPath {
                args = ["-S", socketPath] + args
            }

            output = commandRunner(tmuxPath, args)
            pass.tmuxClientOutputs[cacheKey] = .some(output)
        }

        guard let output else {
            return nil
        }

        let processesByPID = pass.processesByPID
        for clientTTYLine in output.split(separator: "\n") {
            let clientTTY = clientTTYLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clientTTY.isEmpty else {
                continue
            }

            // Find the process whose TTY matches this client TTY, then walk its parents
            for process in processesByPID.values {
                if process.terminalTTY == clientTTY {
                    if let terminalApp = terminalApp(for: process, processesByPID: processesByPID) {
                        return terminalApp
                    }
                }
            }
        }

        return nil
    }

    private func isTmuxServerProcess(command: String) -> Bool {
        let lowered = command.lowercased()
        return lowered.contains("tmux") && lowered.contains("new-session")
            || lowered.hasSuffix("tmux-server")
            || lowered.contains("tmux") && lowered.contains("server")
    }
}
