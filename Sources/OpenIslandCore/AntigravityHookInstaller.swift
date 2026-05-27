import Foundation

public struct AntigravityHookInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-antigravity-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct AntigravityHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum AntigravityHookInstallerError: Error, LocalizedError {
    case invalidSettingsJSON

    public var errorDescription: String? {
        switch self {
        case .invalidSettingsJSON:
            "The existing Antigravity hooks.json is not valid JSON."
        }
    }
}

public enum AntigravityHookInstaller {
    private static let eventSpecs: [(name: String, eventArg: String, matcher: String?)] = [
        ("pre_invocation_hooks", "SessionStart", "*"),
        ("post_invocation_hooks", "SessionEnd", "*"),
        ("pre_tool_hooks", "BeforeAgent", "*"),
        ("post_tool_hooks", "AfterAgent", "*"),
        ("stop_hooks", "SessionEnd", "*"),
    ]

    public static func hookCommand(for binaryPath: String, eventArg: String) -> String {
        "\(shellQuote(binaryPath)) --source antigravity --event \(eventArg)"
    }

    public static func installSettingsJSON(
        existingData: Data?,
        binaryPath: String
    ) throws -> AntigravityHookFileMutation {
        var rootObject = try loadRootObject(from: existingData)

        // Install to root level, hooks sub-object, and open-island sub-object
        // 1. Root level keys
        for spec in eventSpecs {
            let specificCommand = hookCommand(for: binaryPath, eventArg: spec.eventArg)
            var groups = rootObject[spec.name] as? [[String: Any]] ?? []
            groups = groups.filter { !isManagedGroup($0, binaryPath: binaryPath) }
            groups.append(managedGroup(matcher: spec.matcher, hookCommand: specificCommand))
            rootObject[spec.name] = groups
        }

        // 2. "hooks" sub-object
        var hooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        for spec in eventSpecs {
            let specificCommand = hookCommand(for: binaryPath, eventArg: spec.eventArg)
            var groups = hooksObject[spec.name] as? [[String: Any]] ?? []
            groups = groups.filter { !isManagedGroup($0, binaryPath: binaryPath) }
            groups.append(managedGroup(matcher: spec.matcher, hookCommand: specificCommand))
            hooksObject[spec.name] = groups
        }
        rootObject["hooks"] = hooksObject

        // 3. "open-island" sub-object
        var openIslandObject = rootObject["open-island"] as? [String: Any] ?? [:]
        for spec in eventSpecs {
            let specificCommand = hookCommand(for: binaryPath, eventArg: spec.eventArg)
            var groups = openIslandObject[spec.name] as? [[String: Any]] ?? []
            groups = groups.filter { !isManagedGroup($0, binaryPath: binaryPath) }
            groups.append(managedGroup(matcher: spec.matcher, hookCommand: specificCommand))
            openIslandObject[spec.name] = groups
        }
        rootObject["open-island"] = openIslandObject

        let data = try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: data,
            changed: data != existingData,
            managedHooksPresent: true
        )
    }

    public static func uninstallSettingsJSON(
        existingData: Data?,
        binaryPath: String
    ) throws -> AntigravityHookFileMutation {
        guard let existingData else {
            return AntigravityHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        var rootObject = try loadRootObject(from: existingData)
        var mutated = false

        // 1. Clean root level keys
        for spec in eventSpecs {
            if let groups = rootObject[spec.name] as? [[String: Any]] {
                let filtered = groups.filter { !isManagedGroup($0, binaryPath: binaryPath) }
                if filtered.count != groups.count {
                    mutated = true
                }

                if filtered.isEmpty {
                    rootObject.removeValue(forKey: spec.name)
                } else {
                    rootObject[spec.name] = filtered
                }
            }
        }

        // 2. Clean "hooks" and "open-island" sub-objects
        let subkeys = ["hooks", "open-island"]
        for key in subkeys {
            if var hooksObject = rootObject[key] as? [String: Any] {
                for spec in eventSpecs {
                    let groups = hooksObject[spec.name] as? [[String: Any]] ?? []
                    let filtered = groups.filter { !isManagedGroup($0, binaryPath: binaryPath) }
                    if filtered.count != groups.count {
                        mutated = true
                    }

                    if filtered.isEmpty {
                        hooksObject.removeValue(forKey: spec.name)
                    } else {
                        hooksObject[spec.name] = filtered
                    }
                }

                if hooksObject.isEmpty {
                    rootObject.removeValue(forKey: key)
                } else {
                    rootObject[key] = hooksObject
                }
            }
        }

        let contents = rootObject.isEmpty ? nil : try serialize(rootObject)
        return AntigravityHookFileMutation(
            contents: contents,
            changed: mutated || contents != existingData,
            managedHooksPresent: mutated
        )
    }

    private static func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw AntigravityHookInstallerError.invalidSettingsJSON
        }

        return rootObject
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func managedGroup(matcher: String?, hookCommand: String) -> [String: Any] {
        let hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
            "name": "Open Island"
        ]

        var group: [String: Any] = [
            "hooks": [hook]
        ]

        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    private static func isManagedGroup(_ group: [String: Any], binaryPath: String) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else {
            return false
        }

        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains(binaryPath) || isOpenIslandAntigravityHookCommand(command)
        }
    }

    private static func isOpenIslandAntigravityHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks"))
            && normalized.contains("antigravity")
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
