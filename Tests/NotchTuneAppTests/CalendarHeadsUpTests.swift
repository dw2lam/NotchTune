import Foundation
import Testing
@testable import NotchTuneApp
import NotchTuneCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func event(
    _ id: String,
    startsIn minutes: Double,
    length: Double = 30,
    allDay: Bool = false,
    declined: Bool = false,
    busy: Bool = true,
    join: String? = nil
) -> CalendarEventSnapshot {
    let start = now.addingTimeInterval(minutes * 60)
    return CalendarEventSnapshot(
        id: id,
        title: id,
        start: start,
        end: start.addingTimeInterval(length * 60),
        isAllDay: allDay,
        isDeclined: declined,
        isBusy: busy,
        calendarID: "work",
        joinURL: join.flatMap(URL.init(string:))
    )
}

struct CalendarHeadsUpResolverTests {
    private let lead = CalendarLeadTime.five.seconds

    @Test
    func warnsOnlyInsideTheLeadWindow() {
        #expect(CalendarHeadsUpResolver.headsUp(events: [event("a", startsIn: 6)], now: now, leadTime: lead) == nil)
        #expect(CalendarHeadsUpResolver.headsUp(events: [event("a", startsIn: 5)], now: now, leadTime: lead)?.id == "a")
        #expect(CalendarHeadsUpResolver.headsUp(events: [event("a", startsIn: 1)], now: now, leadTime: lead)?.id == "a")
    }

    @Test
    func keepsAStartedMeetingForTheGraceThenLetsGo() {
        #expect(CalendarHeadsUpResolver.headsUp(events: [event("a", startsIn: -4)], now: now, leadTime: lead)?.id == "a")
        #expect(CalendarHeadsUpResolver.headsUp(events: [event("a", startsIn: -6)], now: now, leadTime: lead) == nil)
        // A meeting that ended inside the grace is over.
        #expect(CalendarHeadsUpResolver.headsUp(events: [event("a", startsIn: -3, length: 2)], now: now, leadTime: lead) == nil)
    }

    @Test
    func skipsAllDayDeclinedPastAndDismissedEvents() {
        let events = [
            event("allDay", startsIn: 2, allDay: true),
            event("declined", startsIn: 2, declined: true),
            event("past", startsIn: -90),
            event("dismissed", startsIn: 3),
        ]
        #expect(CalendarHeadsUpResolver.headsUp(events: events, now: now, leadTime: lead, dismissedIDs: ["dismissed"]) == nil)
    }

    @Test
    func overlappingMeetingsWarnAboutTheEarliest() {
        let events = [event("later", startsIn: 4), event("sooner", startsIn: 2), event("same", startsIn: 2)]
        // Equal starts break ties by id, so the pick is stable.
        #expect(CalendarHeadsUpResolver.headsUp(events: events, now: now, leadTime: lead)?.id == "same")
    }

    @Test
    func inAMeetingOnlyWhileABusyAcceptedTimedEventRuns() {
        #expect(CalendarHeadsUpResolver.isInMeeting(events: [event("a", startsIn: -10)], now: now))
        #expect(!CalendarHeadsUpResolver.isInMeeting(events: [event("a", startsIn: 2)], now: now))
        #expect(!CalendarHeadsUpResolver.isInMeeting(events: [event("a", startsIn: -10, busy: false)], now: now))
        #expect(!CalendarHeadsUpResolver.isInMeeting(events: [event("a", startsIn: -10, allDay: true)], now: now))
        #expect(!CalendarHeadsUpResolver.isInMeeting(events: [event("a", startsIn: -10, declined: true)], now: now))
        #expect(!CalendarHeadsUpResolver.isInMeeting(events: [event("a", startsIn: -40)], now: now))
    }

    @Test
    func wakesAtTheNextTransition() {
        let next = CalendarHeadsUpResolver.nextChange(events: [event("a", startsIn: 20)], now: now, leadTime: lead)
        #expect(next == now.addingTimeInterval(15 * 60))
        let inside = CalendarHeadsUpResolver.nextChange(events: [event("a", startsIn: 3)], now: now, leadTime: lead)
        #expect(inside == now.addingTimeInterval(3 * 60))
        #expect(CalendarHeadsUpResolver.nextChange(events: [event("a", startsIn: 2, allDay: true)], now: now, leadTime: lead) == nil)
    }

    @Test
    func countsDownInWholeMinutes() {
        #expect(CalendarHeadsUpResolver.minutesUntil(now.addingTimeInterval(4 * 60 + 1), now: now) == 5)
        #expect(CalendarHeadsUpResolver.minutesUntil(now.addingTimeInterval(60), now: now) == 1)
        #expect(CalendarHeadsUpResolver.minutesUntil(now.addingTimeInterval(-30), now: now) == 0)
        #expect(IslandLiveActivity.meetingCountdownText(start: now.addingTimeInterval(300), now: now) == "5 min")
        #expect(IslandLiveActivity.meetingCountdownText(start: now, now: now) == "now")
    }
}

