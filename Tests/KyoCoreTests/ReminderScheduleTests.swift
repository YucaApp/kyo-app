import Foundation
import Testing
@testable import KyoCore

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func meeting(
    _ id: String = "m", startsAt: Date = start, lasting: TimeInterval = 1800
) -> Meeting {
    Meeting(id: id, title: "Standup", start: startsAt, end: startsAt.addingTimeInterval(lasting))
}

private func before(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(-seconds) }
private func after(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

@Suite struct PhaseTests {
    @Test func nothingMoreThanAnHourOut() {
        #expect(ReminderSchedule.phase(for: meeting(), at: before(3601)) == nil)
    }

    @Test func headsUpDropsAtOneHour() {
        #expect(ReminderSchedule.phase(for: meeting(), at: before(3600)) == .headsUp)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(3589)) == .headsUp)
    }

    @Test func headsUpRetractsAfterTwelveSeconds() {
        #expect(ReminderSchedule.phase(for: meeting(), at: before(3588)) == nil)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(901)) == nil)
    }

    @Test func pillSitsBesideTheNotchFromFifteenMinutes() {
        #expect(ReminderSchedule.phase(for: meeting(), at: before(900)) == .approaching)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(301)) == .approaching)
    }

    @Test func staysDownFromFiveMinutes() {
        #expect(ReminderSchedule.phase(for: meeting(), at: before(300)) == .upcoming)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(121)) == .upcoming)
    }

    @Test func countsDownForLastTwoMinutes() {
        #expect(ReminderSchedule.phase(for: meeting(), at: before(120)) == .countdown)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(0.5)) == .countdown)
    }

    @Test func startedForTheFirstMinute() {
        #expect(ReminderSchedule.phase(for: meeting(), at: start) == .started)
        #expect(ReminderSchedule.phase(for: meeting(), at: after(59)) == .started)
    }

    @Test func overdueOnceAMinuteHasPassedUnjoined() {
        #expect(ReminderSchedule.phase(for: meeting(), at: after(60)) == .overdue)
        #expect(ReminderSchedule.phase(for: meeting(), at: after(299)) == .overdue)
    }

    @Test func leavesFiveMinutesAfterTheStart() {
        #expect(ReminderSchedule.phase(for: meeting(), at: after(300)) == nil)
    }

    @Test func leavesWhenAShortMeetingEnds() {
        let short = meeting(lasting: 120)
        #expect(ReminderSchedule.phase(for: short, at: after(119)) == .overdue)
        #expect(ReminderSchedule.phase(for: short, at: after(120)) == nil)
    }

    @Test func aVeryShortMeetingNeverGoesOverdue() {
        let blink = meeting(lasting: 30)
        #expect(ReminderSchedule.phase(for: blink, at: after(29)) == .started)
        #expect(ReminderSchedule.phase(for: blink, at: after(30)) == nil)
    }

    @Test func zeroLengthEventStillLingers() {
        #expect(ReminderSchedule.phase(for: meeting(lasting: 0), at: after(30)) == .started)
        #expect(ReminderSchedule.phase(for: meeting(lasting: 0), at: after(90)) == .overdue)
    }

    @Test func leadsComeFromConfig() {
        let quick = ReminderConfig(
            headsUpLead: 60, headsUpDuration: 6, approachLead: 40, stayLead: 25,
            countdownLead: 15, overdueAfter: 8, startedLinger: 20)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(60), config: quick) == .headsUp)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(50), config: quick) == nil)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(30), config: quick) == .approaching)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(20), config: quick) == .upcoming)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(10), config: quick) == .countdown)
        #expect(ReminderSchedule.phase(for: meeting(), at: after(5), config: quick) == .started)
        #expect(ReminderSchedule.phase(for: meeting(), at: after(8), config: quick) == .overdue)
        #expect(ReminderSchedule.phase(for: meeting(), at: after(20), config: quick) == nil)
    }
}

@Suite struct ActiveReminderTests {
    @Test func noneWhenNothingIsDue() {
        #expect(ReminderSchedule.active(among: [meeting()], at: before(1000)) == nil)
    }

