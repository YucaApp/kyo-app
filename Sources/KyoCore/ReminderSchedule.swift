import Foundation

public struct ReminderConfig: Equatable, Sendable {
    /// How long before the start the first nudge drops.
    public var headsUpLead: TimeInterval
    /// How long that nudge stays down.
    public var headsUpDuration: TimeInterval
    /// From this long before the start a small pill sits beside the notch.
    public var approachLead: TimeInterval
    /// From this long before the start the panel drops and stays.
    public var stayLead: TimeInterval
    /// From this long before the start the panel counts down in seconds.
    public var countdownLead: TimeInterval
    /// How long after the start, with no join or dismissal, the panel escalates.
    public var overdueAfter: TimeInterval
    /// How long the panel stays after the start if nobody joins or dismisses.
    public var startedLinger: TimeInterval

    public init(
        headsUpLead: TimeInterval = 60 * 60,
        headsUpDuration: TimeInterval = 12,
        approachLead: TimeInterval = 15 * 60,
        stayLead: TimeInterval = 5 * 60,
        countdownLead: TimeInterval = 2 * 60,
        overdueAfter: TimeInterval = 60,
        startedLinger: TimeInterval = 5 * 60
    ) {
        self.headsUpLead = headsUpLead
        self.headsUpDuration = headsUpDuration
        self.approachLead = approachLead
        self.stayLead = stayLead
        self.countdownLead = countdownLead
        self.overdueAfter = overdueAfter
        self.startedLinger = startedLinger
    }

    public static let standard = ReminderConfig()

    /// The standard timings with the drop-and-stay moved to `leadMinutes` before the start.
    public static func standard(leadMinutes: Int) -> ReminderConfig {
        var config = ReminderConfig.standard
        config.stayLead = TimeInterval(max(1, leadMinutes) * 60)
        // The countdown is the tail of the stay, never longer than it.
        config.countdownLead = min(config.countdownLead, config.stayLead)
        return config
    }
}

public enum ReminderPhase: Equatable, Sendable {
    /// The one-hour nudge: drops briefly.
    case headsUp
    /// Fifteen minutes out: a small pill beside the notch.
    case approaching
    /// Five minutes out: the panel drops and stays.
    case upcoming
    /// Last two minutes: counting down.
    case countdown
    case started
    /// Started a while ago and nobody joined or dismissed.
    case overdue

    public var stage: DismissStage {
        switch self {
        case .headsUp: .headsUp
        case .approaching: .approaching
        case .upcoming, .countdown, .started, .overdue: .main
        }
    }
}

/// What a dismissal covers: the one-hour nudge, the pill, or the whole stay-down run.
public enum DismissStage: Hashable, Sendable {
    case headsUp
    case approaching
    case main
}

public struct Dismissal: Hashable, Sendable {
    public let meetingID: String
    public let stage: DismissStage

    public init(meetingID: String, stage: DismissStage) {
        self.meetingID = meetingID
        self.stage = stage
    }
}

public struct ActiveReminder: Equatable, Sendable {
    public let meeting: Meeting
    public let phase: ReminderPhase
    /// Other meetings starting at the same moment.
    public let alsoStarting: Int
    /// The user is in a call right now: remind with the pill, not the dropped
    /// panel, and never escalate.
    public let quiet: Bool

    public init(meeting: Meeting, phase: ReminderPhase, alsoStarting: Int, quiet: Bool = false) {
        self.meeting = meeting
        self.phase = phase
        self.alsoStarting = alsoStarting
        self.quiet = quiet
    }
}

/// How much room a reminder takes.
public enum Prominence: Equatable, Sendable {
    case pill
    case panel
}

public enum ReminderSchedule {
    public static func phase(
        for meeting: Meeting, at now: Date, config: ReminderConfig = .standard,
        snoozedUntil: Date? = nil
    ) -> ReminderPhase? {
        guard !meeting.isAllDay else { return nil }
        let untilStart = meeting.start.timeIntervalSince(now)
        if untilStart > 0 {
            if untilStart <= config.countdownLead { return .countdown }
            if untilStart <= config.stayLead { return .upcoming }
            if untilStart <= config.approachLead { return .approaching }
            let headsUpEnds = config.headsUpLead - config.headsUpDuration
            if untilStart <= config.headsUpLead, untilStart > headsUpEnds { return .headsUp }
            return nil
        }
        guard now < lingerEnd(for: meeting, config: config, snoozedUntil: snoozedUntil) else {
            return nil
        }
        return -untilStart >= config.overdueAfter ? .overdue : .started
    }

