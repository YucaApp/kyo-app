import AppKit
import SwiftUI

/// The small settings window, opened from the panel's right-click menu.
@MainActor
final class SettingsWindow {
    private let source: MeetingSource
    private let onChange: () -> Void
    private var window: NSWindow?

    init(source: MeetingSource, onChange: @escaping () -> Void) {
        self.source = source
        self.onChange = onChange
    }

    func show() {
        // Built fresh each time, so the calendar list is current.
        let view = SettingsView(calendars: source.calendars(), onChange: onChange)
        let window =
            self.window
            ?? {
                let window = NSWindow(
                    contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered,
                    defer: false)
                window.title = "Kyo Settings"
                window.isReleasedWhenClosed = false
                return window
            }()
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        self.window = window
        // Kyo has no Dock icon, so it has to step forward to show a normal window.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    let calendars: [CalendarInfo]
    let onChange: () -> Void

    @State private var leadMinutes = Preferences.leadMinutes
    @State private var snoozeSeconds = Preferences.snoozeSeconds
    @State private var lateSound = Preferences.lateSound
    @State private var quietInCalls = Preferences.quietInCalls
    @State private var ignoreUnanswered = Preferences.ignoreUnanswered
    @State private var hidden = Preferences.hiddenCalendars

    var body: some View {
        Form {
            Section("Reminder") {
                Picker("Drop the panel", selection: $leadMinutes) {
                    ForEach(Preferences.leadChoices, id: \.self) { minutes in
                        Text("\(minutes) min before").tag(minutes)
                    }
                }
                Picker("Snooze for", selection: $snoozeSeconds) {
                    ForEach(Preferences.snoozeChoices, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) min").tag(seconds)
                    }
                }
                Toggle("Play a sound when a meeting started a minute ago", isOn: $lateSound)
                Toggle("Stay quiet while the microphone is in use", isOn: $quietInCalls)
            }

            Section("Calendars") {
                Toggle("Ignore invitations I have not answered", isOn: $ignoreUnanswered)
                if calendars.isEmpty {
                    Text("No calendars to show.")
                        .foregroundStyle(.secondary)
                }
                ForEach(calendars) { calendar in
                    Toggle(isOn: shown(calendar.id)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(nsColor: calendar.color))
                                .frame(width: 9, height: 9)
                            Text(calendar.title)
                            Text(calendar.account)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 320, maxHeight: 560)
        .onChange(of: leadMinutes) { _, value in
            Preferences.leadMinutes = value
            onChange()
        }
        .onChange(of: snoozeSeconds) { _, value in Preferences.snoozeSeconds = value }
        .onChange(of: lateSound) { _, value in Preferences.lateSound = value }
        .onChange(of: quietInCalls) { _, value in
            Preferences.quietInCalls = value
            onChange()
        }
        .onChange(of: ignoreUnanswered) { _, value in
            Preferences.ignoreUnanswered = value
            onChange()
        }
        .onChange(of: hidden) { _, value in
            Preferences.hiddenCalendars = value
            onChange()
        }
    }

    private func shown(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(id) },
            set: { isShown in
                if isShown { hidden.remove(id) } else { hidden.insert(id) }
            })
    }
}
