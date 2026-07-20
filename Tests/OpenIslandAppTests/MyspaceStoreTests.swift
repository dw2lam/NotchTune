import Foundation
import Testing
@testable import OpenIslandApp

@MainActor
struct MyspaceStoreTests {
    @Test
    func savesAndReloadsThoughtsWithCopiedAttachments() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("source.txt")
        try Data("kept locally".utf8).write(to: source)
        let storage = root.appendingPathComponent("storage", isDirectory: true)

        let store = MyspaceStore(rootURL: storage, notificationsEnabled: false)
        let reminder = Date.now.addingTimeInterval(3_600)
        let thought = try store.addThought(
            text: "Remember this",
            attachmentURLs: [source],
            reminderAt: reminder
        )

        #expect(store.thoughts.count == 1)
        #expect(thought.attachments.first?.originalFilename == "source.txt")
        let copiedURL = try #require(thought.attachments.first).storedFilename
        #expect(
            FileManager.default.fileExists(
                atPath: storage
                    .appendingPathComponent("Attachments")
                    .appendingPathComponent(thought.id.uuidString)
                    .appendingPathComponent(copiedURL)
                    .path
            )
        )

        let reloaded = MyspaceStore(rootURL: storage, notificationsEnabled: false)
        #expect(reloaded.thoughts.first?.text == "Remember this")
        #expect(reloaded.activeReminders.first?.id == thought.id)
    }

    @Test
    func requiresTextOrAnAttachment() {
        let store = MyspaceStore(rootURL: temporaryDirectory(), notificationsEnabled: false)

        #expect(throws: MyspaceStoreError.self) {
            try store.addThought(text: "   ")
        }
    }

    @Test
    func holdingFilesCreatesAnAttachmentOnlyThought() throws {
        let root = temporaryDirectory()
        let source = root.appendingPathComponent("held.pdf")
        try Data("held file".utf8).write(to: source)
        let store = MyspaceStore(
            rootURL: root.appendingPathComponent("storage"),
            notificationsEnabled: false
        )

        let thought = try store.holdFiles([source])

        #expect(thought.text.isEmpty)
        #expect(thought.attachments.map(\.originalFilename) == ["held.pdf"])
        #expect(store.thoughts.first?.id == thought.id)
        #expect(
            FileManager.default.fileExists(
                atPath: store.attachmentURL(
                    for: try #require(thought.attachments.first),
                    thoughtID: thought.id
                ).path
            )
        )
    }

    @Test
    func completingAndDeletingReminderPersists() throws {
        let storage = temporaryDirectory()
        let store = MyspaceStore(rootURL: storage, notificationsEnabled: false)
        let thought = try store.addThought(
            text: "A reminder",
            reminderAt: Date.now.addingTimeInterval(3_600)
        )

        store.toggleReminderCompleted(id: thought.id)
        #expect(store.activeReminders.isEmpty)
        #expect(store.thoughts.first?.isReminderCompleted == true)

        let reloaded = MyspaceStore(rootURL: storage, notificationsEnabled: false)
        #expect(reloaded.thoughts.first?.isReminderCompleted == true)

        reloaded.deleteThought(id: thought.id)
        #expect(MyspaceStore(rootURL: storage, notificationsEnabled: false).thoughts.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTuneMyspaceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
