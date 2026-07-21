import AppKit
import Observation
import UniformTypeIdentifiers

/// One captured clipboard entry. Text and links live inline; images are saved
/// as PNGs under `Myspace/Clips/`; file clips keep the original URL.
struct MyspaceClip: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case link
        case image
        case file
    }

    let id: UUID
    let kind: Kind
    var textValue: String?
    var storedFilename: String?
    var filePath: String?
    let createdAt: Date
}

/// Value handed from the pasteboard watcher to the store — a plain struct so
/// capture/dedupe/classification logic is unit-testable without NSPasteboard.
struct ClipCapture: Equatable {
    var text: String?
    var fileURLs: [URL] = []
    var imagePNGData: Data?
}

/// Local-first clipboard history for Myspace (NotchClip-style): everything you
/// copy stays within reach, on this Mac only, with automatic cleanup.
@MainActor
@Observable
final class MyspaceClipStore {
    static let maxClips = 60
    static let retention: TimeInterval = 3 * 24 * 60 * 60

    private(set) var clips: [MyspaceClip] = []

    /// changeCount of the last pasteboard write WE made (copy-back), so the
    /// watcher can skip re-capturing our own writes.
    @ObservationIgnored private(set) var lastOwnWriteChangeCount: Int = -1

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let rootURL: URL
    @ObservationIgnored private let indexURL: URL

    init(
        rootURL: URL = MyspaceStore.defaultRootURL().appendingPathComponent("Clips", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        self.indexURL = rootURL.appendingPathComponent("clips.json")
        load()
    }

    // MARK: - Capture

    /// Classifies and stores a capture. Returns the new clip, or nil when the
    /// capture is empty or identical to the newest clip (consecutive dedupe).
    @discardableResult
    func capture(_ capture: ClipCapture, now: Date = .now) -> MyspaceClip? {
        var clip: MyspaceClip?

        if let data = capture.imagePNGData {
            let filename = "\(UUID().uuidString).png"
            do {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
                try data.write(to: rootURL.appendingPathComponent(filename), options: .atomic)
                clip = MyspaceClip(id: UUID(), kind: .image, storedFilename: filename, createdAt: now)
            } catch {
                return nil
            }
        } else if let url = capture.fileURLs.first {
            // A file copy references the original — don't duplicate the bytes.
            if clips.first?.kind == .file, clips.first?.filePath == url.path { return nil }
            clip = MyspaceClip(id: UUID(), kind: .file, textValue: url.lastPathComponent, filePath: url.path, createdAt: now)
        } else if let text = capture.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if clips.first?.textValue == text { return nil }
            let kind: MyspaceClip.Kind = Self.isLink(text) ? .link : .text
            clip = MyspaceClip(id: UUID(), kind: kind, textValue: text, createdAt: now)
        }

        guard let clip else { return nil }
        clips.insert(clip, at: 0)
        prune(now: now)
        try? persist()
        return clip
    }

    static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Automatic cleanup: cap the count and drop clips older than `retention`.
    func prune(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var kept: [MyspaceClip] = []
        for (index, clip) in clips.enumerated() {
            if index < Self.maxClips, clip.createdAt > cutoff {
                kept.append(clip)
            } else {
                removeStoredFile(of: clip)
            }
        }
        if kept.count != clips.count {
            clips = kept
        }
    }

    // MARK: - Use

    /// Writes the clip back to the general pasteboard for pasting anywhere.
    func copyToPasteboard(_ clip: MyspaceClip) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch clip.kind {
        case .text, .link:
            pasteboard.setString(clip.textValue ?? "", forType: .string)
        case .image:
            if let url = storedFileURL(of: clip), let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            }
        case .file:
            if let path = clip.filePath {
                pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
            }
        }
        lastOwnWriteChangeCount = pasteboard.changeCount
    }

    /// URL to drag out of the shelf (image file, original file, or nil for text).
    func storedFileURL(of clip: MyspaceClip) -> URL? {
        if let storedFilename = clip.storedFilename {
            return rootURL.appendingPathComponent(storedFilename)
        }
        if let path = clip.filePath {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func delete(id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        removeStoredFile(of: clips[index])
        clips.remove(at: index)
        try? persist()
    }

    func clearAll() {
        for clip in clips {
            removeStoredFile(of: clip)
        }
        clips = []
        try? persist()
    }

    // MARK: - Persistence

    private func removeStoredFile(of clip: MyspaceClip) {
        guard let storedFilename = clip.storedFilename else { return }
        try? fileManager.removeItem(at: rootURL.appendingPathComponent(storedFilename))
    }

    private func load() {
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder.myspace.decode([MyspaceClip].self, from: data) else { return }
        clips = decoded.sorted { $0.createdAt > $1.createdAt }
        prune()
    }

    private func persist() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.myspace.encode(clips)
        try data.write(to: indexURL, options: .atomic)
    }
}

/// Polls the general pasteboard's changeCount (a single cheap read) and feeds
/// new copies into the clip store. Skips concealed/transient entries written
/// by password managers and our own copy-backs.
@MainActor
final class ClipboardWatcher {
    private static let skippedTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"),
    ]

    private let store: MyspaceClipStore
    private var task: Task<Void, Never>?
    private var lastSeenChangeCount: Int

    init(store: MyspaceClipStore) {
        self.store = store
        lastSeenChangeCount = NSPasteboard.general.changeCount
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        // Don't capture whatever was copied before the watcher existed.
        lastSeenChangeCount = NSPasteboard.general.changeCount
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastSeenChangeCount else { return }
        lastSeenChangeCount = count
        guard count != store.lastOwnWriteChangeCount else { return }

        let types = pasteboard.types ?? []
        guard !types.contains(where: Self.skippedTypes.contains) else { return }

        var capture = ClipCapture()
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            capture.fileURLs = urls
        } else if types.contains(.png) || types.contains(.tiff) {
            if let image = NSImage(pasteboard: pasteboard),
               let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                capture.imagePNGData = png
            }
        } else {
            capture.text = pasteboard.string(forType: .string)
        }

        store.capture(capture)
    }
}
