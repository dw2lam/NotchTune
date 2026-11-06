import Foundation

public enum HookConfigFileError: Error, LocalizedError, Equatable {
    case unreadable(path: String, reason: String)
    case notUTF8(path: String)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(path, reason):
            "\(path) exists but could not be read (\(reason)), so it was left untouched."
        case let .notUTF8(path):
            "\(path) is not UTF-8 text, so it was left untouched."
        }
    }
}

/// How installers touch a config file the user owns.
///
/// `try? Data(contentsOf:)` can't tell "no file" from "couldn't read it", and
/// an installer that treats the second as the first rewrites or deletes the
/// user's settings. Everything here keeps those two apart.
public enum HookConfigFile {
    /// The file's bytes, or `nil` only when it doesn't exist. Any other
    /// failure throws: the file is there and we can't see what's in it.
    public static func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch {
            throw HookConfigFileError.unreadable(path: url.path, reason: error.localizedDescription)
        }
    }

    public static func readText(_ url: URL) throws -> String? {
        guard let data = try read(url) else {
            return nil
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw HookConfigFileError.notUTF8(path: url.path)
        }

        return text
    }

    /// Atomic write through any symlink: a dotfile manager's link stays a
    /// link instead of being replaced by a plain file.
    public static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    public static func write(_ text: String, to url: URL) throws {
        try write(Data(text.utf8), to: url)
    }
}