    public static func active(
        among meetings: [Meeting], at now: Date,
        dismissed: Set<Dismissal> = [], snoozed: [String: Date] = [:],
        inCall: Bool = false, config: ReminderConfig = .standard
    ) -> ActiveReminder? {
        let due: [(meeting: Meeting, phase: ReminderPhase)] = meetings.compactMap { meeting in
            let snoozedUntil = snoozed[meeting.id]
            if let snoozedUntil, snoozedUntil > now { return nil }
            guard
                let phase = phase(
                    for: meeting, at: now, config: config, snoozedUntil: snoozedUntil),
                !dismissed.contains(Dismissal(meetingID: meeting.id, stage: phase.stage))
            else { return nil }
            return (meeting, phase)
        }
        // The stay-down run outranks the hour-ahead nudge, which outranks the
        // pill: a meeting an hour or fifteen minutes away never hides one that
        // is starting or running.
        let pool =
            [[.upcoming, .countdown, .started, .overdue], [.headsUp], [.approaching]]
            .lazy.map { (phases: [ReminderPhase]) in due.filter { phases.contains($0.phase) } }
            .first { !$0.isEmpty } ?? []
        // Then: a meeting about to start matters more than one already running;
        // among those, the soonest. Among running ones, the most recent.
        let starts = pool.map(\.meeting.start)
        guard let start = starts.filter({ $0 > now }).min() ?? starts.max() else { return nil }
        let together = pool.filter { $0.meeting.start == start }
        let chosen = together[0]
        return ActiveReminder(
            meeting: chosen.meeting, phase: chosen.phase, alsoStarting: together.count - 1,
            quiet: inCall)
    }

    /// Whether to remind with the pill or the dropped panel.
    public static func prominence(
        of reminder: ActiveReminder, at now: Date, config: ReminderConfig = .standard
    ) -> Prominence {
        switch reminder.phase {
        case .headsUp:
            return .panel
        case .approaching:
            return .pill
        case .upcoming, .countdown:
            return reminder.quiet ? .pill : .panel
        case .started, .overdue:
            guard reminder.quiet else { return .panel }
            // One brief drop to say "next up", then out of the way again.
            let sinceStart = now.timeIntervalSince(reminder.meeting.start)
            return sinceStart < config.headsUpDuration ? .panel : .pill
        }
    }

    /// How long to wait until the time left before `reference` next crosses a
    /// multiple of `step`, so a display counting in those steps changes exactly
    /// on time. A hair is added so the wake-up lands just past the boundary.
    public static func untilNextStep(
        of step: TimeInterval, before reference: Date, from now: Date
    ) -> TimeInterval {
        let remainder = reference.timeIntervalSince(now).truncatingRemainder(dividingBy: step)
        let fraction = remainder < 0 ? remainder + step : remainder
        // Already on a boundary (or a rounding error from it): wait a full step.
        return (fraction < 0.02 ? fraction + step : fraction) + 0.005
    }

    /// The next moment after `now` at which any meeting changes phase.
    public static func nextChange(
        among meetings: [Meeting], after now: Date, config: ReminderConfig = .standard,
        snoozed: [String: Date] = [:]
    ) -> Date? {
        meetings
            .filter { !$0.isAllDay }
            .flatMap { boundaries(for: $0, config: config, snoozedUntil: snoozed[$0.id]) }
            .filter { $0 > now }
            .min()
    }

    private static func boundaries(
        for meeting: Meeting, config: ReminderConfig, snoozedUntil: Date?
    ) -> [Date] {
        let end = lingerEnd(for: meeting, config: config, snoozedUntil: snoozedUntil)
        return [
            meeting.start.addingTimeInterval(-config.headsUpLead),
            meeting.start.addingTimeInterval(-config.headsUpLead + config.headsUpDuration),
            meeting.start.addingTimeInterval(-config.approachLead),
            meeting.start.addingTimeInterval(-config.stayLead),
            meeting.start.addingTimeInterval(-config.countdownLead),
            meeting.start,
            // Going overdue only counts if the panel is still there by then.
            min(meeting.start.addingTimeInterval(config.overdueAfter), end),
            end,
        ] + (snoozedUntil.map { [$0] } ?? [])
    }

    /// The panel leaves when the linger runs out or the meeting itself ends,
    /// whichever is first. A zero-length event gets the full linger. After a
    /// snooze it comes back for at least a minute, so snoozing is never a
    /// silent dismissal.
    private static func lingerEnd(
        for meeting: Meeting, config: ReminderConfig, snoozedUntil: Date? = nil
    ) -> Date {
        var linger = meeting.start.addingTimeInterval(config.startedLinger)
        if let snoozedUntil { linger = max(linger, snoozedUntil.addingTimeInterval(60)) }
        return meeting.end > meeting.start ? min(linger, meeting.end) : linger
    }
}
