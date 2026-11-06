import Darwin
import Foundation

public enum ManagedHooksBinary {
    public static let binaryName = "NotchTuneHooks"
    public static let legacyBinaryName = "OpenIslandHooks"

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        installDirectory(fileManager: fileManager)
            .appendingPathComponent(binaryName)
            .standardizedFileURL
    }

    public static func candidateURLs(fileManager: FileManager = .default) -> [URL] {
        [
            defaultURL(fileManager: fileManager),
            legacyInstallDirectory(fileManager: fileManager)
                .appendingPathComponent(legacyBinaryName)
                .standardizedFileURL,
        ]
    }

    @discardableResult
    public static func install(
        from sourceURL: URL,
        to destinationURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let resolvedSourceURL = sourceURL.standardizedFileURL
        let resolvedDestinationURL = (destinationURL ?? defaultURL(fileManager: fileManager)).standardizedFileURL

        try fileManager.createDirectory(
            at: resolvedDestinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if resolvedSourceURL != resolvedDestinationURL {
            try replaceAtomically(resolvedDestinationURL, with: resolvedSourceURL, fileManager: fileManager)
        } else {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resolvedDestinationURL.path)
        }

        return resolvedDestinationURL
    }

    /// Overwrites the installed hooks binary if the bundle source differs.
    /// A missing binary is put back when `restoreIfMissing` is set, because
    /// every installed hook points at this exact path; callers pass false
    /// when no agent uses it, so a fresh install stays empty.
    /// Returns `true` if the binary was updated.
    @discardableResult
    public static func updateIfNeeded(
        from sourceURL: URL,
        to destinationURL: URL? = nil,
        restoreIfMissing: Bool = true,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let installedURL = (destinationURL ?? defaultURL(fileManager: fileManager)).standardizedFileURL
        guard sourceURL.standardizedFileURL != installedURL else {
            return false
        }

        guard fileManager.fileExists(atPath: installedURL.path) else {
            guard restoreIfMissing else {
                return false
            }
            try install(from: sourceURL, to: installedURL, fileManager: fileManager)
            return true
        }

        let sourceData = try Data(contentsOf: sourceURL)
        let installedData = try Data(contentsOf: installedURL)
        guard sourceData != installedData else {
            return false
        }

        try replaceAtomically(installedURL, with: sourceURL, fileManager: fileManager)
        return true
    }

    /// Copies beside the destination, then renames over it. Agents run this
    /// path on every event, so it must never be missing or half written, and
    /// a failed copy has to leave the old binary working.
    private static func replaceAtomically(
        _ destinationURL: URL,
        with sourceURL: URL,
        fileManager: FileManager
    ) throws {
        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: stagingURL) }

        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)

        guard rename(stagingURL.path, destinationURL.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func installDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("NotchTune", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    private static func legacyInstallDirectory(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }
}

public enum HooksBinaryLocator {
    public static func locate(
        fileManager: FileManager = .default,
        currentDirectory: URL? = nil,
        executableDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let explicitPath = environment["NOTCHTUNE_HOOKS_BINARY"] ?? environment["VIBE_ISLAND_HOOKS_BINARY"],
           fileManager.isExecutableFile(atPath: explicitPath) {
            return URL(fileURLWithPath: explicitPath).standardizedFileURL
        }

        let currentDirectory = currentDirectory
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidates = [
            executableDirectory?.appendingPathComponent("NotchTuneHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("NotchTuneHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Helpers/NotchTuneHooks"),
            executableDirectory?.appendingPathComponent("VibeIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("VibeIslandHooks"),
            executableDirectory?.deletingLastPathComponent().appendingPathComponent("Helpers/VibeIslandHooks"),
        ].compactMap { $0 } + ManagedHooksBinary.candidateURLs(fileManager: fileManager) + {
            #if arch(arm64)
            let archTriple = "arm64-apple-macosx"
            #elseif arch(x86_64)
            let archTriple = "x86_64-apple-macosx"
            #endif
            return [
                currentDirectory.appendingPathComponent(".build/\(archTriple)/release/NotchTuneHooks"),
                currentDirectory.appendingPathComponent(".build/release/NotchTuneHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/release/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/release/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/debug/NotchTuneHooks"),
                currentDirectory.appendingPathComponent(".build/debug/NotchTuneHooks"),
                currentDirectory.appendingPathComponent(".build/\(archTriple)/debug/VibeIslandHooks"),
                currentDirectory.appendingPathComponent(".build/debug/VibeIslandHooks"),
            ]
        }()

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.standardizedFileURL
        }

        return nil
    }
}
