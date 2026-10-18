import Foundation

/// One calendar event, copied out of EventKit so everything downstream is a
/// pure, `Sendable` value the resolver and the tests can work with.
struct CalendarEventSnapshot: Equatable, Sendable, Identifiable {
    /// Unique per occurrence: a recurring event's instances share EventKit's
    /// identifier, so the start time is part of the key.
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    /// The user declined the invitation.
    var isDeclined: Bool = false
    /// Marked busy (or tentative / unavailable), not free.
    var isBusy: Bool = true
    var calendarID: String = ""
    var calendarTitle: String = ""
    var calendarColor: CalendarColor? = nil
    /// A Zoom / Meet / Teams / Webex / FaceTime link, if the event has one.
    var joinURL: URL? = nil
}

/// An RGB colour that crosses actor boundaries (an `NSColor` doesn't).
struct CalendarColor: Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

/// A calendar the user can include or leave out of heads-ups.
struct CalendarSourceInfo: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var color: CalendarColor?
}

/// How far ahead NotchTune warns about the next meeting.
enum CalendarLeadTime: Int, CaseIterable, Identifiable, Sendable {
    case two = 2
    case five = 5
    case ten = 10
    case fifteen = 15

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}

/// Which meeting the notch warns about, and whether one is under way. Pure:
/// every decision is a function of the events, the clock and the settings.
enum CalendarHeadsUpResolver {
    /// How long a started meeting keeps its "now" heads-up (with Join) unless
    /// it is dismissed first.
    static let startedGrace: TimeInterval = 5 * 60

    /// Events worth a heads-up: timed, not declined, not over.
    static func isEligible(_ event: CalendarEventSnapshot) -> Bool {
        !event.isAllDay && !event.isDeclined && event.end > event.start
    }

    /// The meeting to warn about at `now`: the earliest eligible event whose
    /// warning window (lead time before its start, through a short grace
    /// after it) contains `now`, skipping dismissed ones.
    static func headsUp(
        events: [CalendarEventSnapshot],
        now: Date,
        leadTime: TimeInterval,
        dismissedIDs: Set<String> = []
    ) -> CalendarEventSnapshot? {
        events
            .filter { event in
                isEligible(event)
                    && !dismissedIDs.contains(event.id)
                    && now >= event.start.addingTimeInterval(-leadTime)
                    && now < min(event.end, event.start.addingTimeInterval(startedGrace))
            }
            .min { lhs, rhs in
                lhs.start != rhs.start ? lhs.start < rhs.start : lhs.id < rhs.id
            }
    }

    /// True while a busy, timed, accepted meeting is in progress.
    static func isInMeeting(events: [CalendarEventSnapshot], now: Date) -> Bool {
        events.contains { event in
            isEligible(event) && event.isBusy && event.start <= now && now < event.end
        }
    }

    /// The next instant the answer to `headsUp` or `isInMeeting` can change:
    /// a warning window opening or closing, a meeting starting or ending.
    static func nextChange(
        events: [CalendarEventSnapshot],
        now: Date,
        leadTime: TimeInterval
    ) -> Date? {
        events
            .filter(isEligible)
            .flatMap { event in
                [
                    event.start.addingTimeInterval(-leadTime),
                    event.start,
                    min(event.end, event.start.addingTimeInterval(startedGrace)),
                    event.end,
                ]
            }
            .filter { $0 > now }
            .min()
    }

    /// Whole minutes until `start`, rounded up ("in 5 min"); 0 once started.
    static func minutesUntil(_ start: Date, now: Date) -> Int {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }
}

/// Finds a video-call link in an event's URL, location or notes.
enum MeetingLinkExtractor {
    /// Hosts (or host suffixes) of the call services NotchTune offers to join.
    private static let hostSuffixes = [
        "zoom.us", "zoom.com", "zoomgov.com",
        "meet.google.com",
        "teams.microsoft.com", "teams.live.com",
        "webex.com",
        "facetime.apple.com",
    ]

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, let link = meetingLink(url) { return link }
        for text in [location, notes].compactMap({ $0 }) where !text.isEmpty {
            if let link = firstMeetingLink(in: text) { return link }
        }
        return nil
    }

    static func isMeetingLink(_ url: URL) -> Bool {
        meetingLink(url) != nil
    }

    /// The link to open for a call, always over https: a plain-http link to
    /// a known call host is upgraded (every one of them serves https), any
    /// other scheme is no meeting.
    static func meetingLink(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else {
            return nil
        }
        guard hostSuffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            return nil
        }
        // A bare marketing page ("zoom.us") is not a meeting.
        guard url.path.count > 1 else { return nil }
        guard scheme == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }

    private static func firstMeetingLink(in text: String) -> URL? {
        guard let detector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let link = meetingLink(url) { return link }
        }
        return nil
    }
}
