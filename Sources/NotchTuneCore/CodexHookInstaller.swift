import Foundation

public struct CodexHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-install.json"
    public static let legacyFileName = "vibe-island-install.json"

    public var hookCommand: String
    public var enabledCodexHooksFeature: Bool
    public var installedAt: Date

    public init(
        hookCommand: String,
        enabledCodexHooksFeature: Bool,
        installedAt: Date = .now
    ) {
        self.hookCommand = hookCommand
        self.enabledCodexHooksFeature = enabledCodexHooksFeature
        self.installedAt = installedAt
    }
}

public struct CodexFeatureMutation: Equatable, Sendable {
    public var contents: String
    public var changed: Bool
    public var featureEnabledByInstaller: Bool

    public init(contents: String, changed: Bool, featureEnabledByInstaller: Bool) {
        self.contents = contents
        self.changed = changed
        self.featureEnabledByInstaller = featureEnabledByInstaller
    }
}

public struct CodexHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var hasRemainingHooks: Bool

    public init(contents: Data?, changed: Bool, hasRemainingHooks: Bool) {
        self.contents = contents
        self.changed = changed
        self.hasRemainingHooks = hasRemainingHooks
    }
}

public enum CodexHooksFeatureFlagKey: String, Equatable, Sendable {
    case current = "hooks"
    case legacy = "codex_hooks"

    var alternate: CodexHooksFeatureFlagKey {
        switch self {
        case .current:
            return .legacy
        case .legacy:
            return .current
        }
    }
}

public enum CodexHookInstallerError: Error, LocalizedError {
    case invalidHooksJSON
    case cannotEditConfig(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHooksJSON:
            "The existing Codex hooks file is not valid JSON."
        case let .cannotEditConfig(reason):
            "NotchTune left ~/.codex/config.toml alone because \(reason)."
        }
    }
}

public enum CodexHookInstaller {
    public static let managedStatusMessage = "Managed by NotchTune"
    public static let legacyOpenIslandManagedStatusMessage = "Managed by Open Island"
    public static let legacyManagedStatusMessage = "Managed by Vibe Island"
    public static let managedTimeout = 45
    public static let managedInteractiveTimeout = 60 * 60
    private static let versionProbeDeadline: TimeInterval = 3
    private static let currentFeatureKey = CodexHooksFeatureFlagKey.current.rawValue
    private static let legacyFeatureKey = CodexHooksFeatureFlagKey.legacy.rawValue

    // Keep the managed Codex install aligned with the original app's low-noise footprint.
    // PermissionRequest is first-class and low-noise; per-command Bash hooks
    // remain opt-in because they produce terminal log spam.
    private static let eventSpecs: [(name: String, matcher: String?, timeout: Int)] = [
        ("SessionStart", "startup|resume", managedTimeout),
        ("UserPromptSubmit", nil, managedTimeout),
        ("PermissionRequest", nil, managedInteractiveTimeout),
        ("Stop", nil, managedTimeout),
    ]

    public static func hookCommand(for binaryPath: String) -> String {
        shellQuote(binaryPath)
    }

