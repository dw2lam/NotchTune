import Foundation

public struct OpenCodePluginInstallationStatus: Equatable, Sendable {
    public var openCodeConfigDirectory: URL
    public var pluginsDirectory: URL
    public var configURL: URL
    public var pluginFileURL: URL
    public var manifestURL: URL
    public var pluginFilePresent: Bool
    /// A leftover reference from older installs. Nothing needs it: OpenCode
    /// loads the plugins directory by itself on both V1 and V2.
    public var pluginRegistered: Bool
    /// The revision marker in the installed file; 0 for files older than it.
    public var pluginRevision: Int
    public var manifest: OpenCodePluginInstallerManifest?
    /// Why a stale reference in config.json couldn't be removed, when it
    /// couldn't. The plugin itself is already gone; the user has to finish.
    public var configCleanupProblem: String?

    public var isInstalled: Bool {
        pluginFilePresent
    }

    /// Older files are V1 only and silently don't load on OpenCode 2.
    public var pluginIsCurrent: Bool {
        pluginRevision >= OpenCodePluginInstallationManager.currentPluginRevision
    }

    public init(
        openCodeConfigDirectory: URL,
        pluginsDirectory: URL,
        configURL: URL,
        pluginFileURL: URL,
        manifestURL: URL,
        pluginFilePresent: Bool,
        pluginRegistered: Bool,
        pluginRevision: Int = 0,
        manifest: OpenCodePluginInstallerManifest?,
        configCleanupProblem: String? = nil
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.pluginsDirectory = pluginsDirectory
        self.configURL = configURL
        self.pluginFileURL = pluginFileURL
        self.manifestURL = manifestURL
        self.pluginFilePresent = pluginFilePresent
        self.pluginRegistered = pluginRegistered
        self.pluginRevision = pluginRevision
        self.manifest = manifest
        self.configCleanupProblem = configCleanupProblem
    }
}

public struct OpenCodePluginInstallerManifest: Equatable, Codable, Sendable {
    public static let fileName = "notchtune-opencode-plugin-install.json"

    public var pluginPath: String
    public var installedAt: Date

    public init(pluginPath: String, installedAt: Date = .now) {
        self.pluginPath = pluginPath
        self.installedAt = installedAt
    }
}

public enum OpenCodePluginInstallationError: Error, LocalizedError, Equatable {
    case configNotEditable(path: String)

    public var errorDescription: String? {
        switch self {
        case let .configNotEditable(path):
            "\(path) still mentions the plugin, but it isn't plain JSON, so NotchTune left it for you to edit."
        }
    }
}

public final class OpenCodePluginInstallationManager: @unchecked Sendable {
    public static let pluginFileName = "open-island.js"
    /// Keep in step with `notchtune-plugin-revision` in notchtune-opencode.js.
    public static let currentPluginRevision = 2

    public let openCodeConfigDirectory: URL
    private let fileManager: FileManager

    public init(
        openCodeConfigDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.openCodeConfigDirectory = openCodeConfigDirectory
        self.fileManager = fileManager
    }

    private var pluginsDirectory: URL {
        openCodeConfigDirectory.appendingPathComponent("plugins", isDirectory: true)
    }

    private var pluginFileURL: URL {
        pluginsDirectory.appendingPathComponent(Self.pluginFileName)
    }

    private var configURL: URL {
        openCodeConfigDirectory.appendingPathComponent("config.json")
    }

    private var manifestURL: URL {
        openCodeConfigDirectory.appendingPathComponent(OpenCodePluginInstallerManifest.fileName)
    }

    public func status() throws -> OpenCodePluginInstallationStatus {
        let pluginPresent = fileManager.fileExists(atPath: pluginFileURL.path)
        let registered = isPluginRegistered()
        let manifest = try loadManifest()

        return OpenCodePluginInstallationStatus(
            openCodeConfigDirectory: openCodeConfigDirectory,
            pluginsDirectory: pluginsDirectory,
            configURL: configURL,
            pluginFileURL: pluginFileURL,
            manifestURL: manifestURL,
            pluginFilePresent: pluginPresent,
            pluginRegistered: registered,
            pluginRevision: Self.pluginRevision(in: try? Data(contentsOf: pluginFileURL)),
            manifest: manifest
        )
    }

    /// Reads the revision comment from a plugin file's first line.
    public static func pluginRevision(in data: Data?) -> Int {
        guard let data,
              let firstLine = String(decoding: data.prefix(120), as: UTF8.self).split(separator: "\n").first,
              let marker = firstLine.range(of: "notchtune-plugin-revision:") else {
            return 0
        }

        return Int(firstLine[marker.upperBound...].trimmingCharacters(in: .whitespaces)) ?? 0
    }

    @discardableResult
    public func install(pluginSourceData: Data) throws -> OpenCodePluginInstallationStatus {
        try fileManager.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)

        // Write the JS plugin file
        try pluginSourceData.write(to: pluginFileURL, options: .atomic)

        // Older installs registered the file in config.json, which only makes
        // V1 load it twice. A config we can't parse keeps its entry: it's
        // harmless here and not ours to rewrite.
        _ = try? removeConfigReference()

        // Write manifest
        let manifest = OpenCodePluginInstallerManifest(pluginPath: pluginFileURL.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status()
    }

    @discardableResult
    public func uninstall() throws -> OpenCodePluginInstallationStatus {
        // Remove plugin file
        if fileManager.fileExists(atPath: pluginFileURL.path) {
            try fileManager.removeItem(at: pluginFileURL)
        }

        // Remove from config.json. Failing here must not undo the uninstall,
        // but a reference to a deleted file is the user's to know about.
        var cleanupProblem: String?
        do {
            try removeConfigReference()
        } catch {
            cleanupProblem = error.localizedDescription
        }

        // Remove manifest
        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        var result = try status()
        result.configCleanupProblem = cleanupProblem
        return result
    }

    // MARK: - Config.json manipulation

    private func isOurReference(_ entry: Any) -> Bool {
        guard let entry = entry as? String else {
            return false
        }

        return entry == "file://\(pluginFileURL.path)" || entry.hasSuffix("/\(Self.pluginFileName)")
    }

    private func isPluginRegistered() -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = json["plugin"] as? [Any] else {
            return false
        }

        return plugins.contains(where: isOurReference)
    }

    /// Drops our entry and leaves everything else in the list alone, including
    /// the `[name, options]` tuples OpenCode accepts alongside strings.
    private func removeConfigReference() throws {
        guard let data = try HookConfigFile.read(configURL) else {
            return
        }

        // OpenCode accepts JSONC, which JSONSerialization doesn't. Rewriting
        // that from a failed parse would wipe it, so it stays as it is.
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            guard String(decoding: data, as: UTF8.self).contains(Self.pluginFileName) else {
                return
            }
            throw OpenCodePluginInstallationError.configNotEditable(path: configURL.path)
        }

        guard var plugins = json["plugin"] as? [Any], plugins.contains(where: isOurReference) else {
            return
        }

        plugins.removeAll(where: isOurReference)
        try backupFile(at: configURL)

        if plugins.isEmpty {
            json.removeValue(forKey: "plugin")
        } else {
            json["plugin"] = plugins
        }

        let outputData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try HookConfigFile.write(outputData, to: configURL)
    }

    // MARK: - Helpers

    private func loadManifest() throws -> OpenCodePluginInstallerManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OpenCodePluginInstallerManifest.self, from: data)
    }

    private func backupFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.appendingPathExtension("backup.\(timestamp)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }
}
