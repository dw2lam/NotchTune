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
    func groupsThoughtsByDayNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let newest = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 19, hour: 20
        )))
        let earlierToday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 19, hour: 8
        )))
        let yesterday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 18, hour: 23
        )))
        let thoughts = [
            thought(createdAt: earlierToday),
            thought(createdAt: yesterday),
            thought(createdAt: newest),
        ]

        let groups = MyspaceStore.groupThoughtsByDay(thoughts, calendar: calendar)

        #expect(groups.count == 2)
        #expect(groups[0].day == calendar.startOfDay(for: newest))
        #expect(groups[0].thoughts.map(\.createdAt) == [newest, earlierToday])
        #expect(groups[1].thoughts.map(\.createdAt) == [yesterday])
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
        #expect(store.archivedReminders.map(\.id) == [thought.id])
        #expect(store.thoughts.first?.isReminderCompleted == true)

        let reloaded = MyspaceStore(rootURL: storage, notificationsEnabled: false)
        #expect(reloaded.thoughts.first?.isReminderCompleted == true)
        #expect(reloaded.archivedReminders.map(\.id) == [thought.id])

        reloaded.toggleReminderCompleted(id: thought.id)
        #expect(reloaded.archivedReminders.isEmpty)
        #expect(reloaded.activeReminders.map(\.id) == [thought.id])

        reloaded.deleteThought(id: thought.id)
        #expect(MyspaceStore(rootURL: storage, notificationsEnabled: false).thoughts.isEmpty)
    }

    @Test
    func untimedReminderRemainsSeparateFromMyspaceAfterReload() throws {
        let storage = temporaryDirectory()
        let store = MyspaceStore(rootURL: storage, notificationsEnabled: false)

        let reminder = try store.addThought(
            text: "Keep this visible",
            reminderAt: nil,
            isReminder: true
        )
        let thought = try store.addThought(text: "An ordinary thought")

        #expect(store.activeReminders.map(\.id) == [reminder.id])
        #expect(store.thoughts.first(where: { $0.id == thought.id })?.isReminder == false)

        let reloaded = MyspaceStore(rootURL: storage, notificationsEnabled: false)
        #expect(reloaded.activeReminders.map(\.id) == [reminder.id])
        #expect(reloaded.thoughts.first(where: { $0.id == thought.id })?.isReminder == false)
    }

    @Test
    func legacyTimedThoughtDecodesAsReminder() throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSinceReferenceDate: 100)
        let reminderAt = Date(timeIntervalSinceReferenceDate: 200)
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString,
            "text": "Legacy reminder",
            "createdAt": createdAt.timeIntervalSinceReferenceDate,
            "reminderAt": reminderAt.timeIntervalSinceReferenceDate,
            "isReminderCompleted": false,
            "attachments": [],
        ])

        let decoded = try JSONDecoder().decode(MyspaceThought.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.isReminder)
        #expect(decoded.reminderAt == reminderAt)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTuneMyspaceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func thought(createdAt: Date) -> MyspaceThought {
        MyspaceThought(
            id: UUID(),
            text: "",
            createdAt: createdAt,
            reminderAt: nil,
            isReminderCompleted: false,
            attachments: []
        )
    }
}
