import Foundation

/// A JSON file that a bad write or a bad entry can't take everything with it.
/// A store that decodes to nothing and then saves replaces the user's file
/// with an empty one, so damage has to be set aside, not walked past.
///
/// - Each write keeps the last good file beside it (`.bak`).
/// - A file that won't decode whole is renamed `.corrupt-<date>`, never
///   overwritten, and whatever it and the backup still hold is kept.
struct RecoverableJSONFile {
    /// What a file decoded to, and whether anything in it had to be dropped.
    struct Decoded<Value> {
        var value: Value
        var isComplete: Bool
    }

    enum Outcome<Value> {
        case missing
        case intact(Value)
        /// The file was damaged and has been set aside; this is what survived.
        case recovered(Value)
        /// The file was damaged and nothing could be saved from it.
        case lost
    }

    let url: URL
    var fileManager: FileManager = .default

    var backupURL: URL {
        url.appendingPathExtension("bak")
    }

    func load<Value>(
        now: Date = .now,
        decode: (Data) throws -> Decoded<Value>,
        merge: (_ survivors: Value, _ backup: Value) -> Value
    ) -> Outcome<Value> {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }

        let decoded = (try? Data(contentsOf: url)).flatMap { try? decode($0) }
        if let decoded, decoded.isComplete {
            return .intact(decoded.value)
        }

        setAside(now: now)
        let backup = (try? Data(contentsOf: backupURL)).flatMap { try? decode($0) }
        switch (decoded, backup) {
        case let (survivors?, backup?):
            return .recovered(merge(survivors.value, backup.value))
        case let (survivors?, nil):
            return .recovered(survivors.value)
        case let (nil, backup?):
            return .recovered(backup.value)
        case (nil, nil):
            return .lost
        }
    }

    /// Replaces the file, keeping what was there as the backup. Damage has
    /// already been moved out of the way by `load`, so that's the last good.
    func write(_ data: Data) throws {
        if let previous = try? Data(contentsOf: url) {
            try? previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }

    private func setAside(now: Date) {
        let stamp = now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let destination = url.appendingPathExtension("corrupt-\(stamp)")
        try? fileManager.moveItem(at: url, to: destination)
    }
}

/// One array element that may fail to decode, so a single bad entry doesn't
/// fail the array around it.
struct LossyElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: any Decoder) throws {
        value = try? Element(from: decoder)
    }
}

extension RecoverableJSONFile {
    /// The elements that decoded, and whether that was all of them.
    static func survivors<Element>(of elements: [LossyElement<Element>]) -> Decoded<[Element]> {
        let values = elements.compactMap(\.value)
        return Decoded(value: values, isComplete: values.count == elements.count)
    }
}
