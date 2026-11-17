import Foundation
import Testing
@testable import KyoCore

@Suite struct AgendaTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 06:13 UTC; the day runs from `now - 6h13m20s` for 24 hours.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ id: String, inHours start: Double, lasting hours: Double = 1) -> Meeting {
        Meeting(
            id: id, title: id, start: now.addingTimeInterval(start * 3600),
            end: now.addingTimeInterval((start + hours) * 3600))
    }

    private func allDay(_ id: String) -> Meeting {
        let midnight = utc.startOfDay(for: now)
        return Meeting(
            id: id, title: id, start: midnight, end: midnight.addingTimeInterval(86_399),
            isAllDay: true)
    }

    private func today(_ meetings: [Meeting]) -> [AgendaEntry] {
        Agenda.today(from: meetings, at: now, calendar: utc)
    }

    @Test func listsAllDayFirstThenByStart() {
        let entries = today([event("late", inHours: 5), allDay("holiday"), event("early", inHours: 1)])
        #expect(entries.map(\.meeting.id) == ["holiday", "early", "late"])
    }

    @Test func marksEachEventByWhereItSitsInTheDay() {
        let entries = today([
            allDay("holiday"), event("done", inHours: -3), event("running", inHours: -0.5),
            event("upnext", inHours: 1), event("after", inHours: 4),
        ])
        #expect(entries.map(\.status) == [.allDay, .past, .now, .next, .later])
    }

    @Test func leavesOutOtherDays() {
        let entries = today([
            event("yesterday", inHours: -20), event("tomorrow", inHours: 20), event("today", inHours: 2),
        ])
        #expect(entries.map(\.meeting.id) == ["today"])
    }

    @Test func keepsAnEventThatRunsOverMidnightIntoToday() {
        let entries = today([event("overnight", inHours: -8, lasting: 9)])
        #expect(entries.map(\.status) == [.now])
    }

    @Test func emptyWhenNothingIsOn() {
        #expect(today([]).isEmpty)
    }

    // MARK: Fitting the panel

    private func entries(_ statuses: [AgendaEntry.Status]) -> [AgendaEntry] {
        statuses.enumerated().map { index, status in
            AgendaEntry(meeting: event("e\(index)", inHours: Double(index)), status: status)
        }
    }

    @Test func aShortListIsLeftAlone() {
        let list = entries([.past, .now, .next])
        let fitted = Agenda.fitting(list, limit: 3)
        #expect(fitted.shown == list)
        #expect(fitted.hidden == 0)
    }

    @Test func whatHasPassedIsDroppedFirst() {
        let list = entries([.allDay, .past, .past, .now, .next, .later])
        let fitted = Agenda.fitting(list, limit: 4)
        #expect(fitted.shown.map(\.status) == [.allDay, .now, .next, .later])
        #expect(fitted.hidden == 0)
    }

    @Test func onlyAsMuchOfThePastAsNeededIsDropped() {
        let fitted = Agenda.fitting(entries([.past, .past, .now, .next]), limit: 3)
        #expect(fitted.shown.map(\.meeting.id) == ["e1", "e2", "e3"])
    }

    @Test func aLongDayLosesItsTailAndSaysHowMuch() {
        let list = entries([.now, .next, .later, .later, .later, .later])
        let fitted = Agenda.fitting(list, limit: 4)
        // Three lines of events, leaving the fourth for "+3 more".
        #expect(fitted.shown.map(\.meeting.id) == ["e0", "e1", "e2"])
        #expect(fitted.hidden == 3)
    }
}
