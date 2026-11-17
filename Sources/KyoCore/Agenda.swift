import Foundation

/// One line of the day's list.
public struct AgendaEntry: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case allDay
        case past
        case now
        /// The first event still to start.
        case next
        case later
    }

    public let meeting: Meeting
    public let status: Status

    public init(meeting: Meeting, status: Status) {
        self.meeting = meeting
        self.status = status
    }
}

public enum Agenda {
    /// Cuts the list down to `limit` lines. What has already happened goes
    /// first; if that is not enough, the tail is dropped and counted, and one
    /// line is left free to say how many.
    public static func fitting(_ entries: [AgendaEntry], limit: Int)
        -> (shown: [AgendaEntry], hidden: Int)
    {
        var shown = entries
        while shown.count > limit, let past = shown.firstIndex(where: { $0.status == .past }) {
            shown.remove(at: past)
        }
        guard shown.count > limit else { return (shown, 0) }
        let kept = max(0, limit - 1)
        return (Array(shown.prefix(kept)), shown.count - kept)
    }

    /// Everything that touches today: all-day events first, then by start.
    public static func today(
        from meetings: [Meeting], at now: Date, calendar: Calendar = .current
    ) -> [AgendaEntry] {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let todays = meetings.filter { meeting in
            // An event with no length belongs to the day it starts on.
            meeting.end > meeting.start
                ? meeting.start < dayEnd && meeting.end > dayStart
                : meeting.start >= dayStart && meeting.start < dayEnd
        }
        let ordered =
            todays.filter(\.isAllDay)
            + todays.filter { !$0.isAllDay }.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)

        let next = ordered.first { !$0.isAllDay && $0.start > now }
        return ordered.map { meeting in
            let status: AgendaEntry.Status =
                if meeting.isAllDay {
                    .allDay
                } else if meeting.start > now {
                    meeting.id == next?.id ? .next : .later
                } else if meeting.end > now {
                    .now
                } else {
                    .past
                }
            return AgendaEntry(meeting: meeting, status: status)
        }
    }
}