    @Test func reportsTheMeetingAndItsPhase() {
        let m = meeting()
        #expect(
            ReminderSchedule.active(among: [m], at: before(200))
                == ActiveReminder(meeting: m, phase: .upcoming, alsoStarting: 0))
    }

    @Test func aboutToStartBeatsAlreadyStarted() {
        let running = meeting("running", startsAt: before(240))
        let next = meeting("next")
        let active = ReminderSchedule.active(among: [running, next], at: before(60))
        #expect(active?.meeting.id == "next")
        #expect(active?.phase == .countdown)
    }

    @Test func aDroppedPanelIsNotReplacedByAPill() {
        let running = meeting("running", startsAt: before(720))
        let next = meeting("next")
        let active = ReminderSchedule.active(among: [running, next], at: before(600))
        #expect(active?.meeting.id == "running")
        #expect(active?.phase == .overdue)
    }

    @Test func dismissingThePillLeavesTheStay() {
        let dismissed: Set = [Dismissal(meetingID: "m", stage: .approaching)]
        #expect(
            ReminderSchedule.active(among: [meeting()], at: before(600), dismissed: dismissed) == nil)
        #expect(
            ReminderSchedule.active(among: [meeting()], at: before(200), dismissed: dismissed)?.phase
                == .upcoming)
    }

    @Test func soonestStartWinsAmongUpcoming() {
        let later = meeting("later", startsAt: after(120))
        let sooner = meeting("sooner")
        let active = ReminderSchedule.active(among: [later, sooner], at: before(100))
        #expect(active?.meeting.id == "sooner")
    }

    @Test func countsOtherMeetingsStartingTogether() {
        let active = ReminderSchedule.active(
            among: [meeting("a"), meeting("b"), meeting("c", startsAt: after(60))], at: before(100))
        #expect(active?.meeting.id == "a")
        #expect(active?.alsoStarting == 1)
    }

    @Test func dismissingTheStayHidesItThroughTheStart() {
        let dismissed: Set = [Dismissal(meetingID: "m", stage: .main)]
        for moment in [before(200), before(60), after(30), after(90)] {
            #expect(
                ReminderSchedule.active(among: [meeting()], at: moment, dismissed: dismissed) == nil)
        }
    }

    @Test func dismissingTheHeadsUpDoesNotSilenceTheStay() {
        let dismissed: Set = [Dismissal(meetingID: "m", stage: .headsUp)]
        #expect(
            ReminderSchedule.active(among: [meeting()], at: before(3595), dismissed: dismissed) == nil)
        #expect(
            ReminderSchedule.active(among: [meeting()], at: before(200), dismissed: dismissed)?.phase
                == .upcoming)
    }

    @Test func dismissedMeetingRevealsTheNextOne() {
        let dismissed: Set = [Dismissal(meetingID: "a", stage: .main)]
        let active = ReminderSchedule.active(
            among: [meeting("a"), meeting("b")], at: before(100), dismissed: dismissed)
        #expect(active?.meeting.id == "b")
        #expect(active?.alsoStarting == 0)
    }
}

@Suite struct NextChangeTests {
    @Test func nilWithNoMeetings() {
        #expect(ReminderSchedule.nextChange(among: [], after: start) == nil)
    }

    @Test func walksEveryBoundaryInOrder() {
        let m = [meeting()]
        #expect(ReminderSchedule.nextChange(among: m, after: before(5000)) == before(3600))
        #expect(ReminderSchedule.nextChange(among: m, after: before(3600)) == before(3588))
        #expect(ReminderSchedule.nextChange(among: m, after: before(3000)) == before(900))
        #expect(ReminderSchedule.nextChange(among: m, after: before(900)) == before(300))
        #expect(ReminderSchedule.nextChange(among: m, after: before(300)) == before(120))
        #expect(ReminderSchedule.nextChange(among: m, after: before(120)) == start)
        #expect(ReminderSchedule.nextChange(among: m, after: start) == after(60))
        #expect(ReminderSchedule.nextChange(among: m, after: after(60)) == after(300))
        #expect(ReminderSchedule.nextChange(among: m, after: after(300)) == nil)
    }

    @Test func shortMeetingEndsTheLingerEarly() {
        let m = [meeting(lasting: 90)]
        #expect(ReminderSchedule.nextChange(among: m, after: start) == after(60))
        #expect(ReminderSchedule.nextChange(among: m, after: after(60)) == after(90))
    }

    @Test func noOverdueBoundaryPastTheEndOfAVeryShortMeeting() {
        let m = [meeting(lasting: 30)]
        #expect(ReminderSchedule.nextChange(among: m, after: start) == after(30))
        #expect(ReminderSchedule.nextChange(among: m, after: after(30)) == nil)
    }

    @Test func earliestBoundaryAcrossMeetings() {
        let m = [meeting("far", startsAt: after(7200)), meeting("near")]
        #expect(ReminderSchedule.nextChange(among: m, after: before(200)) == before(120))
    }
}

@Suite struct TimeLabelTests {
    @Test func headsUpSaysOneHour() {
        #expect(TimeLabel.text(for: .headsUp, meeting: meeting(), at: before(3600)) == "in 1 hr")
        #expect(TimeLabel.text(for: .headsUp, meeting: meeting(), at: before(3590)) == "in 1 hr")
    }

