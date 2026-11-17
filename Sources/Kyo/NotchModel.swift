import AppKit
import KyoCore

/// What the panel is showing right now.
struct NotchContent: Equatable {
    enum Tone: Equatable {
        case calm  // nothing pressing: the one-hour nudge, the pill, a peek
        case soon  // inside five minutes
        case urgent  // counting down
        case live  // started
        case late  // started a while ago, nobody joined
    }

    var title: String
    var detail: String
    /// The time-to-go text on the right; large while counting down.
    var emphasis: String?
    var tone: Tone = .calm
    var actionLabel: String?
    /// The time-to-go text for the pill, e.g. "12m".
    var compactText: String?
    /// Offer a snooze button beside ×.
    var canSnooze = false
    /// When set, the panel lists the day in place of the single row;
    /// `title` and `detail` become its heading.
    var agenda: [AgendaRow]?

    /// Height of the content under the notch when the panel is open.
    var height: CGFloat {
        guard let agenda else { return NotchMetrics.rowHeight }
        return AgendaRow.headerHeight + CGFloat(max(1, agenda.count)) * AgendaRow.height + 12
    }
}

/// One line of the day's list.
struct AgendaRow: Equatable, Identifiable {
    static let height: CGFloat = 23
    static let headerHeight: CGFloat = 34

    let id: String
    var time: String
    var title: String
    var status: AgendaEntry.Status
    /// "in 12 min" or "now", on the right.
    var trailing: String?
    /// The row is clickable: it has a link to open.
    var hasCall = false
    /// Where the link leads when it is not a known call service.
    var linkHost: String?
}

enum NotchState: Equatable {
    /// Nothing drawn; the window is off screen.
    case closed
    /// A pill the height of the menu bar, a little wider than the notch.
    case compact
    /// The full panel, dropped below the notch.
    case open
}

/// Where the notch is and how big the panel grows.
struct NotchMetrics: Equatable {
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 0
    /// Distance from the screen's left edge to the centre of the notch.
    var centerX: CGFloat = 0

    /// Height of the content row under the notch.
    static let rowHeight: CGFloat = 58
    /// How far the pill reaches either side of the notch.
    static let wing: CGFloat = 44

    var hasNotch: Bool { notchHeight > 0 }

    init() {}

    init(screen: NSScreen) {
        centerX = screen.frame.width / 2
        // Screens with a camera housing report the menu-bar strips either side of it.
        guard screen.safeAreaInsets.top > 0,
            let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea
        else { return }
        notchWidth = screen.frame.width - left.width - right.width
        notchHeight = screen.safeAreaInsets.top
        centerX = left.width + notchWidth / 2
    }

    /// Size of the black shape, not counting the flared ears. `contentHeight`
    /// is what the open panel holds under the notch.
    func size(for state: NotchState, contentHeight: CGFloat = NotchMetrics.rowHeight) -> CGSize {
        switch state {
        case .closed:
            CGSize(width: notchWidth, height: notchHeight)
        case .compact:
            // Without a notch there is nothing to hide behind, so use the menu bar's height.
            CGSize(width: notchWidth + 2 * Self.wing, height: hasNotch ? notchHeight : 26)
        case .open:
            CGSize(width: max(440, notchWidth + 220), height: notchHeight + contentHeight)
        }
    }
}

@MainActor
final class NotchModel: ObservableObject {
    @Published var content: NotchContent?
    @Published var state: NotchState = .closed
    @Published var metrics = NotchMetrics()
    /// Follows `content.height`; set by the panel so the window can keep up.
    @Published var contentHeight = NotchMetrics.rowHeight

    var onAction: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onSnooze: () -> Void = {}
    /// A row of the day list was clicked; the argument is its id.
    var onOpenRow: (String) -> Void = { _ in }
    /// The pill was clicked.
    var onTap: () -> Void = {}
}

enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let lateSoundKey = "lateSound"
    private static let leadMinutesKey = "leadMinutes"
    private static let snoozeSecondsKey = "snoozeSeconds"
    private static let hiddenCalendarsKey = "hiddenCalendars"
    private static let quietInCallsKey = "quietInCalls"
    private static let ignoreUnansweredKey = "ignoreUnanswered"

    static let leadChoices = [1, 2, 3, 5, 10, 15]
    static let snoozeChoices = [30, 60, 120, 300, 600]

    static func registerDefaults() {
        defaults.register(defaults: [
            lateSoundKey: true, leadMinutesKey: 5, snoozeSecondsKey: 120, quietInCallsKey: true,
        ])
    }

    /// Play a sound when a meeting has started and nobody joined.
    static var lateSound: Bool {
        get { defaults.bool(forKey: lateSoundKey) }
        set { defaults.set(newValue, forKey: lateSoundKey) }
    }

    /// Remind with the pill, and never escalate, while the microphone is in use.
    static var quietInCalls: Bool {
        get { defaults.bool(forKey: quietInCallsKey) }
        set { defaults.set(newValue, forKey: quietInCallsKey) }
    }

    /// Leave out invitations the user has neither accepted nor declined.
    static var ignoreUnanswered: Bool {
        get { defaults.bool(forKey: ignoreUnansweredKey) }
        set { defaults.set(newValue, forKey: ignoreUnansweredKey) }
    }

    /// Minutes before the start at which the panel drops and stays.
    static var leadMinutes: Int {
        get { defaults.integer(forKey: leadMinutesKey) }
        set { defaults.set(newValue, forKey: leadMinutesKey) }
    }

    static var snoozeSeconds: Int {
        get { defaults.integer(forKey: snoozeSecondsKey) }
        set { defaults.set(newValue, forKey: snoozeSecondsKey) }
    }

    /// Identifiers of calendars left out. Storing the exclusions means a
    /// calendar added later is included without anyone having to notice it.
    static var hiddenCalendars: Set<String> {
        get { Set(defaults.stringArray(forKey: hiddenCalendarsKey) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: hiddenCalendarsKey) }
    }
}
