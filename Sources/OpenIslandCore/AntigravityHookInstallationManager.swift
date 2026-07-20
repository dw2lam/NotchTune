import Foundation

public struct AntigravityHookInstallationStatus: Equatable, Sendable {
    public var configDirectory: URL
    public var hooksURL: URL
    public var manifestURL: URL
    public var hooksBinaryURL: URL?
    public var managedHooksPresent: Bool
    public var manifest: AntigravityHookInstallerManifest?

    public init(
        configDirectory: URL,
        hooksURL: URL,
        manifestURL: URL,
        hooksBinaryURL: URL?,
        managedHooksPresent: Bool,
        manifest: AntigravityHookInstallerManifest?
    ) {
        self.configDirectory = configDirectory
        self.hooksURL = hooksURL
        self.manifestURL = manifestURL
        self.hooksBinaryURL = hooksBinaryURL
        self.managedHooksPresent = managedHooksPresent
        self.manifest = manifest
    }
}

/// Reads and writes NotchTune's hooks in Antigravity's shared config file,
/// `~/.gemini/config/hooks.json` (the path the current `agy` CLI loads).
public final class AntigravityHookInstallationManager: @unchecked Sendable {
    public let configDirectory: URL
    public let managedHooksBinaryURL: URL
    private let fileManager: FileManager

    public init(
        configDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/config", isDirectory: true),
        managedHooksBinaryURL: URL = ManagedHooksBinary.defaultURL(),
        fileManager: FileManager = .default
    ) {
        self.configDirectory = configDirectory
        self.managedHooksBinaryURL = managedHooksBinaryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    private var hooksURL: URL { configDirectory.appendingPathComponent("hooks.json") }
    private var manifestURL: URL {
        configDirectory.appendingPathComponent(AntigravityHookInstallerManifest.fileName)
    }

    public func status(hooksBinaryURL: URL? = nil) throws -> AntigravityHookInstallationStatus {
        let resolvedBinaryURL = resolvedHooksBinaryURL(explicitURL: hooksBinaryURL)
        let hooksData = try? Data(contentsOf: hooksURL)
        let manifest = try loadManifest(at: manifestURL)

        return AntigravityHookInstallationStatus(
            configDirectory: configDirectory,
            hooksURL: hooksURL,
            manifestURL: manifestURL,
            hooksBinaryURL: resolvedBinaryURL,
            managedHooksPresent: AntigravityHookInstaller.managedHooksPresent(in: hooksData),
            manifest: manifest
        )
    }

    @discardableResult
    public func install(hooksBinaryURL: URL) throws -> AntigravityHookInstallationStatus {
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        let existing = try? Data(contentsOf: hooksURL)
        let installedBinaryURL = try ManagedHooksBinary.install(
            from: hooksBinaryURL,
            to: managedHooksBinaryURL,
            fileManager: fileManager
        )
        let mutation = try AntigravityHookInstaller.installHooksJSON(
            existingData: existing,
            binaryPath: installedBinaryURL.path
        )

        if mutation.changed, fileManager.fileExists(atPath: hooksURL.path) {
            try backupFile(at: hooksURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: hooksURL, options: .atomic)
        }

        let manifest = AntigravityHookInstallerManifest(
            hookCommand: AntigravityHookInstaller.baseHookCommand(for: installedBinaryURL.path)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        return try status(hooksBinaryURL: installedBinaryURL)
    }

    @discardableResult
    public func uninstall() throws -> AntigravityHookInstallationStatus {
        let existing = try? Data(contentsOf: hooksURL)
        let mutation = try AntigravityHookInstaller.uninstallHooksJSON(existingData: existing)

        if mutation.changed, fileManager.fileExists(atPath: hooksURL.path) {
            try backupFile(at: hooksURL)
        }

        if let contents = mutation.contents {
            try contents.write(to: hooksURL, options: .atomic)
        } else if fileManager.fileExists(atPath: hooksURL.path) {
            try fileManager.removeItem(at: hooksURL)
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        return try status()
    }

    private func loadManifest(at url: URL) throws -> AntigravityHookInstallerManifest? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AntigravityHookInstallerManifest.self, from: data)
    }

    private func resolvedHooksBinaryURL(explicitURL: URL?) -> URL? {
        if let explicitURL {
            return explicitURL.standardizedFileURL
        }

        guard fileManager.isExecutableFile(atPath: managedHooksBinaryURL.path) else {
            return nil
        }

        return managedHooksBinaryURL
    }

    private func backupFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }

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