    @Test func upcomingRoundsMinutesUp() {
        #expect(TimeLabel.text(for: .upcoming, meeting: meeting(), at: before(300)) == "in 5 min")
        #expect(TimeLabel.text(for: .upcoming, meeting: meeting(), at: before(241)) == "in 5 min")
        #expect(TimeLabel.text(for: .upcoming, meeting: meeting(), at: before(150)) == "in 3 min")
    }

    @Test func countdownShowsMinutesAndSeconds() {
        #expect(TimeLabel.text(for: .countdown, meeting: meeting(), at: before(120)) == "2:00")
        #expect(TimeLabel.text(for: .countdown, meeting: meeting(), at: before(101.3)) == "1:42")
        #expect(TimeLabel.text(for: .countdown, meeting: meeting(), at: before(60)) == "1:00")
        #expect(TimeLabel.text(for: .countdown, meeting: meeting(), at: before(0.4)) == "0:01")
    }

    @Test func startedSaysNowThenHowLongAgo() {
        #expect(TimeLabel.text(for: .started, meeting: meeting(), at: start) == "now")
        #expect(TimeLabel.text(for: .started, meeting: meeting(), at: after(59)) == "now")
        #expect(TimeLabel.text(for: .started, meeting: meeting(), at: after(60)) == "started 1 min ago")
        #expect(TimeLabel.text(for: .started, meeting: meeting(), at: after(185)) == "started 3 min ago")
    }

    @Test func pillPhaseReadsLikeTheOthers() {
        #expect(TimeLabel.text(for: .approaching, meeting: meeting(), at: before(840)) == "in 14 min")
    }

    @Test func overdueSaysHowLongAgo() {
        #expect(TimeLabel.text(for: .overdue, meeting: meeting(), at: after(125)) == "started 2 min ago")
    }

    @Test func compactIsMinutesRoundedUp() {
        #expect(TimeLabel.compact(840) == "14m")
        #expect(TimeLabel.compact(841) == "15m")
        #expect(TimeLabel.compact(20) == "1m")
    }

    @Test func relativeSpansHoursAndMinutes() {
        #expect(TimeLabel.relative(45) == "in 1 min")
        #expect(TimeLabel.relative(5400) == "in 1 hr 30 min")
        #expect(TimeLabel.relative(7200) == "in 2 hr")
    }
}

@Suite struct AllDayTests {
    @Test func allDayEventsNeverAlert() {
        var holiday = meeting()
        holiday.isAllDay = true
        for moment in [before(3600), before(600), before(200), before(60), after(30)] {
            #expect(ReminderSchedule.phase(for: holiday, at: moment) == nil)
        }
        #expect(ReminderSchedule.active(among: [holiday], at: before(200)) == nil)
        #expect(ReminderSchedule.nextChange(among: [holiday], after: before(5000)) == nil)
    }
}

@Suite struct InCallTests {
    @Test func quietWhileTheUserIsInACall() {
        let active = ReminderSchedule.active(among: [meeting()], at: before(200), inCall: true)
        #expect(active?.meeting.id == "m")
        #expect(active?.quiet == true)
    }

    @Test func notQuietOtherwise() {
        #expect(ReminderSchedule.active(among: [meeting()], at: before(200))?.quiet == false)
    }

    @Test func aMeetingRunningUpToThisOneIsNotEnoughOnItsOwn() {
        // The calendar says busy, but nothing says the user is really in that call.
        let previous = meeting("prev", startsAt: before(1800), lasting: 1800)
        let active = ReminderSchedule.active(among: [previous, meeting()], at: before(200))
        #expect(active?.meeting.id == "m")
        #expect(active?.quiet == false)
    }

    @Test func theHourAheadNudgeDoesNotInterruptAMeetingThatJustStarted() {
        let running = meeting("running", startsAt: before(3600), lasting: 3600)
        let active = ReminderSchedule.active(among: [running, meeting("next")], at: before(3600))
        #expect(active?.meeting.id == "running")
        #expect(active?.phase == .started)
    }
}

@Suite struct ProminenceTests {
    private func prominence(_ phase: ReminderPhase, quiet: Bool, at now: Date) -> Prominence {
        ReminderSchedule.prominence(
            of: ActiveReminder(meeting: meeting(), phase: phase, alsoStarting: 0, quiet: quiet), at: now)
    }

    @Test func onlyTheFifteenMinuteStageIsAPillNormally() {
        #expect(prominence(.headsUp, quiet: false, at: before(3600)) == .panel)
        #expect(prominence(.approaching, quiet: false, at: before(600)) == .pill)
        #expect(prominence(.upcoming, quiet: false, at: before(200)) == .panel)
        #expect(prominence(.countdown, quiet: false, at: before(60)) == .panel)
        #expect(prominence(.started, quiet: false, at: after(30)) == .panel)
        #expect(prominence(.overdue, quiet: false, at: after(90)) == .panel)
    }

