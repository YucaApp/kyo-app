import AppKit
import KyoCore

/// Decides what the notch shows from the clock, the calendar and the pointer.
@MainActor
final class ReminderController {
    private let source: MeetingSource
    /// Fixed timings for the demo; otherwise they follow the settings.
    private let fixedConfig: ReminderConfig?
    private var config: ReminderConfig {
        fixedConfig ?? .standard(leadMinutes: Preferences.leadMinutes)
    }
    private let model = NotchModel()
    private let panel: NotchPanelController
    private let hover = HoverTracker()

    private var meetings: [Meeting] = []
    private var dismissed: Set<Dismissal> = []
    /// When each snoozed meeting's reminder comes back.
    private var snoozed: [String: Date] = [:]
    private lazy var settings = SettingsWindow(source: source) { [weak self] in self?.reload() }
    /// Meetings the late sound has already played for.
    private var escalated: Set<String> = []
    /// When what is remembered about each meeting above can be dropped.
    private var forgetAfter: [String: Date] = [:]
    private var pendingReload: DispatchWorkItem?
    private var hasAccess = false
    private var showing: ActiveReminder?
    private var peekUntil: Date?
    private var isHovering = false
    /// Set by a click on × or Open, so the panel can leave while the pointer is still on it.
    private var hoverSpent = false
    private var tick: Timer?
    private var observers: [NSObjectProtocol] = []

    /// Set for a recorded demo run; see `Diagnostics`.
    var diagnostics: Diagnostics?
    /// No sounds, for unattended runs.
    var isMuted = false

    /// Whether the user seems to be in a call.
    private let micIsLive: () -> Bool

    init(source: MeetingSource, config: ReminderConfig?, micIsLive: @escaping () -> Bool) {
        self.source = source
        self.fixedConfig = config
        self.micIsLive = micIsLive
        self.panel = NotchPanelController(model: model)
    }

    func start() {
        model.onAction = { [weak self] in self?.performAction() }
        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onSnooze = { [weak self] in self?.snooze() }
        model.onOpenRow = { [weak self] id in
            guard let self, let meeting = self.meetings.first(where: { $0.id == id }) else { return }
            self.diagnostics?.note("row opened")
            self.join(meeting)
            self.dismiss()
        }
        panel.onOpenSettings = { [weak self] in self?.settings.show() }
        model.onTap = { [weak self] in
            self?.diagnostics?.note("pill clicked")
            self?.peek()
        }
        source.onChange = { [weak self] in self?.reloadSoon() }

        hover.entryZone = { [panel] in panel.notchZone }
        hover.stayZone = { [panel] in panel.panelZone }
        hover.onChange = { [weak self] inside in
            self?.isHovering = inside
            self?.diagnostics?.note(inside ? "pointer on notch" : "pointer left")
            if !inside { self?.hoverSpent = false }
            self?.update()
        }
        hover.start()

        // Timers do not run while asleep, and the clock can jump.
        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter) {
            $0.reload()
        }
        observe(.NSSystemClockDidChange) { $0.reload() }
        observe(NSApplication.didChangeScreenParametersNotification) { $0.panel.place() }

        // A safety net; calendar edits arrive through `source.onChange`.
        let refresh = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        refresh.tolerance = 30
        RunLoop.main.add(refresh, forMode: .common)

