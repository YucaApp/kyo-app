import Foundation

public enum TimeLabel {
    public static func text(for phase: ReminderPhase, meeting: Meeting, at now: Date) -> String {
        let untilStart = meeting.start.timeIntervalSince(now)
        switch phase {
        case .headsUp, .approaching, .upcoming:
            return relative(untilStart)
        case .countdown:
            // Rounded up, so 0:00 only shows at the start itself.
            let seconds = max(0, Int(untilStart.rounded(.up)))
            let padded = seconds % 60 < 10 ? "0\(seconds % 60)" : "\(seconds % 60)"
            return "\(seconds / 60):\(padded)"
        case .started, .overdue:
            let minutes = Int(-untilStart / 60)
            return minutes < 1 ? "now" : "started \(minutes) min ago"
        }
    }

    /// What the pill says for a phase: "12m", "1:42", "now".
    public static func pill(for phase: ReminderPhase, meeting: Meeting, at now: Date) -> String {
        switch phase {
        case .headsUp, .approaching, .upcoming:
            compact(meeting.start.timeIntervalSince(now))
        case .countdown:
            text(for: .countdown, meeting: meeting, at: now)
        case .started, .overdue:
            "now"
        }
    }

    /// "12m": the time to go, short enough to sit beside the notch.
    public static func compact(_ remaining: TimeInterval) -> String {
        "\(max(1, Int((remaining / 60).rounded(.up))))m"
    }

    /// "in 5 min", "in 1 hr 30 min".
    public static func relative(_ remaining: TimeInterval) -> String {
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        let hours = minutes / 60
        switch (hours, minutes % 60) {
        case (0, let m): return "in \(m) min"
        case (let h, 0): return "in \(h) hr"
        case (let h, let m): return "in \(h) hr \(m) min"
        }
    }
}