struct MeetingLinkExtractorTests {
    @Test
    func findsCallLinksInTheUrlLocationOrNotes() {
        let zoom = MeetingLinkExtractor.joinURL(url: URL(string: "https://us02web.zoom.us/j/8123456789?pwd=x"), location: nil, notes: nil)
        #expect(zoom?.host == "us02web.zoom.us")

        let meet = MeetingLinkExtractor.joinURL(
            url: nil,
            location: "Room 4",
            notes: "Agenda attached.\nJoin: https://meet.google.com/abc-defg-hij thanks"
        )
        #expect(meet?.absoluteString == "https://meet.google.com/abc-defg-hij")

        let teams = MeetingLinkExtractor.joinURL(
            url: nil,
            location: "Microsoft Teams Meeting https://teams.microsoft.com/l/meetup-join/19%3ameeting",
            notes: nil
        )
        #expect(teams?.host == "teams.microsoft.com")

        let facetime = MeetingLinkExtractor.joinURL(url: nil, location: nil, notes: "https://facetime.apple.com/join#v=1&p=abc")
        #expect(facetime?.host == "facetime.apple.com")
    }

    @Test
    func ignoresOrdinaryLinksAndBareHomepages() {
        #expect(MeetingLinkExtractor.joinURL(url: URL(string: "https://example.com/meeting"), location: nil, notes: nil) == nil)
        #expect(MeetingLinkExtractor.joinURL(url: URL(string: "https://zoom.us"), location: nil, notes: nil) == nil)
        #expect(MeetingLinkExtractor.joinURL(url: URL(string: "https://notzoom.us.evil.com/j/1"), location: nil, notes: nil) == nil)
        #expect(MeetingLinkExtractor.joinURL(url: nil, location: "Cafe on 5th", notes: "bring slides") == nil)
    }

    @Test
    func theEventUrlWinsOverTheNotes() {
        let url = MeetingLinkExtractor.joinURL(
            url: URL(string: "https://acme.webex.com/meet/jane"),
            location: nil,
            notes: "https://meet.google.com/zzz-zzzz-zzz"
        )
        #expect(url?.host == "acme.webex.com")
    }
}

@MainActor
private final class StubCalendarSource: CalendarEventSource {
    var onChange: (() -> Void)?
    var authorization: CalendarAuthorization
    var grantOnRequest: Bool
    var stubEvents: [CalendarEventSnapshot]
    var stubCalendars = [
        CalendarSourceInfo(id: "work", title: "Work", color: nil),
        CalendarSourceInfo(id: "home", title: "Home", color: nil),
    ]
    private(set) var requestCount = 0
    private(set) var lastCalendarIDs: Set<String>??

    init(authorization: CalendarAuthorization, grantOnRequest: Bool = true, events: [CalendarEventSnapshot] = []) {
        self.authorization = authorization
        self.grantOnRequest = grantOnRequest
        self.stubEvents = events
    }

    func requestAccess() async -> CalendarAuthorization {
        requestCount += 1
        authorization = grantOnRequest ? .granted : .denied
        return authorization
    }

    func calendars() -> [CalendarSourceInfo] { stubCalendars }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>?) -> [CalendarEventSnapshot] {
        lastCalendarIDs = .some(calendarIDs)
        return stubEvents.filter { calendarIDs?.contains($0.calendarID) ?? true }
    }
}

