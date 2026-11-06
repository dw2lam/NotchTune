import Foundation
import Testing
@testable import NotchTuneApp

@MainActor
struct MyspaceFailureTests {
    private let root: URL
    private var indexURL: URL { root.appendingPathComponent("thoughts.json") }
    private var trashURL: URL { root.appendingPathComponent("Trash") }

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchTuneMyspaceFailures-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeStore(undoWindow: Duration = .seconds(60)) -> MyspaceStore {
        MyspaceStore(rootURL: root, notificationsEnabled: false, undoWindow: undoWindow)
    }

    private func sourceFile(_ name: String) throws -> URL {
        let folder = root.deletingLastPathComponent()
            .appendingPathComponent("sources-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func corruptFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.contains(".corrupt-") }
    }

    private func thoughtJSON(_ text: String) -> String {
        """
        {"id":"\(UUID().uuidString)","text":"\(text)","createdAt":"2026-11-01T10:00:00Z",\
        "isReminderCompleted":false,"attachments":[]}
        """
    }

    // MARK: - A damaged index

    @Test
    func aDamagedIndexIsSetAsideNotOverwritten() throws {
        try Data("{ this is not json".utf8).write(to: indexURL)

        let store = makeStore()

        #expect(store.thoughts.isEmpty)
        #expect(store.loadProblem != nil)
        #expect(store.lastErrorMessage == store.loadProblem)

        // The save that used to replace the user's file with an empty list.
        try store.addThought(text: "After the damage")

        let aside = try #require(try corruptFiles().first)
        #expect(aside.hasPrefix("thoughts.json.corrupt-"))
        #expect(try String(contentsOf: root.appendingPathComponent(aside), encoding: .utf8) == "{ this is not json")
    }

    @Test
    func oneBadEntryOnlyLosesThatEntry() throws {
        let json = "[\(thoughtJSON("first")),{\"id\":\"broken\"},\(thoughtJSON("second"))]"
        try Data(json.utf8).write(to: indexURL)

        let store = makeStore()

        #expect(Set(store.thoughts.map(\.text)) == ["first", "second"])
        #expect(store.loadProblem != nil)
        #expect(try corruptFiles().count == 1)
    }

    @Test
    func theBackupFillsInWhatTheDamagedFileLost() throws {
        let store = makeStore()
        try store.addThought(text: "kept")
        try store.addThought(text: "also kept")

        // Damaged on disk after the last good write.
        try Data("garbage".utf8).write(to: indexURL)

        let recovered = makeStore()

        // `.bak` is the file before the last write, so one change behind.
        #expect(recovered.thoughts.map(\.text) == ["kept"])
        #expect(recovered.loadProblem != nil)
    }

    @Test
    func aRecoveredIndexIsWrittenBackSoTheNextLaunchIsQuiet() throws {
        let store = makeStore()
        try store.addThought(text: "one")
        try store.addThought(text: "two")
        try Data("garbage".utf8).write(to: indexURL)
        _ = makeStore()

        let next = makeStore()

        #expect(next.thoughts.map(\.text) == ["one"])
        #expect(next.loadProblem == nil)
    }

    @Test
    func aGoodIndexLoadsWithoutComplaint() throws {
        try makeStore().addThought(text: "fine")

        let store = makeStore()

        #expect(store.thoughts.map(\.text) == ["fine"])
        #expect(store.loadProblem == nil)
        #expect(try corruptFiles().isEmpty)
    }

    @Test
    func theMusicLibraryKeepsItsPinsThroughTheSameDamage() throws {
        let file = root.appendingPathComponent("library.json")
        let good = MusicLibraryItem(id: "spotify:playlist:1", kind: .playlist, title: "Pinned", subtitle: "Spotify")

        // One bad pin among good ones.
        let store = MusicLibraryStore(fileURL: file)
        store.update { $0.spotifyPins = [good] }
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var pins = try #require(json["spotifyPins"] as? [Any])
        pins.append(["id": "broken"])
        json["spotifyPins"] = pins
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        #expect(MusicLibraryStore(fileURL: file).archive.spotifyPins.map(\.id) == [good.id])

        // Nothing readable: the last good write comes back.
        let second = MusicLibraryStore(fileURL: file)
        second.update { $0.spotifyPins = [good, good] }
        second.update { $0.spotifyPins = [] }
        try Data("garbage".utf8).write(to: file)
        #expect(MusicLibraryStore(fileURL: file).archive.spotifyPins.count == 2)
        #expect(try corruptFiles().contains { $0.hasPrefix("library.json.corrupt-") })
    }

    // MARK: - Deleting held files

    @Test
    func everyFileInAMultiFileThoughtCanBeDeletedOnItsOwn() async throws {
        let store = makeStore()
        let thought = try await store.holdFiles([try sourceFile("a.png"), try sourceFile("b.png")])
        let first = thought.attachments[0]
        let second = thought.attachments[1]

        store.deleteAttachment(id: first.id, fromThought: thought.id)

        #expect(store.thoughts.first?.attachments.map(\.id) == [second.id])
        #expect(exists(store.attachmentURL(for: second, thoughtID: thought.id)))

        // The last file takes the thought, which would otherwise be invisible.
        store.deleteAttachment(id: second.id, fromThought: thought.id)
        #expect(store.thoughts.isEmpty)
    }

    @Test
    func deletingAFileKeepsAThoughtThatStillHasText() throws {
        let store = makeStore()
        let thought = try store.addThought(text: "With a file", attachmentURLs: [try sourceFile("a.png")])

        store.deleteAttachment(id: thought.attachments[0].id, fromThought: thought.id)

        #expect(store.thoughts.first?.text == "With a file")
        #expect(store.thoughts.first?.attachments.isEmpty == true)
    }

    @Test
    func multiFileThoughtsAlreadyOnDiskCanBeDeletedFileByFile() async throws {
        let id = try await makeStore()
            .holdFiles([try sourceFile("a.png"), try sourceFile("b.png")]).id

        let reloaded = makeStore()
        let saved = try #require(reloaded.thoughts.first { $0.id == id })
        reloaded.deleteAttachment(id: saved.attachments[0].id, fromThought: id)

        #expect(makeStore().thoughts.first?.attachments.count == 1)
    }

    // MARK: - Undo

    @Test
    func undoBringsBackAThoughtAndItsFiles() throws {
        let store = makeStore()
        let older = try store.addThought(text: "older")
        let thought = try store.addThought(text: "With a file", attachmentURLs: [try sourceFile("a.png")])
        let newer = try store.addThought(text: "newer")
        let file = store.attachmentURL(for: thought.attachments[0], thoughtID: thought.id)

        store.deleteThought(id: thought.id)
        #expect(store.thoughts.map(\.id) == [newer.id, older.id])
        #expect(store.pendingDeletion?.title == "With a file")
        #expect(exists(file) == false)
        // The list on disk moved on too: a crash here must not bring it back.
        #expect(makeStoreForReadingIndex().contains(thought.id) == false)

        store.undoDeletion()

        #expect(store.thoughts.map(\.id) == [newer.id, thought.id, older.id])
        #expect(store.pendingDeletion == nil)
        #expect(exists(file))
        #expect(makeStoreForReadingIndex().contains(thought.id))
    }

    @Test
    func undoBringsBackASingleFileInItsPlace() async throws {
        let store = makeStore()
        let thought = try await store.holdFiles([try sourceFile("a.png"), try sourceFile("b.png")])
        let first = thought.attachments[0]

        store.deleteAttachment(id: first.id, fromThought: thought.id)
        #expect(store.pendingDeletion?.title == "a.png")

        store.undoDeletion()

        #expect(store.thoughts.first?.attachments.map(\.id) == thought.attachments.map(\.id))
        #expect(exists(store.attachmentURL(for: first, thoughtID: thought.id)))
    }

    @Test
    func filesGoForGoodOnceTheUndoWindowCloses() async throws {
        let store = makeStore(undoWindow: .milliseconds(50))
        let thought = try store.addThought(text: "Bye", attachmentURLs: [try sourceFile("a.png")])

        store.deleteThought(id: thought.id)
        #expect(store.pendingDeletion != nil)

        for _ in 0..<100 where store.pendingDeletion != nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.pendingDeletion == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: trashURL.path).isEmpty)
    }

    @Test
    func aSecondDeleteMakesTheFirstPermanent() throws {
        let store = makeStore()
        let first = try store.addThought(text: "first", attachmentURLs: [try sourceFile("a.png")])
        let second = try store.addThought(text: "second")

        store.deleteThought(id: first.id)
        store.deleteThought(id: second.id)
        store.undoDeletion()

        #expect(store.thoughts.map(\.id) == [second.id])
        #expect(try FileManager.default.contentsOfDirectory(atPath: trashURL.path).isEmpty)
    }

    @Test
    func aDeleteLeftPendingByAQuitIsCleanedUpOnLaunch() throws {
        let store = makeStore()
        let thought = try store.addThought(text: "Bye", attachmentURLs: [try sourceFile("a.png")])
        store.deleteThought(id: thought.id)
        #expect(exists(trashURL))

        // Relaunch without the undo window ever closing.
        let relaunched = makeStore()

        #expect(relaunched.thoughts.isEmpty)
        #expect(exists(trashURL) == false)
    }

    @Test
    func undoRestoresAReminderToTheActiveList() throws {
        let store = makeStore()
        let reminder = try store.addThought(text: "Call", reminderAt: .now.addingTimeInterval(3_600))

        store.deleteThought(id: reminder.id)
        #expect(store.activeReminders.isEmpty)

        store.undoDeletion()
        #expect(store.activeReminders.map(\.id) == [reminder.id])
    }

    /// The ids in thoughts.json, read without going through a store (whose
    /// launch would clear the trash under the test).
    private func makeStoreForReadingIndex() -> Set<UUID> {
        guard let data = try? Data(contentsOf: indexURL),
              let thoughts = try? JSONDecoder.myspace.decode([MyspaceThought].self, from: data) else {
            return []
        }
        return Set(thoughts.map(\.id))
    }

    // MARK: - Importing

    @Test
    func aFailedImportLeavesNoCopiesBehind() async throws {
        let store = makeStore()
        let good = try sourceFile("good.png")
        let missing = good.deletingLastPathComponent().appendingPathComponent("missing.png")

        #expect(throws: (any Error).self) {
            try store.addThought(text: "", attachmentURLs: [good, missing])
        }
        await #expect(throws: (any Error).self) {
            try await store.holdFiles([good, missing])
        }

        let attachments = root.appendingPathComponent("Attachments")
        #expect(try FileManager.default.contentsOfDirectory(atPath: attachments.path).isEmpty)
        #expect(store.thoughts.isEmpty)
        #expect(store.lastErrorMessage != nil)
    }

    // MARK: - Reminders that can't alert

    @Test
    func aReminderTimeInThePastIsRefusedAndNothingIsSaved() {
        let store = makeStore()

        #expect(throws: MyspaceStoreError.reminderTimeHasPassed) {
            try store.addThought(text: "Too late", reminderAt: .now.addingTimeInterval(-60), isReminder: true)
        }
        #expect(store.thoughts.isEmpty)
    }

    @Test
    func notificationsBeingOffOnlyMattersForAReminderWithATimeToCome() async throws {
        let status = StatusBox(.off)
        let store = MyspaceStore(rootURL: root, notificationsEnabled: false) { status.value }

        await store.refreshNotificationStatus()
        #expect(store.notificationStatus == .off)
        #expect(store.hasRemindersThatCantAlert == false)

        try store.addThought(text: "Untimed", isReminder: true)
        #expect(store.hasRemindersThatCantAlert == false)

        try store.addThought(text: "Timed", reminderAt: .now.addingTimeInterval(3_600))
        #expect(store.hasRemindersThatCantAlert)

        // Flipped in System Settings: read live, so the row goes away.
        status.value = .allowed
        await store.refreshNotificationStatus()
        #expect(store.hasRemindersThatCantAlert == false)
    }

    private final class StatusBox: @unchecked Sendable {
        var value: MyspaceNotificationStatus
        init(_ value: MyspaceNotificationStatus) { self.value = value }
    }

    @Test
    func aReminderTriggerIsPinnedToTheCalendarsTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Toronto"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let components = MyspaceReminderService.triggerComponents(for: date, calendar: calendar)

        #expect(components.timeZone == calendar.timeZone)
        // Round trips to the same instant, wherever the Mac is by then.
        #expect(calendar.date(from: components) == date)
    }

    @Test
    func aPendingDeletionNamesWhatWent() {
        func thought(text: String, files: [String]) -> MyspaceThought {
            MyspaceThought(
                id: UUID(), text: text, createdAt: .now, reminderAt: nil, isReminderCompleted: false,
                attachments: files.map { MyspaceAttachment(id: UUID(), originalFilename: $0, storedFilename: $0) }
            )
        }
        func title(_ thought: MyspaceThought) -> String {
            MyspacePendingDeletion(id: UUID(), item: .thought(thought)).title
        }

        #expect(title(thought(text: "A note", files: ["a.png"])) == "A note")
        #expect(title(thought(text: "", files: ["a.png"])) == "a.png")
        #expect(title(thought(text: "", files: ["a.png", "b.png"])) == "2 files")
    }
}
