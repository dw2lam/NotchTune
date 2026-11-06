import AppKit
import Foundation
import NotchTuneCore
import Observation
@preconcurrency import UserNotifications

struct MyspaceAttachment: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let originalFilename: String
    let storedFilename: String
}

struct MyspaceThought: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var text: String
    let createdAt: Date
    var isReminder: Bool
    var reminderAt: Date?
    var isReminderCompleted: Bool
    var attachments: [MyspaceAttachment]

    init(
        id: UUID,
        text: String,
        createdAt: Date,
        isReminder: Bool? = nil,
        reminderAt: Date?,
        isReminderCompleted: Bool,
        attachments: [MyspaceAttachment]
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isReminder = isReminder ?? (reminderAt != nil)
        self.reminderAt = reminderAt
        self.isReminderCompleted = isReminderCompleted
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
        case isReminder
        case reminderAt
        case isReminderCompleted
        case attachments
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        reminderAt = try container.decodeIfPresent(Date.self, forKey: .reminderAt)
        isReminder = try container.decodeIfPresent(Bool.self, forKey: .isReminder)
            ?? (reminderAt != nil)
        isReminderCompleted = try container.decode(Bool.self, forKey: .isReminderCompleted)
        attachments = try container.decode([MyspaceAttachment].self, forKey: .attachments)
    }
}

/// A delete the user can still take back. The entry has left the list and the
/// index already; its files wait in `Trash/` until the undo window closes,
/// and a launch clears anything a quit or crash left there.
struct MyspacePendingDeletion: Equatable, Identifiable, Sendable {
    enum Item: Equatable, Sendable {
        case thought(MyspaceThought)
        case attachment(MyspaceAttachment, thoughtID: UUID, index: Int)
    }

    let id: UUID
    let item: Item

    /// How the undo bar names what went.
    var title: String {
        switch item {
        case let .thought(thought):
            if !thought.text.isEmpty { return thought.text }
            return thought.attachments.count == 1
                ? thought.attachments[0].originalFilename
                : "\(thought.attachments.count) files"
        case let .attachment(attachment, _, _):
            return attachment.originalFilename
        }
    }
}

/// Whether a timed reminder can reach the user.
enum MyspaceNotificationStatus: Equatable, Sendable {
    case allowed
    /// Refused in System Settings: reminders stay in the list but never alert.
    case off
    /// macOS will ask the first time a reminder is scheduled.
    case notDetermined
    /// No bundle to ask about (`swift run`, tests).
    case unavailable
}

struct MyspaceDayGroup: Equatable, Identifiable, Sendable {
    let day: Date
    let thoughts: [MyspaceThought]

    var id: Date { day }
}

enum MyspaceStoreError: LocalizedError {
    case emptyThought
    case reminderTimeHasPassed

    var errorDescription: String? {
        switch self {
        case .emptyThought:
            "Add a thought or at least one attachment."
        case .reminderTimeHasPassed:
            "That time has passed."
        }
    }
}

@MainActor
@Observable
final class MyspaceStore {
    private(set) var thoughts: [MyspaceThought] = []
    private(set) var lastErrorMessage: String?
    /// The last delete, while it can still be undone.
    private(set) var pendingDeletion: MyspacePendingDeletion?
    private(set) var notificationStatus: MyspaceNotificationStatus = .unavailable
    /// Set when launch found the index damaged, for `AppModel` to tell the user.
    private(set) var loadProblem: String?

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let rootURL: URL
    @ObservationIgnored private let index: RecoverableJSONFile
    @ObservationIgnored private let attachmentsURL: URL
    @ObservationIgnored private let trashURL: URL
    @ObservationIgnored private let notificationsEnabled: Bool
    @ObservationIgnored private let undoWindow: Duration
    @ObservationIgnored private let notificationStatusProvider: @Sendable () async -> MyspaceNotificationStatus
    @ObservationIgnored private var undoTask: Task<Void, Never>?

