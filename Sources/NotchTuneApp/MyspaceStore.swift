import Foundation
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

struct MyspaceDayGroup: Equatable, Identifiable, Sendable {
    let day: Date
    let thoughts: [MyspaceThought]

    var id: Date { day }
}

enum MyspaceStoreError: LocalizedError {
    case emptyThought

    var errorDescription: String? {
        switch self {
        case .emptyThought:
            "Add a thought or at least one attachment."
        }
    }
}

@MainActor
@Observable
final class MyspaceStore {
    private(set) var thoughts: [MyspaceThought] = []
    private(set) var lastErrorMessage: String?

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let rootURL: URL
    @ObservationIgnored private let indexURL: URL
    @ObservationIgnored private let attachmentsURL: URL
    @ObservationIgnored private let notificationsEnabled: Bool

    init(
        rootURL: URL = MyspaceStore.defaultRootURL(),
        fileManager: FileManager = .default,
        notificationsEnabled: Bool = true
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        self.indexURL = rootURL.appendingPathComponent("thoughts.json")
        self.attachmentsURL = rootURL.appendingPathComponent("Attachments", isDirectory: true)
        self.notificationsEnabled = notificationsEnabled
        load()
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

        let thoughtID = UUID()
        let importedAttachments = try importAttachments(attachmentURLs, thoughtID: thoughtID)
        let thought = MyspaceThought(
            id: thoughtID,
            text: trimmedText,
            createdAt: .now,
            isReminder: isReminder ?? (reminderAt != nil),
            reminderAt: reminderAt,
            isReminderCompleted: false,
            attachments: importedAttachments
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
            thoughts.removeAll { $0.id == thoughtID }
            try? fileManager.removeItem(at: attachmentDirectory(for: thoughtID))
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func holdFiles(_ urls: [URL]) throws -> MyspaceThought {
        try addThought(text: "", attachmentURLs: urls)
    }

    func deleteThought(id: UUID) {
        guard let index = thoughts.firstIndex(where: { $0.id == id }) else { return }
        let removed = thoughts.remove(at: index)
        do {
            try persist()
            try? fileManager.removeItem(at: attachmentDirectory(for: id))
            if notificationsEnabled {
                MyspaceReminderService.cancel(thoughtID: id)
            }
            lastErrorMessage = nil
        } catch {
            thoughts.insert(removed, at: index)
            lastErrorMessage = error.localizedDescription
        }
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
            guard fileManager.fileExists(atPath: indexURL.path) else { return }
            let data = try Data(contentsOf: indexURL)
            thoughts = try JSONDecoder.myspace.decode([MyspaceThought].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persist() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.myspace.encode(thoughts)
        try data.write(to: indexURL, options: .atomic)
    }

    private func importAttachments(_ urls: [URL], thoughtID: UUID) throws -> [MyspaceAttachment] {
        guard !urls.isEmpty else { return [] }
        let destinationDirectory = attachmentDirectory(for: thoughtID)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        return try urls.map { sourceURL in
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }

            let originalFilename = sourceURL.lastPathComponent
            let storedFilename = "\(UUID().uuidString)-\(originalFilename)"
            let destinationURL = destinationDirectory.appendingPathComponent(storedFilename)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return MyspaceAttachment(
                id: UUID(),
                originalFilename: originalFilename,
                storedFilename: storedFilename
            )
        }
    }

    private func attachmentDirectory(for thoughtID: UUID) -> URL {
        attachmentsURL.appendingPathComponent(thoughtID.uuidString, isDirectory: true)
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
        guard date > .now else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Reminder"
            content.body = thought.text.isEmpty
                ? "Open your saved attachment."
                : String(thought.text.prefix(160))
            content.sound = .default
            content.userInfo = ["thoughtID": thought.id.uuidString]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            let request = UNNotificationRequest(
                identifier: notificationPrefix + thought.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            center.add(request)
        }
    }

    static func cancel(thoughtID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationPrefix + thoughtID.uuidString]
        )
    }
}