    public static func installHooksJSON(
        existingData: Data?,
        hookCommand: String
    ) throws -> CodexHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)
        let existingHooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        for (eventName, value) in existingHooksObject {
            let existingGroups = value as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)

            if !cleanedGroups.isEmpty {
                hooksObject[eventName] = cleanedGroups
            }
        }

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups, replacingCommand: hookCommand)
            hooksObject[spec.name] = cleanedGroups + [
                managedGroup(matcher: spec.matcher, hookCommand: hookCommand, timeout: spec.timeout)
            ]
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)
        let changed = data != existingData
        return CodexHookFileMutation(contents: data, changed: changed, hasRemainingHooks: true)
    }

    public static func uninstallHooksJSON(
        existingData: Data?,
        managedCommand: String?
    ) throws -> CodexHookFileMutation {
        guard let existingData else {
            return CodexHookFileMutation(contents: nil, changed: false, hasRemainingHooks: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var mutated = false

        for spec in eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups, managedCommand: managedCommand)

            if cleanedGroups.count != existingGroups.count || containsManagedHook(in: existingGroups, managedCommand: managedCommand) {
                mutated = true
            }

            if cleanedGroups.isEmpty {
                hooksObject.removeValue(forKey: spec.name)
            } else {
                hooksObject[spec.name] = cleanedGroups
            }
        }

        if hooksObject.isEmpty {
            rootObject.removeValue(forKey: "hooks")
            guard !rootObject.isEmpty else {
                return CodexHookFileMutation(contents: nil, changed: mutated, hasRemainingHooks: false)
            }
            // Keys beside `hooks` aren't ours to take with it.
            let data = try serialize(rootObject)
            return CodexHookFileMutation(contents: data, changed: mutated || data != existingData, hasRemainingHooks: false)
        }

        rootObject["hooks"] = hooksObject
        let data = try serialize(rootObject)
        return CodexHookFileMutation(contents: data, changed: mutated || data != existingData, hasRemainingHooks: true)
    }

    /// Enables the current Codex hooks feature flag and migrates the legacy flag when present.
    ///
    /// Writes in whichever form the file already uses for `features`: TOML
    /// rejects a `[features]` table next to `features.x = ...` or
    /// `features = { ... }`, so adding the wrong one breaks the user's config.
    public static func enableCodexHooksFeature(
        in contents: String,
        preferredKey: CodexHooksFeatureFlagKey = .current
    ) -> CodexFeatureMutation {
        var document = CodexTOMLDocument(contents)
        let featureKey = preferredKey.rawValue
        let alternateFeatureKey = preferredKey.alternate.rawValue
        let wasEnabled = featureValue(for: featureKey, in: document) == true
        let alternateWasEnabled = featureValue(for: alternateFeatureKey, in: document) == true

        switch featureStyle(in: document) {
        case let .table(body):
            if let index = featureLine(featureKey, inTable: body, of: document) {
                if !wasEnabled {
                    document.replaceLine(at: index, with: "\(featureKey) = true")
                }
                removeFeature(alternateFeatureKey, from: &document)
            } else if let index = featureLine(alternateFeatureKey, inTable: body, of: document) {
                document.replaceLine(at: index, with: "\(featureKey) = true")
            } else {
                document.insertLine("\(featureKey) = true", at: endOfContent(in: body, of: document))
            }

        case .dotted:
            if let index = document.indexOfRootAssignment(key: ["features", featureKey]) {
                if !wasEnabled {
                    document.replaceLine(at: index, with: "features.\(featureKey) = true")
                }
                removeFeature(alternateFeatureKey, from: &document)
            } else if let index = document.indexOfRootAssignment(key: ["features", alternateFeatureKey]) {
                document.replaceLine(at: index, with: "features.\(featureKey) = true")
            } else if let last = document.rootAssignments(prefix: "features").last {
                document.insertLine("features.\(featureKey) = true", at: last + 1)
            }

        case let .inline(index, value):
            let entries = inlineEntries(value).filter {
                $0.key != featureKey && $0.key != alternateFeatureKey
            }
            let rendered = (entries.map { "\($0.key) = \($0.value)" } + ["\(featureKey) = true"])
                .joined(separator: ", ")
            document.replaceLine(at: index, with: "features = { \(rendered) }")

        case .absent:
            if document.rawLines.last?.isEmpty == false {
                document.insertLine("", at: document.rawLines.count)
            }
            document.insertLine("[features]", at: document.rawLines.count)
            document.insertLine("\(featureKey) = true", at: document.rawLines.count)
        }

        let updated = document.text
        return CodexFeatureMutation(
            contents: updated,
            changed: updated != contents,
            featureEnabledByInstaller: !wasEnabled && !alternateWasEnabled
        )
    }

    /// The check that runs before a config edit reaches disk. The editor is
    /// line-based, so it's the file's shape after the edit, not the code that
    /// made it, that decides whether it's safe to write.
    public static func verifyFeatureMutation(
        _ mutation: CodexFeatureMutation,
        original: String,
        preferredKey: CodexHooksFeatureFlagKey
    ) throws {
        let before = CodexTOMLDocument(original)
        let after = CodexTOMLDocument(mutation.contents)

        guard before.headerIndices(of: ["features"]).count <= 1,
              after.headerIndices(of: ["features"]).count <= 1 else {
            throw CodexHookInstallerError.cannotEditConfig("it defines [features] more than once")
        }

        guard featureValue(for: preferredKey.rawValue, in: after) == true else {
            throw CodexHookInstallerError.cannotEditConfig("the hooks flag didn't take effect")
        }

        // Every other line must survive: the only lines allowed to change are
        // the flag itself and, for an inline table, the line holding it.
        var remaining = after.rawLines
        for line in before.rawLines {
            if let index = remaining.firstIndex(of: line) {
                remaining.remove(at: index)
            } else if !isFeatureFlagLine(line) {
                throw CodexHookInstallerError.cannotEditConfig("the edit would have changed other settings")
            }
        }
    }

    /// Removes hook feature flags that were previously enabled by the managed installer.
    public static func disableCodexHooksFeatureIfManaged(in contents: String) -> CodexFeatureMutation {
        var document = CodexTOMLDocument(contents)
        var removed = false

        for key in [currentFeatureKey, legacyFeatureKey] where featureValue(for: key, in: document) != nil {
            removeFeature(key, from: &document)
            removed = true
        }

        guard removed else {
            return CodexFeatureMutation(contents: contents, changed: false, featureEnabledByInstaller: false)
        }

        if let header = document.headerIndices(of: ["features"]).first,
           let body = document.tableBody(of: ["features"]),
           !body.contains(where: { !isBlankOrComment(document.rawLines[$0]) }) {
            document.removeLine(at: header)
            if header < document.rawLines.count, document.rawLines[header].isEmpty {
                document.removeLine(at: header)
            }
        }

        return CodexFeatureMutation(
            contents: document.text,
            changed: true,
            featureEnabledByInstaller: false
        )
    }

    /// Returns whether the config enables Codex hooks using either the current or legacy flag.
    public static func isCodexHooksFeatureEnabled(in contents: String) -> Bool {
        let document = CodexTOMLDocument(contents)
        return featureValue(for: currentFeatureKey, in: document) == true
            || featureValue(for: legacyFeatureKey, in: document) == true
    }

    /// Hooks are on by default in current Codex builds, so only an explicit
    /// `false` turns them off; an absent flag proves nothing.
    public static func isCodexHooksFeatureExplicitlyDisabled(in contents: String) -> Bool {
        let document = CodexTOMLDocument(contents)
        return featureValue(for: currentFeatureKey, in: document) == false
            || featureValue(for: legacyFeatureKey, in: document) == false
    }

    public static func preferredCodexHooksFeatureKey() -> CodexHooksFeatureFlagKey {
        if let featureKey = commandOutput(arguments: ["features", "list"])
            .flatMap(preferredCodexHooksFeatureKey(fromFeatureList:)) {
            return featureKey
        }

        if let featureKey = commandOutput(arguments: ["--version"])
            .flatMap(preferredCodexHooksFeatureKey(fromVersionOutput:)) {
            return featureKey
        }

        return .legacy
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw CodexHookInstallerError.invalidHooksJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitize(groups: [Any], managedCommand: String?) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHook(hook, managedCommand: managedCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func sanitizeForInstall(groups: [Any], replacingCommand: String) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else {
                return nil
            }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else {
                    return nil
                }

                return isManagedHookForInstall(hook, replacingCommand: replacingCommand) ? nil : hook
            }

            guard !filteredHooks.isEmpty else {
                return nil
            }

            group["hooks"] = filteredHooks
            return group
        }
    }

    private static func containsManagedHook(in groups: [Any], managedCommand: String?) -> Bool {
        groups.contains { item in
            guard let group = item as? [String: Any],
                  let hooks = group["hooks"] as? [Any] else {
                return false
            }

            return hooks.contains { hook in
                guard let hook = hook as? [String: Any] else {
                    return false
                }

                return isManagedHook(hook, managedCommand: managedCommand)
            }
        }
    }

    private static func managedGroup(matcher: String?, hookCommand: String, timeout: Int) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": hookCommand,
                "timeout": timeout,
            ]]
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedHook(_ hook: [String: Any], managedCommand: String?) -> Bool {
        if let statusMessage = hook["statusMessage"] as? String,
           statusMessage == managedStatusMessage ||
            statusMessage == legacyOpenIslandManagedStatusMessage ||
            statusMessage == legacyManagedStatusMessage {
            return true
        }

        guard let managedCommand else {
            return false
        }

        return hook["command"] as? String == managedCommand
    }

    private static func isManagedHookForInstall(_ hook: [String: Any], replacingCommand: String) -> Bool {
        if isManagedHook(hook, managedCommand: replacingCommand) {
            return true
        }

        guard let command = hook["command"] as? String else {
            return false
        }

        return isLegacyNotchTuneHookCommand(command)
    }

    private static func isLegacyNotchTuneHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        if normalized.contains("notchtunehooks") || normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks") {
            return true
        }

        return normalized.contains("open-island-bridge") || normalized.contains("vibe-island-bridge")
    }

    private enum FeatureStyle {
        case table(Range<Int>)
        case dotted
        case inline(index: Int, value: String)
        case absent
    }

    private static func featureStyle(in document: CodexTOMLDocument) -> FeatureStyle {
        if let body = document.tableBody(of: ["features"]) {
            return .table(body)
        }

        if !document.rootAssignments(prefix: "features").isEmpty {
            return .dotted
        }

        if let index = document.indexOfRootAssignment(key: ["features"]),
           case let .assignment(_, value) = document.lines[index] {
            return .inline(index: index, value: value)
        }

        return .absent
    }

    private static func featureLine(
        _ key: String,
        inTable body: Range<Int>,
        of document: CodexTOMLDocument
    ) -> Int? {
        let lines = document.lines
        return body.first { index in
            if case .assignment([key], _) = lines[index] {
                return true
            }
            return false
        }
    }

    /// Last line of real content in a table, so a new key lands above the
    /// blank line that separates it from the next table.
    private static func endOfContent(in body: Range<Int>, of document: CodexTOMLDocument) -> Int {
        var end = body.upperBound
        while end > body.lowerBound, isBlankOrComment(document.rawLines[end - 1]) {
            end -= 1
        }
        return end
    }

    private static func removeFeature(_ key: String, from document: inout CodexTOMLDocument) {
        switch featureStyle(in: document) {
        case let .table(body):
            if let index = featureLine(key, inTable: body, of: document) {
                document.removeLine(at: index)
            }
        case .dotted:
            if let index = document.indexOfRootAssignment(key: ["features", key]) {
                document.removeLine(at: index)
            }
        case let .inline(index, value):
            let entries = inlineEntries(value).filter { $0.key != key }
            let rendered = entries.map { "\($0.key) = \($0.value)" }.joined(separator: ", ")
            document.replaceLine(at: index, with: rendered.isEmpty ? "features = {}" : "features = { \(rendered) }")
        case .absent:
            break
        }
    }

    private static func featureValue(for key: String, in document: CodexTOMLDocument) -> Bool? {
        let value: String?
        switch featureStyle(in: document) {
        case let .table(body):
            value = featureLine(key, inTable: body, of: document).flatMap { index in
                if case let .assignment(_, value) = document.lines[index] {
                    return value
                }
                return nil
            }
        case .dotted:
            value = document.indexOfRootAssignment(key: ["features", key]).flatMap { index in
                if case let .assignment(_, value) = document.lines[index] {
                    return value
                }
                return nil
            }
        case let .inline(_, inlineValue):
            value = inlineEntries(inlineValue).first { $0.key == key }?.value
        case .absent:
            value = nil
        }

        switch value?.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    /// `{ a = true, b = false }` as key/value pairs. Flags are booleans, so a
    /// plain comma split is enough here.
    private static func inlineEntries(_ value: String) -> [(key: String, value: String)] {
        let body = value
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}"))

        return body.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
    }

    private static func isBlankOrComment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed.hasPrefix("#")
    }

    private static func isFeatureFlagLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return [currentFeatureKey, legacyFeatureKey, "features"].contains { key in
            trimmed.hasPrefix(key) || trimmed.hasPrefix("features.\(key)")
        }
    }

    static func preferredCodexHooksFeatureKey(fromFeatureList output: String) -> CodexHooksFeatureFlagKey? {
        let featureNames = Set(output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            line.split(whereSeparator: \.isWhitespace).first.map(String.init)
        })

        if featureNames.contains(currentFeatureKey) {
            return .current
        }
        if featureNames.contains(legacyFeatureKey) {
            return .legacy
        }
        return nil
    }

    static func preferredCodexHooksFeatureKey(fromVersionOutput output: String) -> CodexHooksFeatureFlagKey? {
        guard let versionToken = output.split(whereSeparator: \.isWhitespace).first(where: { token in
            token.first?.isNumber == true
        }) else {
            return nil
        }

        let components = versionToken.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else {
            return nil
        }

        let major = components[0]
        let minor = components[1]
        return major > 0 || minor >= 130 ? .current : .legacy
    }

    private static func commandOutput(arguments: [String]) -> String? {
        for command in codexCommandCandidates() {
            if let output = runCommand(
                executableURL: command.executableURL,
                arguments: command.prefixArguments + arguments
            ) {
                return output
            }
        }

        return nil
    }

    static func codexCommandCandidates() -> [(executableURL: URL, prefixArguments: [String])] {
        var candidates: [(executableURL: URL, prefixArguments: [String])] = [
            (URL(fileURLWithPath: "/usr/bin/env"), ["codex"]),
        ]

        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                candidates.append((URL(fileURLWithPath: path), []))
            }
        }

        return candidates
    }

    /// Bounded because a wedged `codex` (a slow Node wrapper, a first-run
    /// prompt) must not hold an install forever.
    private static func runCommand(executableURL: URL, arguments: [String]) -> String? {
        guard let output = BoundedProcess.run(
            executablePath: executableURL.path,
            arguments: arguments,
            deadline: versionProbeDeadline
        ), output.status == 0 else {
            return nil
        }

        return output.text
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else {
            return "''"
        }

        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