    init(
        rootURL: URL = MyspaceStore.defaultRootURL(),
        fileManager: FileManager = .default,
        notificationsEnabled: Bool = true,
        undoWindow: Duration = .seconds(10),
        notificationStatusProvider: @escaping @Sendable () async -> MyspaceNotificationStatus = {
            await MyspaceReminderService.notificationStatus()
        }
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        self.index = RecoverableJSONFile(
            url: rootURL.appendingPathComponent("thoughts.json"),
            fileManager: fileManager
        )
        self.attachmentsURL = rootURL.appendingPathComponent("Attachments", isDirectory: true)
        self.trashURL = rootURL.appendingPathComponent("Trash", isDirectory: true)
        self.notificationsEnabled = notificationsEnabled
        self.undoWindow = undoWindow
        self.notificationStatusProvider = notificationStatusProvider
        load()
        // Pending when the app quit or crashed: the index no longer lists any
        // of it, so this was the user's delete taking effect.
        try? fileManager.removeItem(at: trashURL)
    }

    var activeReminders: [MyspaceThought] {
        thoughts
            .filter { $0.isReminder && !$0.isReminderCompleted }
            .sorted {
                switch ($0.reminderAt, $1.reminderAt) {
                case let (left?, right?): left < right
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): $0.createdAt > $1.createdAt
                }
            }
    }

    var archivedReminders: [MyspaceThought] {
        thoughts
            .filter { $0.isReminder && $0.isReminderCompleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    nonisolated static func groupThoughtsByDay(
        _ thoughts: [MyspaceThought],
        calendar: Calendar = .current
    ) -> [MyspaceDayGroup] {
        let grouped = Dictionary(grouping: thoughts) {
            calendar.startOfDay(for: $0.createdAt)
        }
        return grouped
            .map { day, thoughts in
                MyspaceDayGroup(
                    day: day,
                    thoughts: thoughts.sorted { $0.createdAt > $1.createdAt }
                )
            }
            .sorted { $0.day > $1.day }
    }

    @discardableResult
    func addThought(
        text: String,
        attachmentURLs: [URL] = [],
        reminderAt: Date? = nil,
        isReminder: Bool? = nil
    ) throws -> MyspaceThought {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachmentURLs.isEmpty else {
            throw MyspaceStoreError.emptyThought
        }
        // A trigger in the past never fires: better to say so now than to
        // list a reminder that will stay quiet.
        if let reminderAt, reminderAt <= .now {
            throw MyspaceStoreError.reminderTimeHasPassed
        }

        let thoughtID = UUID()
        let importedAttachments = try importAttachments(attachmentURLs, thoughtID: thoughtID)
        return try insertThought(
            id: thoughtID,
            text: trimmedText,
            attachments: importedAttachments,
            reminderAt: reminderAt,
            isReminder: isReminder ?? (reminderAt != nil)
        )
    }

    /// Off the main thread: a drop can be gigabytes, and the copy held the
    /// notch and every other surface until it finished.
    @discardableResult
    func holdFiles(_ urls: [URL]) async throws -> MyspaceThought {
        guard !urls.isEmpty else { throw MyspaceStoreError.emptyThought }

        let thoughtID = UUID()
        let directory = attachmentDirectory(for: thoughtID)
        do {
            let attachments = try await Task.detached(priority: .userInitiated) {
                try Self.copyAttachments(urls, into: directory)
            }.value
            return try insertThought(id: thoughtID, text: "", attachments: attachments, reminderAt: nil, isReminder: false)
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func insertThought(
        id: UUID,
        text: String,
        attachments: [MyspaceAttachment],
        reminderAt: Date?,
        isReminder: Bool
    ) throws -> MyspaceThought {
        let thought = MyspaceThought(
            id: id,
            text: text,
            createdAt: .now,
            isReminder: isReminder,
            reminderAt: reminderAt,
            isReminderCompleted: false,
            attachments: attachments
        )

        thoughts.insert(thought, at: 0)
        do {
            try persist()
            lastErrorMessage = nil
            if notificationsEnabled, let reminderAt {
                MyspaceReminderService.schedule(thought: thought, at: reminderAt)
            }
            return thought
        } catch {
            thoughts.removeAll { $0.id == id }
            try? fileManager.removeItem(at: attachmentDirectory(for: id))
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: Deleting

    /// Takes the thought out now; its attachments go for good once the undo
    /// window closes.
    func deleteThought(id: UUID) {
        guard let index = thoughts.firstIndex(where: { $0.id == id }) else { return }
        let removed = thoughts.remove(at: index)
        do {
            try persist()
            lastErrorMessage = nil
        } catch {
            thoughts.insert(removed, at: index)
            lastErrorMessage = error.localizedDescription
            return
        }

        if notificationsEnabled {
            MyspaceReminderService.cancel(thoughtID: id)
        }
        beginUndoWindow(for: .thought(removed), files: attachmentDirectory(for: id))
    }

    /// Removes one file from a thought. A thought with nothing left in it
    /// would be invisible (text-less thoughts only show their files), so
    /// taking its last file takes the thought.
    func deleteAttachment(id attachmentID: UUID, fromThought thoughtID: UUID) {
        guard let thoughtIndex = thoughts.firstIndex(where: { $0.id == thoughtID }),
              let index = thoughts[thoughtIndex].attachments.firstIndex(where: { $0.id == attachmentID }) else {
            return
        }

        let thought = thoughts[thoughtIndex]
        if thought.text.isEmpty, thought.attachments.count == 1, !thought.isReminder {
            deleteThought(id: thoughtID)
            return
        }

        let removed = thoughts[thoughtIndex].attachments.remove(at: index)
        do {
            try persist()
            lastErrorMessage = nil
        } catch {
            thoughts[thoughtIndex].attachments.insert(removed, at: index)
            lastErrorMessage = error.localizedDescription
            return
        }

        beginUndoWindow(
            for: .attachment(removed, thoughtID: thoughtID, index: index),
            files: attachmentURL(for: removed, thoughtID: thoughtID)
        )
    }

    /// Puts the last delete back, files and reminder included.
    func undoDeletion() {
        guard let deletion = pendingDeletion else { return }
        undoTask?.cancel()
        undoTask = nil
        pendingDeletion = nil

        let trashed = trashFolder(for: deletion.id)
        switch deletion.item {
        case let .thought(thought):
            restore(from: trashed, to: attachmentDirectory(for: thought.id))
            let position = thoughts.firstIndex { $0.createdAt < thought.createdAt } ?? thoughts.count
            thoughts.insert(thought, at: position)
            persistRestoring { self.thoughts.removeAll { $0.id == thought.id } }
            if notificationsEnabled, !thought.isReminderCompleted,
               let reminderAt = thought.reminderAt, reminderAt > .now {
                MyspaceReminderService.schedule(thought: thought, at: reminderAt)
            }
        case let .attachment(attachment, thoughtID, index):
            guard let thoughtIndex = thoughts.firstIndex(where: { $0.id == thoughtID }) else { break }
            restore(from: trashed, to: attachmentURL(for: attachment, thoughtID: thoughtID))
            let position = min(index, thoughts[thoughtIndex].attachments.count)
            thoughts[thoughtIndex].attachments.insert(attachment, at: position)
            persistRestoring { self.thoughts[thoughtIndex].attachments.removeAll { $0.id == attachment.id } }
        }
        try? fileManager.removeItem(at: trashed)
    }

    private func persistRestoring(rollback: () -> Void) {
        do {
            try persist()
            lastErrorMessage = nil
        } catch {
            rollback()
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Only one delete is undoable at a time: the one before it goes for
    /// good now, as it would have a few seconds later.
    private func beginUndoWindow(for item: MyspacePendingDeletion.Item, files: URL) {
        finishPendingDeletion()

        let deletion = MyspacePendingDeletion(id: UUID(), item: item)
        if fileManager.fileExists(atPath: files.path) {
            let folder = trashFolder(for: deletion.id)
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fileManager.moveItem(at: files, to: folder.appendingPathComponent(Self.trashedItemName))
        }

        pendingDeletion = deletion
        let window = undoWindow
        undoTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: window)
            } catch {
                return
            }
            self?.finishPendingDeletion()
        }
    }

    /// The undo window closed: the delete becomes permanent.
    func finishPendingDeletion() {
        undoTask?.cancel()
        undoTask = nil
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        try? fileManager.removeItem(at: trashFolder(for: deletion.id))
    }

    private static let trashedItemName = "item"

    private func restore(from folder: URL, to destination: URL) {
        let trashed = folder.appendingPathComponent(Self.trashedItemName)
        guard fileManager.fileExists(atPath: trashed.path) else { return }
        try? fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.moveItem(at: trashed, to: destination)
    }

    private func trashFolder(for deletionID: UUID) -> URL {
        trashURL.appendingPathComponent(deletionID.uuidString, isDirectory: true)
    }

    // MARK: Notifications

    /// Read fresh each time: it's changed in System Settings, behind our back.
    func refreshNotificationStatus() async {
        let status = await notificationStatusProvider()
        if status != notificationStatus {
            notificationStatus = status
        }
    }

    /// Timed reminders are waiting on a notification that can't arrive.
    var hasRemindersThatCantAlert: Bool {
        notificationStatus == .off
            && activeReminders.contains { ($0.reminderAt ?? .distantPast) > .now }
    }

    func toggleReminderCompleted(id: UUID) {
        guard let index = thoughts.firstIndex(where: { $0.id == id }) else { return }
        thoughts[index].isReminderCompleted.toggle()

        do {
            try persist()
            let thought = thoughts[index]
            if notificationsEnabled, thought.isReminderCompleted {
                MyspaceReminderService.cancel(thoughtID: id)
            } else if notificationsEnabled, let reminderAt = thought.reminderAt {
                MyspaceReminderService.schedule(thought: thought, at: reminderAt)
            }
            lastErrorMessage = nil
        } catch {
            thoughts[index].isReminderCompleted.toggle()
            lastErrorMessage = error.localizedDescription
        }
    }

    func attachmentURL(for attachment: MyspaceAttachment, thoughtID: UUID) -> URL {
        attachmentDirectory(for: thoughtID)
            .appendingPathComponent(attachment.storedFilename)
    }

    func restorePendingReminders() {
        guard notificationsEnabled else { return }
        for thought in activeReminders {
            guard let reminderAt = thought.reminderAt, reminderAt > .now else { continue }
            MyspaceReminderService.schedule(thought: thought, at: reminderAt)
        }
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
        return applicationSupport
            .appendingPathComponent("NotchTune", isDirectory: true)
            .appendingPathComponent("Myspace", isDirectory: true)
    }

    private func load() {
        do {
            try fileManager.createDirectory(
                at: attachmentsURL,
                withIntermediateDirectories: true
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        let outcome = index.load(
            decode: { data in
                RecoverableJSONFile.survivors(
                    of: try JSONDecoder.myspace.decode([LossyElement<MyspaceThought>].self, from: data)
                )
            },
            merge: { survivors, backup in
                let kept = Set(survivors.map(\.id))
                return survivors + backup.filter { !kept.contains($0.id) }
            }
        )

        switch outcome {
        case .missing:
            break
        case let .intact(loaded):
            thoughts = loaded.sorted { $0.createdAt > $1.createdAt }
        case let .recovered(loaded):
            thoughts = loaded.sorted { $0.createdAt > $1.createdAt }
            // The damaged file is gone from its place: without this the next
            // launch would find no index at all.
            try? persist()
            reportLoadProblem("Some of your Myspace notes were damaged. NotchTune saved what it could and kept the old file.")
        case .lost:
            reportLoadProblem("Your Myspace notes couldn't be read. NotchTune kept the damaged file beside them.")
        }
    }

    private func reportLoadProblem(_ message: String) {
        loadProblem = message
        lastErrorMessage = message
    }

    private func persist() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try index.write(JSONEncoder.myspace.encode(thoughts))
    }

    private func importAttachments(_ urls: [URL], thoughtID: UUID) throws -> [MyspaceAttachment] {
        guard !urls.isEmpty else { return [] }
        return try Self.copyAttachments(urls, into: attachmentDirectory(for: thoughtID))
    }

    /// All or nothing: a failure partway leaves no copied files behind, since
    /// no thought will ever point at them.
    private nonisolated static func copyAttachments(_ urls: [URL], into directory: URL) throws -> [MyspaceAttachment] {
        let fileManager = FileManager()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            return try urls.map { sourceURL in
                let accessed = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed { sourceURL.stopAccessingSecurityScopedResource() }
                }

                let originalFilename = sourceURL.lastPathComponent
                let storedFilename = "\(UUID().uuidString)-\(originalFilename)"
                let destinationURL = directory.appendingPathComponent(storedFilename)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return MyspaceAttachment(
                    id: UUID(),
                    originalFilename: originalFilename,
                    storedFilename: storedFilename
                )
            }
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private func attachmentDirectory(for thoughtID: UUID) -> URL {
        attachmentsURL.appendingPathComponent(thoughtID.uuidString, isDirectory: true)
    }
}

// MARK: - Harness

extension MyspaceStore {
    /// The store for this launch. A harness run never reads or writes the
    /// user's own Myspace: it gets a store in a fresh temporary folder that
    /// schedules no notifications, and a marketing capture
    /// (`NOTCHTUNE_HARNESS_SHOWCASE=1`) a few made-up thoughts and reminders,
    /// plus the files in `NOTCHTUNE_HARNESS_MYSPACE_FILES=<path>:<path>`.
    /// `NOTCHTUNE_HARNESS_NOTIFICATIONS=off` reports notifications as refused;
    /// `NOTCHTUNE_HARNESS_MYSPACE_UNDO=1` starts with a delete to take back.
    static func forLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) -> MyspaceStore {
        guard environment["NOTCHTUNE_HARNESS_SCENARIO"] != nil else { return MyspaceStore() }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchtune-harness-myspace-\(UUID().uuidString)", isDirectory: true)
        let notifications: MyspaceNotificationStatus =
            environment["NOTCHTUNE_HARNESS_NOTIFICATIONS"] == "off" ? .off : .unavailable
        let store = MyspaceStore(
            rootURL: root,
            notificationsEnabled: false,
            notificationStatusProvider: { notifications }
        )
        if environment["NOTCHTUNE_HARNESS_SHOWCASE"] == "1" {
            let files = (environment["NOTCHTUNE_HARNESS_MYSPACE_FILES"] ?? "")
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0)) }
            store.seedShowcase(files: files)
            if environment["NOTCHTUNE_HARNESS_MYSPACE_UNDO"] == "1",
               let thought = store.thoughts.first(where: { !$0.isReminder }) {
                store.deleteThought(id: thought.id)
            }
        }
        return store
    }

    private func seedShowcase(files: [URL], now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func at(day: Int = 0, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today) ?? now
        }
        func thought(_ text: String, _ createdAt: Date, remindAt: Date? = nil, done: Bool = false) -> MyspaceThought {
            MyspaceThought(
                id: UUID(), text: text, createdAt: createdAt,
                isReminder: remindAt != nil, reminderAt: remindAt,
                isReminderCompleted: done, attachments: []
            )
        }

        var seeded: [MyspaceThought] = files.enumerated().compactMap { index, file in
            let id = UUID()
            guard let attachments = try? importAttachments([file], thoughtID: id) else { return nil }
            return MyspaceThought(
                id: id, text: "", createdAt: at(9, 12 + index * 9),
                reminderAt: nil, isReminderCompleted: false, attachments: attachments
            )
        }
        seeded += [
            thought("Checkout feels fast now. Try lazy images on the product grid too.", at(10, 24)),
            thought("Check the staging deploy before standup", at(8, 50), remindAt: at(10, 0)),
            thought("Send the 2.1.5 notes to the beta testers", at(9, 5), remindAt: at(15, 30)),
            thought("Book the onboarding design review", at(day: -1, 16, 40), remindAt: at(day: 1, 9, 30)),
            thought("Rotate the staging API key", at(day: -1, 11, 20), remindAt: at(day: -1, 14, 0), done: true),
        ]
        thoughts = seeded.sorted { $0.createdAt > $1.createdAt }
        try? persist()
    }
}

