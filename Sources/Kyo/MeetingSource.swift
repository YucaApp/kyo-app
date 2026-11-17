import AppKit
import EventKit
import KyoCore

@MainActor
protocol MeetingSource: AnyObject {
    /// Called when the underlying calendar data changes.
    var onChange: (() -> Void)? { get set }
    func requestAccess() async -> Bool
    /// Timed and all-day events, from the calendars not listed in `hiding`.
    func meetings(from: Date, to: Date, hiding: Set<String>) -> [Meeting]
    func calendars() -> [CalendarInfo]
}

struct CalendarInfo: Identifiable {
    let id: String
    let title: String
    /// The account it belongs to, e.g. "iCloud" or a Google address.
    let account: String
    let color: NSColor
}

/// The calendars set up in macOS (iCloud, Google, Exchange…), read through EventKit.
@MainActor
final class CalendarSource: MeetingSource {
    var onChange: (() -> Void)?
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        if granted, observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?() }
            }
        }
        return granted
    }

    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map {
                CalendarInfo(
                    id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "",
                    color: $0.color ?? .gray)
            }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func meetings(from: Date, to: Date, hiding: Set<String>) -> [Meeting] {
        let shown = store.calendars(for: .event).filter { !hiding.contains($0.calendarIdentifier) }
        // An empty list would mean "every calendar" to EventKit.
        guard !shown.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: shown)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled, !declined(event) else { return nil }
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let standing = standing(in: event)
            // The id is the event's own, shared by every calendar it appears on,
            // so one meeting seen twice is one meeting and a dismissal sticks.
            // Recurring events share it too, so the start makes it unique.
            let identity = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? title
            return Meeting(
                id: "\(identity)@\(event.startDate.timeIntervalSince1970)",
                title: title.isEmpty ? "Untitled event" : title,
                start: event.startDate,
                end: event.endDate,
                joinURL: MeetingLinkFinder.find(
                    url: event.url, location: event.location, notes: event.notes,
                    trusted: standing == .mine),
                isAllDay: event.isAllDay,
                account: InviteAccount.email(
                    attendee: me(in: event)?.url, calendarAccount: event.calendar?.source?.title),
                isUnanswered: standing == .unanswered)
        }
    }

    private enum Standing {
        /// The user's own event, or an invitation they accepted.
        case mine
        /// An invitation waiting for an answer.
        case unanswered
        /// Has guests, but nothing says the user agreed to it.
        case unknown
    }

    /// How far the event can be taken as the user's own. Anyone can put an
    /// invitation on a calendar, so only an accepted one, or an event the user
    /// made, counts as theirs.
    private func standing(in event: EKEvent) -> Standing {
        guard let attendees = event.attendees, !attendees.isEmpty else { return .mine }
        if event.organizer?.isCurrentUser == true { return .mine }
        switch attendees.first(where: \.isCurrentUser)?.participantStatus {
        case .accepted, .tentative: return .mine
        case .pending: return .unanswered
        default: return .unknown
        }
    }

    private func declined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    /// The user's own entry on the event: as a guest, or as its organiser.
    private func me(in event: EKEvent) -> EKParticipant? {
        event.attendees?.first(where: \.isCurrentUser)
            ?? event.organizer.flatMap { $0.isCurrentUser ? $0 : nil }
    }
}

/// A made-up day whose main meeting is 65 seconds after launch, on a compressed
/// schedule: nudge at 5s, pill at 25s, stay at 40s, countdown at 50s, start at
/// 65s, late at 73s, gone at 85s. With `busy`, another call runs right up to
/// it and the app is told the microphone is live, so the reminder is quiet.
@MainActor
final class DemoSource: MeetingSource {
    static let config = ReminderConfig(
        headsUpLead: 60, headsUpDuration: 6, approachLead: 40, stayLead: 25,
        countdownLead: 15, overdueAfter: 8, startedLinger: 20)

    var onChange: (() -> Void)?
    private let busy: Bool
    private let start = Date().addingTimeInterval(65)

    init(busy: Bool) {
        self.busy = busy
    }

    func requestAccess() async -> Bool { true }

    func calendars() -> [CalendarInfo] { [] }

    func meetings(from: Date, to: Date, hiding: Set<String>) -> [Meeting] {
        func event(_ title: String, at offset: TimeInterval, minutes: Double, link: String? = nil)
            -> Meeting
        {
            let begins = start.addingTimeInterval(offset)
            return Meeting(
                id: title, title: title, start: begins, end: begins.addingTimeInterval(minutes * 60),
                joinURL: link.flatMap(URL.init(string:)))
        }
        let midnight = Calendar.current.startOfDay(for: start)
        var day = [
            Meeting(
                id: "offsite", title: "Company offsite", start: midnight,
                end: midnight.addingTimeInterval(86_399), isAllDay: true),
            event("Morning standup", at: -3 * 3600, minutes: 15),
            event("Weekly product sync", at: 0, minutes: 30, link: "https://meet.google.com/"),
            event("Design review", at: 2 * 3600, minutes: 45),
        ]
        if busy {
            day.append(event("Customer call", at: -30 * 60, minutes: 30))
        }
        return day
    }
}