@MainActor
struct CalendarHeadsUpServiceTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "CalendarHeadsUpServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func staysOffAndNeverAsksUntilTurnedOn() async {
        let source = StubCalendarSource(authorization: .notDetermined, events: [event("a", startsIn: 2)])
        let service = CalendarHeadsUpService(source: source, defaults: makeDefaults(), clock: { now })
        service.start()
        #expect(!service.isEnabled)
        #expect(source.requestCount == 0)
        #expect(service.headsUp == nil)

        await service.setEnabled(true)
        #expect(source.requestCount == 1)
        #expect(service.authorization == .granted)
        #expect(service.headsUp?.id == "a")
    }

    @Test
    func aDeniedRequestLeavesNothingShowing() async {
        let source = StubCalendarSource(authorization: .notDetermined, grantOnRequest: false, events: [event("a", startsIn: 2)])
        let service = CalendarHeadsUpService(source: source, defaults: makeDefaults(), clock: { now })
        await service.setEnabled(true)
        #expect(service.authorization == .denied)
        #expect(service.headsUp == nil)
        #expect(!service.isInMeeting)
    }

    @Test
    func quietsOnlyWhenAskedAndInAMeeting() async {
        let source = StubCalendarSource(authorization: .granted, events: [event("call", startsIn: -10)])
        let service = CalendarHeadsUpService(source: source, defaults: makeDefaults(), clock: { now })
        await service.setEnabled(true)
        #expect(service.isInMeeting)
        #expect(!service.isQuietingNow)

        service.quietDuringMeetings = true
        #expect(service.isQuietingNow)

        source.stubEvents = [event("call", startsIn: -10, busy: false)]
        service.refresh()
        #expect(!service.isQuietingNow)

        await service.setEnabled(false)
        #expect(!service.isQuietingNow)
        #expect(service.headsUp == nil)
    }

    @Test
    func dismissingHidesThatMeetingOnly() async {
        let source = StubCalendarSource(authorization: .granted, events: [event("a", startsIn: 1), event("b", startsIn: 4)])
        let service = CalendarHeadsUpService(source: source, defaults: makeDefaults(), clock: { now })
        await service.setEnabled(true)
        #expect(service.headsUp?.id == "a")
        service.dismissHeadsUp()
        #expect(service.headsUp?.id == "b")
    }

    @Test
    func settingsPersistAndCalendarChoiceNarrowsTheFetch() async {
        let defaults = makeDefaults()
        let source = StubCalendarSource(authorization: .granted, events: [event("a", startsIn: 2)])
        let service = CalendarHeadsUpService(source: source, defaults: defaults, clock: { now })
        await service.setEnabled(true)
        service.leadTime = .ten
        service.quietDuringMeetings = true
        service.setCalendar("home", selected: false)
        #expect(service.selectedCalendarIDs == ["work"])
        #expect(source.lastCalendarIDs == .some(["work"]))

        // Ticking everything again means "all", so new calendars follow.
        service.setCalendar("home", selected: true)
        #expect(service.selectedCalendarIDs == nil)

        let reloaded = CalendarHeadsUpService(source: source, defaults: defaults, clock: { now })
        #expect(reloaded.isEnabled)
        #expect(reloaded.leadTime == .ten)
        #expect(reloaded.quietDuringMeetings)
    }

    @Test
    func theHarnessFixtureIsAJoinableMeetingMinutesAway() {
        let fixture = CalendarFixtureSource(
            environment: ["NOTCHTUNE_HARNESS_CALENDAR_EVENT": "Design review|5|https://meet.google.com/abc-defg-hij"],
            now: now
        )
        let events = fixture?.events(from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(3600), calendarIDs: nil)
        #expect(events?.first?.title == "Design review")
        #expect(events?.first?.start == now.addingTimeInterval(300))
        #expect(events?.first?.joinURL?.host == "meet.google.com")
        #expect(CalendarFixtureSource(environment: [:]) == nil)
    }
}

struct MeetingLiveActivityTests {
    private func session(_ id: String, phase: SessionPhase) -> AgentSession {
        AgentSession(
            id: id, title: "Codex · \(id)", tool: .codex, origin: .live,
            attachmentState: .attached, phase: phase, summary: phase.displayName, updatedAt: now
        )
    }

    private let meeting = event("Standup", startsIn: 3, join: "https://meet.google.com/abc-defg-hij")

    @Test
    func needsYouOutranksTheMeeting() {
        let waiting = [session("w", phase: .waitingForApproval)]
        for mode in IslandLiveActivityMode.allCases {
            let activity = IslandLiveActivity.resolve(
                mode: mode, sessions: waiting, finishedPeekSessionID: nil,
                runningSince: [:], attentionSince: [:], meeting: meeting
            )
            #expect(activity?.kind != .meeting, "\(mode)")
        }
    }

    @Test
    func theMeetingOutranksWorkAndShowsEvenWithLiveActivitiesOff() {
        let working = [session("r", phase: .running)]
        let active = IslandLiveActivity.resolve(
            mode: .active, sessions: working, finishedPeekSessionID: nil,
            runningSince: [:], attentionSince: [:], meeting: meeting
        )
        #expect(active?.kind == .meeting)
        #expect(active?.title == "Standup")
        #expect(active?.otherCount == 1)
        #expect(active?.tool == nil)

        let off = IslandLiveActivity.resolve(
            mode: .off, sessions: [], finishedPeekSessionID: nil,
            runningSince: [:], attentionSince: [:], meeting: meeting
        )
        #expect(off?.kind == .meeting)
    }

    @Test
    func aFreshFinishStillGetsItsPeek() {
        let finished = [session("f", phase: .completed)]
        let activity = IslandLiveActivity.resolve(
            mode: .events, sessions: finished, finishedPeekSessionID: "f",
            runningSince: [:], attentionSince: [:], meeting: meeting
        )
        #expect(activity?.kind == .finished)
    }

    @Test
    func theJoinMarkWidensTheRightWing() {
        let joinable = IslandLiveActivity.meetingActivity(meeting, otherCount: 0)
        var plain = meeting
        plain.joinURL = nil
        #expect(joinable.trailingWidth > IslandLiveActivity.meetingActivity(plain, otherCount: 0).trailingWidth)
    }
}
