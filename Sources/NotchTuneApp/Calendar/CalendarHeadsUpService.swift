import AppKit
import EventKit
import Foundation
import Observation

/// Whether NotchTune may read the user's calendars.
enum CalendarAuthorization: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
    /// This binary has no calendar usage description (a bare `swift run`):
    /// asking would crash it, so the feature explains instead.
    case unavailable
}

/// Where events come from: EventKit in the app, a fixture in the harness, a
/// stub in tests.
@MainActor
protocol CalendarEventSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    func requestAccess() async -> CalendarAuthorization
    func calendars() -> [CalendarSourceInfo]
    /// Events overlapping `start..<end`, from `calendarIDs` (nil: all).
    func events(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [CalendarEventSnapshot]
    /// Called when the calendar database changes.
    var onChange: (() -> Void)? { get set }
}

/// Gives a heads-up before the next meeting and knows when one is under way.
///
/// Opt-in and local: nothing touches EventKit until the user turns the
/// feature on, and then only to read events. There is no polling loop: the
/// service sleeps until the next moment its answer can change (a warning
/// window opening, a meeting starting or ending), refetches when the
/// calendar database changes, after a wake from sleep, and at most every
/// half hour as a safety net.
@MainActor
@Observable
final class CalendarHeadsUpService {
    static let enabledDefaultsKey = "calendar.headsUp.enabled"
    static let leadTimeDefaultsKey = "calendar.headsUp.leadMinutes"
    static let calendarIDsDefaultsKey = "calendar.headsUp.calendarIDs"
    static let quietDefaultsKey = "calendar.quietDuringMeetings"

    /// How far back and ahead each fetch looks: wide enough for a meeting in
    /// progress and the rest of the day, bounded so a fetch stays cheap.
    static let fetchLookBehind: TimeInterval = 12 * 60 * 60
    static let fetchLookAhead: TimeInterval = 24 * 60 * 60
    /// Refetch at least this often, whatever the calendar says.
    static let refetchInterval: TimeInterval = 30 * 60

    // MARK: Settings

    private(set) var isEnabled: Bool
    var leadTime: CalendarLeadTime {
        didSet {
            guard leadTime != oldValue else { return }
            if persists { defaults.set(leadTime.rawValue, forKey: Self.leadTimeDefaultsKey) }
            recompute()
        }
    }
    var quietDuringMeetings: Bool {
        didSet {
            guard quietDuringMeetings != oldValue else { return }
            if persists { defaults.set(quietDuringMeetings, forKey: Self.quietDefaultsKey) }
        }
    }
    /// The calendars to read; nil means every calendar (the default).
    var selectedCalendarIDs: Set<String>? {
        didSet {
            guard selectedCalendarIDs != oldValue else { return }
            if persists {
                if let selectedCalendarIDs {
                    defaults.set(selectedCalendarIDs.sorted(), forKey: Self.calendarIDsDefaultsKey)
                } else {
                    defaults.removeObject(forKey: Self.calendarIDsDefaultsKey)
                }
            }
            refresh()
        }
    }

    // MARK: State

    private(set) var authorization: CalendarAuthorization
    private(set) var calendars: [CalendarSourceInfo] = []
    /// The meeting the notch is warning about right now.
    private(set) var headsUp: CalendarEventSnapshot?
    /// The next eligible meeting, near or not (Settings shows it).
    private(set) var nextEvent: CalendarEventSnapshot?
    /// A busy meeting is in progress.
    private(set) var isInMeeting = false

    /// Mute NotchTune's sounds and hold non-urgent pop-ups right now.
    var isQuietingNow: Bool {
        isEnabled && quietDuringMeetings && isInMeeting
    }

    @ObservationIgnored private let source: CalendarEventSource
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var events: [CalendarEventSnapshot] = []
    @ObservationIgnored private var dismissedIDs: Set<String> = []
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var systemWakeObserver: NSObjectProtocol?

    init(
        source: CalendarEventSource,
        defaults: UserDefaults = .standard,
        persists: Bool = true,
        forceEnabled: Bool = false,
        clock: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.defaults = defaults
        self.persists = persists
        self.clock = clock
        isEnabled = forceEnabled || defaults.bool(forKey: Self.enabledDefaultsKey)
        leadTime = CalendarLeadTime(rawValue: defaults.integer(forKey: Self.leadTimeDefaultsKey)) ?? .five
        quietDuringMeetings = defaults.bool(forKey: Self.quietDefaultsKey)
        selectedCalendarIDs = (defaults.array(forKey: Self.calendarIDsDefaultsKey) as? [String]).map(Set.init)
        authorization = source.authorization
        source.onChange = { [weak self] in self?.refresh() }
    }

