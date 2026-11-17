import AppKit

/// A record of a demo run (`--demo --snapshot <dir>`): a picture of the panel
/// after every change, a log of clicks and hovers, and a few readings. It is
/// how the app is checked where screenshots are not possible. Never used on a
/// real calendar, so no real meeting title is written to disk.
@MainActor
final class Diagnostics {
    private let directory: URL
    private let started = Date()

    init(directory: URL) {
        self.directory = directory
    }

    private var elapsed: Int { Int(Date().timeIntervalSince(started)) }

    /// Appends one line to `events.txt`.
    func note(_ event: String) {
        let url = directory.appendingPathComponent("events.txt")
        let line = String(format: "%03d %@\n", elapsed, event)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + line).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes `<seconds>.png` and refreshes `notes.txt` once the panel has settled.
    func snapshot(of panel: NotchPanelController, readings: String) {
        let name = String(format: "%03d.png", elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [directory] in
            panel.writeSnapshot(to: directory.appendingPathComponent(name))
            try? "\(panel.placement)\n\(readings)\n".write(
                to: directory.appendingPathComponent("notes.txt"), atomically: true,
                encoding: .utf8)
        }
    }
}