        Task {
            hasAccess = await source.requestAccess()
            reload()
            peek()
        }
    }

    /// Drops the panel for a few seconds to show what is next.
    func peek() {
        peekUntil = Date().addingTimeInterval(hasAccess ? 8 : 12)
        update()
    }

    private func reload() {
        guard hasAccess else {
            // Access may have been granted in System Settings since we last asked.
            Task {
                hasAccess = await source.requestAccess()
                if hasAccess { reload() }
            }
            return update()
        }
        let now = Date()
        // From midnight, so the day's list can show what has already happened.
        meetings = source.meetings(
            from: Calendar.current.startOfDay(for: now), to: now.addingTimeInterval(26 * 60 * 60),
            hiding: Preferences.hiddenCalendars
        )
        .filter { !(Preferences.ignoreUnanswered && $0.isUnanswered) }
        .deduplicated()
        forgetFinishedMeetings(at: now)
        update()
    }

    /// A calendar sync announces itself many times over; one reload after it
    /// goes quiet is enough.
    private func reloadSoon() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Dismissals, snoozes and "already sounded" last until an hour after the
    /// meeting ends. They are dropped by the clock, not by whether the meeting
    /// is in the latest fetch: a fetch can come back short while calendars sync,
    /// and forgetting then would bring a dismissed reminder back.
    private func remember(_ meeting: Meeting) {
        forgetAfter[meeting.id] = max(meeting.start, meeting.end).addingTimeInterval(60 * 60)
    }

    private func forgetFinishedMeetings(at now: Date) {
        let finished = Set(forgetAfter.filter { $0.value < now }.keys)
        guard !finished.isEmpty else { return }
        dismissed = dismissed.filter { !finished.contains($0.meetingID) }
        snoozed = snoozed.filter { !finished.contains($0.key) }
        escalated.subtract(finished)
        finished.forEach { forgetAfter[$0] = nil }
    }

    private func update() {
        let now = Date()
        let config = config
        showing = ReminderSchedule.active(
            among: meetings, at: now, dismissed: dismissed, snoozed: snoozed,
            inCall: Preferences.quietInCalls && micIsLive(), config: config)
        if let until = peekUntil, until <= now { peekUntil = nil }
        // The user asked to look: pointer on the notch, a click on the pill, or Kyo reopened.
        let asked = (isHovering && !hoverSpent) || peekUntil != nil

        let state: NotchState
        let content: NotchContent?
        if let showing {
            content = reminderContent(showing, at: now)
            let pill = ReminderSchedule.prominence(of: showing, at: now, config: config) == .pill
            state = pill && !asked ? .compact : .open
        } else if asked {
            content = peekContent(at: now)
            state = .open
        } else {
            content = nil
            state = .closed
        }
        panel.present(state, content: content)
        soundIfNewlyLate()
        scheduleTick(from: now, state: state)
        if state != .closed, let diagnostics {
            diagnostics.snapshot(of: panel, readings: readings())
        }
    }

    private func scheduleTick(from now: Date, state: NotchState) {
        tick?.invalidate()
        let nextChange = ReminderSchedule.nextChange(
            among: meetings, after: now, config: config, snoozed: snoozed)?
            .timeIntervalSince(now)
        let delay: TimeInterval
        switch state {
        case .open:
            // On whole seconds relative to the start, so the countdown and the
            // phase changes land exactly on time.
            let reference = showing?.meeting.start ?? peekUntil ?? now
            delay = ReminderSchedule.untilNextStep(of: 1, before: reference, from: now)
        case .compact:
            // The pill shows minutes, except while it counts down.
            let reference = showing?.meeting.start ?? now
            let step: TimeInterval = showing?.phase == .countdown ? 1 : 60
            // Look again every few seconds regardless: the call the user is in
            // may end, and then this reminder should stop being quiet.
            delay = min(
                ReminderSchedule.untilNextStep(of: step, before: reference, from: now), nextChange ?? 60, 5)
        case .closed:
            delay = min(60, nextChange ?? 60)
        }
        let timer = Timer(timeInterval: max(0.05, delay), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    // MARK: Buttons

    private func performAction() {
        diagnostics?.note("button clicked: \(model.content?.actionLabel ?? "?")")
        if !hasAccess {
            if let settings = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
            {
                NSWorkspace.shared.open(settings)
            }
        } else if let meeting = showing?.meeting {
            join(meeting)
        }
        dismiss()
    }

    /// Opens a meeting's call: in the service's own app when it has one
    /// installed, otherwise in the browser as the account that was invited.
    private func join(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        if let native = NativeMeetingLink.url(for: url),
            NSWorkspace.shared.urlForApplication(toOpen: native) != nil
        {
            NSWorkspace.shared.open(native)
            return
        }
        NSWorkspace.shared.open(InviteAccount.link(url, for: meeting.account))
    }

    private func dismiss() {
        diagnostics?.note("dismissed")
        if let showing {
            dismissed.insert(Dismissal(meetingID: showing.meeting.id, stage: showing.phase.stage))
            remember(showing.meeting)
        }
        peekUntil = nil
        hoverSpent = true
        update()
    }

    /// Hides the reminder for the snooze length, after which it comes back.
    private func snooze() {
        diagnostics?.note("snoozed")
        guard let showing else { return }
        snoozed[showing.meeting.id] = Date().addingTimeInterval(
            TimeInterval(Preferences.snoozeSeconds))
        remember(showing.meeting)
        peekUntil = nil
        hoverSpent = true
        update()
    }

    private func soundIfNewlyLate() {
        // A quiet reminder stays quiet: the user is taken to be in another call.
        guard let showing, showing.phase == .overdue, !showing.quiet,
            escalated.insert(showing.meeting.id).inserted
        else { return }
        remember(showing.meeting)
        guard Preferences.lateSound, !isMuted else { return }
        NSSound(named: "Glass")?.play()
    }

    // MARK: What the panel says

    private func reminderContent(_ reminder: ActiveReminder, at now: Date) -> NotchContent {
        let meeting = reminder.meeting
        var detail = "\(time(meeting.start)) – \(time(meeting.end))"
        if reminder.quiet { detail = "Next up · " + detail }
        if reminder.alsoStarting > 0 { detail += " · +\(reminder.alsoStarting) more" }

        let tone: NotchContent.Tone =
            switch reminder.phase {
            case _ where reminder.quiet: .calm
            case .headsUp, .approaching: .calm
            case .upcoming: .soon
            case .countdown: .urgent
            case .started: .live
            case .overdue: .late
            }
        return NotchContent(
            title: meeting.title,
            detail: detail,
            emphasis: TimeLabel.text(for: reminder.phase, meeting: meeting, at: now),
            tone: tone,
            actionLabel: reminder.phase == .headsUp ? nil : meeting.joinURL.map(openLabel),
            compactText: TimeLabel.pill(for: reminder.phase, meeting: meeting, at: now),
            canSnooze: reminder.phase.stage == .main)
    }

    /// The day at a glance: every event today, all-day ones included.
    private func peekContent(at now: Date) -> NotchContent {
        guard hasAccess else {
            return NotchContent(
                title: "Kyo can't see your calendar",
                detail: "Allow it in Privacy & Security → Calendars",
                actionLabel: "Settings")
        }
        // Nothing left today: say what comes first tomorrow.
        let today = Agenda.today(from: meetings, at: now)
        let tomorrow =
            today.contains { $0.status == .next }
            ? nil : meetings.first { !$0.isAllDay && $0.start > now }
        // Keep the panel a sensible height.
        let fitted = Agenda.fitting(today, limit: tomorrow == nil ? 9 : 8)

        var rows = fitted.shown.map { entry in
            let meeting = entry.meeting
            let trailing: String? =
                switch entry.status {
                case .next: TimeLabel.relative(meeting.start.timeIntervalSince(now))
                case .now: "now"
                case .allDay, .past, .later: nil
                }
            return AgendaRow(
                id: meeting.id, time: meeting.isAllDay ? "all-day" : time(meeting.start),
                title: meeting.title, status: entry.status, trailing: trailing,
                hasCall: meeting.joinURL != nil, linkHost: meeting.joinURL.flatMap(siteName))
        }
        if fitted.hidden > 0 {
            rows.append(
                AgendaRow(id: "more", time: "", title: "+\(fitted.hidden) more", status: .later))
        }
        if let tomorrow {
            rows.append(
                AgendaRow(
                    id: tomorrow.id, time: dayAndTime(tomorrow.start), title: tomorrow.title,
                    status: .later, hasCall: tomorrow.joinURL != nil,
                    linkHost: tomorrow.joinURL.flatMap(siteName)))
        }
        return NotchContent(
            title: "Today", detail: now.formatted(.dateTime.weekday(.abbreviated).day().month()),
            agenda: rows)
    }

    /// "Open" for a call service; for any other site the button says where it goes.
    private func openLabel(_ url: URL) -> String {
        siteName(url).map { "Open \($0)" } ?? "Open"
    }

    /// The site's name, when the link is not to a known call service.
    private func siteName(_ url: URL) -> String? {
        MeetingLinkFinder.isCallService(url) ? nil : MeetingLinkFinder.displayHost(url)
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func dayAndTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time(date) }
        if calendar.isDateInTomorrow(date) { return "Tomorrow \(time(date))" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time(date))"
    }

    // MARK: Plumbing

    private func observe(
        _ name: Notification.Name, on center: NotificationCenter = .default,
        _ handler: @escaping @MainActor (ReminderController) -> Void
    ) {
        observers.append(
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { handler(self) }
                }
            })
    }

    /// A few facts for a recorded demo run.
    private func readings() -> String {
        let linked = meetings.filter { $0.joinURL != nil }
        return "pointer events seen: \(hover.eventsSeen)\n"
            + "microphone live: \(Microphone.isLive)\n"
            + "events loaded: \(meetings.count), with a call link: \(linked.count)"
    }
}