    /// The app's service: EventKit, or the harness fixture when
    /// `NOTCHTUNE_HARNESS_CALENDAR_EVENT` is set.
    static func makeDefault() -> CalendarHeadsUpService {
        if let fixture = CalendarFixtureSource(environment: ProcessInfo.processInfo.environment) {
            return CalendarHeadsUpService(source: fixture, persists: false, forceEnabled: true)
        }
        return CalendarHeadsUpService(source: EventKitCalendarSource())
    }

    /// Picks up where the last launch left off. Never asks for access: that
    /// only happens when the user turns the feature on.
    func start() {
        guard isEnabled else { return }
        observeSystemWake()
        refresh()
    }

    // MARK: User actions

    /// Turns heads-ups on or off; turning on asks for calendar access the
    /// first time.
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if persists { defaults.set(enabled, forKey: Self.enabledDefaultsKey) }
        guard enabled else {
            stop()
            return
        }
        observeSystemWake()
        if source.authorization == .notDetermined {
            authorization = await source.requestAccess()
        }
        refresh()
    }

    /// Asks again (from Settings) when access is still undecided.
    func requestAccess() async {
        authorization = await source.requestAccess()
        refresh()
    }

    func dismissHeadsUp() {
        guard let headsUp else { return }
        dismissedIDs.insert(headsUp.id)
        recompute()
    }

    func joinHeadsUp() {
        guard let url = headsUp?.joinURL else { return }
        NSWorkspace.shared.open(url)
        dismissHeadsUp()
    }

    func isCalendarSelected(_ id: String) -> Bool {
        selectedCalendarIDs?.contains(id) ?? true
    }

    func setCalendar(_ id: String, selected: Bool) {
        var ids = selectedCalendarIDs ?? Set(calendars.map(\.id))
        if selected { ids.insert(id) } else { ids.remove(id) }
        // Everything ticked is the same as "all": keep following new calendars.
        selectedCalendarIDs = ids == Set(calendars.map(\.id)) ? nil : ids
    }

    // MARK: Refresh

    /// Refetches the bounded event window and recomputes.
    func refresh() {
        authorization = source.authorization
        guard isEnabled, authorization == .granted else {
            clearState()
            return
        }
        let now = clock()
        calendars = source.calendars()
        events = source.events(
            from: now.addingTimeInterval(-Self.fetchLookBehind),
            to: now.addingTimeInterval(Self.fetchLookAhead),
            calendarIDs: selectedCalendarIDs
        )
        lastFetch = now
        recompute()
    }

    /// Re-derives the heads-up and meeting state from the cached events and
    /// schedules the next wake.
    func recompute() {
        guard isEnabled, authorization == .granted else {
            clearState()
            return
        }
        let now = clock()
        let lead = leadTime.seconds
        dismissedIDs = dismissedIDs.filter { id in events.contains { $0.id == id && $0.end > now } }
        let newHeadsUp = CalendarHeadsUpResolver.headsUp(events: events, now: now, leadTime: lead, dismissedIDs: dismissedIDs)
        if newHeadsUp != headsUp { headsUp = newHeadsUp }
        let newNext = events
            .filter { CalendarHeadsUpResolver.isEligible($0) && $0.end > now }
            .min { $0.start < $1.start }
        if newNext != nextEvent { nextEvent = newNext }
        let inMeeting = CalendarHeadsUpResolver.isInMeeting(events: events, now: now)
        if inMeeting != isInMeeting { isInMeeting = inMeeting }
        scheduleWake(now: now, lead: lead)
    }

    private func scheduleWake(now: Date, lead: TimeInterval) {
        wakeTask?.cancel()
        let refetchAt = (lastFetch ?? now).addingTimeInterval(Self.refetchInterval)
        let changeAt = CalendarHeadsUpResolver.nextChange(events: events, now: now, leadTime: lead)
        let wakeAt = min(refetchAt, changeAt ?? refetchAt)
        // Land just past the transition; never spin.
        let delay = max(1, wakeAt.timeIntervalSince(now) + 0.5)
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            if let lastFetch = self.lastFetch,
               self.clock().timeIntervalSince(lastFetch) >= Self.refetchInterval {
                self.refresh()
            } else {
                self.recompute()
            }
        }
    }

    private func stop() {
        wakeTask?.cancel()
        wakeTask = nil
        if let systemWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(systemWakeObserver)
            self.systemWakeObserver = nil
        }
        clearState()
    }

    private func clearState() {
        wakeTask?.cancel()
        wakeTask = nil
        events = []
        lastFetch = nil
        if headsUp != nil { headsUp = nil }
        if nextEvent != nil { nextEvent = nil }
        if isInMeeting { isInMeeting = false }
    }

    /// The clock jumps across sleep: refetch on wake.
    private func observeSystemWake() {
        guard systemWakeObserver == nil else { return }
        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}

