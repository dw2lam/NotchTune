import Foundation
import Testing
@testable import NotchTuneApp

@MainActor
struct MyspaceClipStoreTests {
    private func makeStore() throws -> (MyspaceClipStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchtune-clips-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (MyspaceClipStore(rootURL: root), root)
    }

    @Test
    func capturesTextAndClassifiesLinks() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let text = store.capture(ClipCapture(text: "ship the notch update"))
        #expect(text?.kind == .text)

        let link = store.capture(ClipCapture(text: "https://notchtune.dev/download"))
        #expect(link?.kind == .link)

        // Sentences containing spaces are never links, even with a scheme-ish start.
        let sentence = store.capture(ClipCapture(text: "https broke my build again"))
        #expect(sentence?.kind == .text)

        #expect(store.clips.count == 3)
    }

    @Test
    func consecutiveDuplicatesAreDeduped() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(store.capture(ClipCapture(text: "same")) != nil)
        #expect(store.capture(ClipCapture(text: "same")) == nil)
        #expect(store.capture(ClipCapture(text: "different")) != nil)
        #expect(store.capture(ClipCapture(text: "same")) != nil)
        #expect(store.clips.count == 3)

        let url = URL(fileURLWithPath: "/tmp/some-file.png")
        #expect(store.capture(ClipCapture(fileURLs: [url])) != nil)
        #expect(store.capture(ClipCapture(fileURLs: [url])) == nil)
    }

    @Test
    func imageCapturesWriteAPNGThatClearAllRemoves() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let clip = try #require(store.capture(ClipCapture(imagePNGData: Data([0x89, 0x50, 0x4E, 0x47]))))
        #expect(clip.kind == .image)
        let stored = try #require(store.storedFileURL(of: clip))
        #expect(FileManager.default.fileExists(atPath: stored.path))

        store.clearAll()
        #expect(store.clips.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
    }

    @Test
    func pruneEnforcesCountCapAndRetention() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let now = Date()
        // One stale clip well past retention, then a full cap of fresh ones.
        _ = store.capture(ClipCapture(text: "stale"), now: now.addingTimeInterval(-MyspaceClipStore.retention - 60))
        for i in 0..<(MyspaceClipStore.maxClips + 5) {
            _ = store.capture(ClipCapture(text: "clip \(i)"), now: now)
        }

        store.prune(now: now)
        #expect(store.clips.count == MyspaceClipStore.maxClips)
        #expect(!store.clips.contains { $0.textValue == "stale" })
    }

    @Test
    func persistenceRoundTripsAcrossStoreInstances() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = store.capture(ClipCapture(text: "persist me"))
        _ = store.capture(ClipCapture(text: "https://example.com/x"))

        let reopened = MyspaceClipStore(rootURL: root)
        #expect(reopened.clips.count == 2)
        #expect(reopened.clips.first?.kind == .link)
        #expect(reopened.clips.last?.textValue == "persist me")
    }
}