    @Test func aQuietReminderStaysAPillUpToTheStart() {
        #expect(prominence(.upcoming, quiet: true, at: before(200)) == .pill)
        #expect(prominence(.countdown, quiet: true, at: before(60)) == .pill)
    }

    @Test func aQuietReminderDropsBrieflyAtTheStartThenReturnsToThePill() {
        #expect(prominence(.started, quiet: true, at: start) == .panel)
        #expect(prominence(.started, quiet: true, at: after(11)) == .panel)
        #expect(prominence(.started, quiet: true, at: after(12)) == .pill)
        #expect(prominence(.overdue, quiet: true, at: after(90)) == .pill)
    }
}

@Suite struct SnoozeTests {
    @Test func aSnoozedMeetingIsHiddenUntilTheSnoozeEnds() {
        let snoozed = ["m": before(100)]
        #expect(ReminderSchedule.active(among: [meeting()], at: before(150), snoozed: snoozed) == nil)
        #expect(
            ReminderSchedule.active(among: [meeting()], at: before(100), snoozed: snoozed)?.phase
                == .countdown)
    }

    @Test func aSnoozeThatOutlastsTheLingerStillComesBackForAMinute() {
        let snoozed = ["m": after(400)]
        #expect(ReminderSchedule.active(among: [meeting()], at: after(350), snoozed: snoozed) == nil)
        #expect(
            ReminderSchedule.active(among: [meeting()], at: after(410), snoozed: snoozed)?.phase
                == .overdue)
        #expect(ReminderSchedule.active(among: [meeting()], at: after(460), snoozed: snoozed) == nil)
    }

    @Test func aSnoozeDoesNotOutliveTheMeeting() {
        let snoozed = ["m": after(400)]
        #expect(
            ReminderSchedule.active(among: [meeting(lasting: 360)], at: after(410), snoozed: snoozed)
                == nil)
    }

    @Test func theEndOfASnoozeIsAMomentOfChange() {
        let snoozed = ["m": after(400)]
        #expect(
            ReminderSchedule.nextChange(among: [meeting()], after: after(301), snoozed: snoozed)
                == after(400))
        #expect(
            ReminderSchedule.nextChange(among: [meeting()], after: after(400), snoozed: snoozed)
                == after(460))
    }
}

@Suite struct LeadTimeTests {
    @Test func leadMinutesMovesTheDropAndStay() {
        let config = ReminderConfig.standard(leadMinutes: 10)
        #expect(config.stayLead == 600)
        #expect(config.countdownLead == 120)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(590), config: config) == .upcoming)
    }

    @Test func aShortLeadShortensTheCountdownToMatch() {
        let config = ReminderConfig.standard(leadMinutes: 1)
        #expect(config.stayLead == 60)
        #expect(config.countdownLead == 60)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(61), config: config) == .approaching)
        #expect(ReminderSchedule.phase(for: meeting(), at: before(60), config: config) == .countdown)
    }
}

@Suite struct PillLabelTests {
    @Test func minutesThenCountdownThenNow() {
        #expect(TimeLabel.pill(for: .approaching, meeting: meeting(), at: before(840)) == "14m")
        #expect(TimeLabel.pill(for: .upcoming, meeting: meeting(), at: before(200)) == "4m")
        #expect(TimeLabel.pill(for: .countdown, meeting: meeting(), at: before(101.3)) == "1:42")
        #expect(TimeLabel.pill(for: .started, meeting: meeting(), at: after(20)) == "now")
        #expect(TimeLabel.pill(for: .overdue, meeting: meeting(), at: after(90)) == "now")
    }
}

@Suite struct TickAlignmentTests {
    private func wait(_ step: TimeInterval, startsIn seconds: TimeInterval) -> TimeInterval {
        ReminderSchedule.untilNextStep(of: step, before: start, from: before(seconds))
    }

    private func isClose(_ value: TimeInterval, to expected: TimeInterval) -> Bool {
        abs(value - expected) < 0.0001
    }

    @Test func waitsForTheNextWholeSecondOfTheCountdown() {
        #expect(isClose(wait(1, startsIn: 10.3), to: 0.305))
    }

    @Test func onABoundaryItWaitsAFullStepNotZero() {
        #expect(isClose(wait(1, startsIn: 10), to: 1.005))
    }

    @Test func keepsStepAfterTheStart() {
        // 2.3 seconds in: the next whole second of elapsed time is 0.7 away.
        #expect(isClose(wait(1, startsIn: -2.3), to: 0.705))
    }

    @Test func minuteStepsForThePill() {
        #expect(isClose(wait(60, startsIn: 125), to: 5.005))
    }
}