// MARK: - EventKit

/// The real calendars, read-only. The store is only created once the
/// feature is on, so a user who never enables it never touches EventKit.
@MainActor
final class EventKitCalendarSource: CalendarEventSource {
    var onChange: (() -> Void)?

    private var store: EKEventStore?
    private var changeObserver: NSObjectProtocol?

    private static var hasUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }

    var authorization: CalendarAuthorization {
        guard Self.hasUsageDescription else { return .unavailable }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .granted
        case .restricted: return .restricted
        // Write-only access can't read events.
        case .denied, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    func requestAccess() async -> CalendarAuthorization {
        guard Self.hasUsageDescription else { return .unavailable }
        let store = eventStore()
        _ = try? await store.requestFullAccessToEvents()
        return authorization
    }

    func calendars() -> [CalendarSourceInfo] {
        guard authorization == .granted else { return [] }
        return eventStore().calendars(for: .event)
            .map { CalendarSourceInfo(id: $0.calendarIdentifier, title: $0.title, color: Self.color(of: $0)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [CalendarEventSnapshot] {
        guard authorization == .granted else { return [] }
        let store = eventStore()
        var calendars: [EKCalendar]?
        if let calendarIDs {
            calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            if calendars?.isEmpty == true { return [] }
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).map(Self.snapshot)
    }

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let store = EKEventStore()
        self.store = store
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        return store
    }

    private static func snapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        let start = event.startDate ?? .distantPast
        let declined = event.status == .canceled
            || event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        return CalendarEventSnapshot(
            id: "\(event.calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))",
            title: (event.title?.isEmpty == false ? event.title : nil) ?? "Untitled meeting",
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            isDeclined: declined,
            isBusy: event.availability != .free,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            calendarTitle: event.calendar?.title ?? "",
            calendarColor: event.calendar.flatMap(color(of:)),
            joinURL: MeetingLinkExtractor.joinURL(url: event.url, location: event.location, notes: event.notes)
        )
    }

    private static func color(of calendar: EKCalendar) -> CalendarColor? {
        guard let rgb = calendar.color?.usingColorSpace(.sRGB) else { return nil }
        return CalendarColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

// MARK: - Harness fixture

/// One made-up meeting for headless captures:
/// `NOTCHTUNE_HARNESS_CALENDAR_EVENT="Standup|5|https://meet.google.com/abc-defg-hij"`
/// (title | minutes until it starts, negative = already started | optional
/// join link | optional length in minutes, default 30).
@MainActor
final class CalendarFixtureSource: CalendarEventSource {
    var onChange: (() -> Void)?
    let authorization: CalendarAuthorization = .granted
    private let event: CalendarEventSnapshot

    private static let fixtureCalendar = CalendarSourceInfo(
        id: "fixture-work",
        title: "Work",
        color: CalendarColor(red: 0.27, green: 0.62, blue: 1.0)
    )

    init?(environment: [String: String], now: Date = .now) {
        guard let spec = environment["NOTCHTUNE_HARNESS_CALENDAR_EVENT"], !spec.isEmpty else { return nil }
        let parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let title = parts.first.flatMap { $0.isEmpty ? nil : $0 } ?? "Standup"
        let minutes = parts.count > 1 ? Double(parts[1]) ?? 5 : 5
        let url = parts.count > 2 ? URL(string: parts[2]) : nil
        let length = parts.count > 3 ? Double(parts[3]) ?? 30 : 30
        let start = now.addingTimeInterval(minutes * 60)
        event = CalendarEventSnapshot(
            id: "fixture@\(Int(start.timeIntervalSince1970))",
            title: title,
            start: start,
            end: start.addingTimeInterval(length * 60),
            calendarID: Self.fixtureCalendar.id,
            calendarTitle: Self.fixtureCalendar.title,
            calendarColor: Self.fixtureCalendar.color,
            joinURL: url.flatMap { MeetingLinkExtractor.isMeetingLink($0) ? $0 : nil }
        )
    }

    func requestAccess() async -> CalendarAuthorization { .granted }

    func calendars() -> [CalendarSourceInfo] { [Self.fixtureCalendar] }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [CalendarEventSnapshot] {
        guard calendarIDs?.contains(event.calendarID) ?? true,
              event.end > start, event.start < end else { return [] }
        return [event]
    }
}