extension JSONEncoder {
    static var myspace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var myspace: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum MyspaceReminderService {
    static let notificationPrefix = "notchtune.myspace."

    static func schedule(thought: MyspaceThought, at date: Date) {
        guard date > .now, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            // Refused: nothing to schedule, and the Reminders tab says so
            // (`MyspaceStore.hasRemindersThatCantAlert`).
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Reminder"
            content.body = thought.text.isEmpty
                ? "Open your saved attachment."
                : String(thought.text.prefix(160))
            content.sound = .default
            content.userInfo = ["thoughtID": thought.id.uuidString]

            let request = UNNotificationRequest(
                identifier: notificationPrefix + thought.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents(for: date), repeats: false)
            )
            center.add(request)
        }
    }

    /// Pinned to a time zone: floating components fire at that wall-clock
    /// time wherever the Mac is by then, not the moment the list shows.
    static func triggerComponents(for date: Date, calendar: Calendar = .current) -> DateComponents {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.timeZone = calendar.timeZone
        return components
    }

    /// `UNUserNotificationCenter` raises instead of answering in a process
    /// with no bundle (`swift run`, tests).
    static func notificationStatus() async -> MyspaceNotificationStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .denied: return .off
        case .notDetermined: return .notDetermined
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default: return .allowed
        }
    }

    /// System Settings → Notifications.
    @MainActor
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func cancel(thoughtID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationPrefix + thoughtID.uuidString]
        )
    }
}
