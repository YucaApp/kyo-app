import AppKit

/// Tells its owner when the pointer rests on the notch, and when it has left the panel.
///
/// Hovering starts only on the notch itself, so a pointer that happens to sit
/// where the panel drops does not count. Once started it lasts while the
/// pointer stays anywhere on the panel.
@MainActor
final class HoverTracker {
    /// Where hovering can begin: the notch.
    var entryZone: () -> CGRect = { .zero }
    /// Where hovering continues: whatever the panel currently covers.
    var stayZone: () -> CGRect = { .zero }
    var onChange: (Bool) -> Void = { _ in }

    /// How many pointer events have arrived; for checking the monitor works.
    private(set) var eventsSeen = 0

    private var inside = false
    private var reported = false
    private var settle: DispatchWorkItem?
    private var monitors: [Any] = []
    private var watchdog: Timer?

    func start() {
        let moved: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        // Global: pointer movement while another app is active, which is always,
        // since Kyo never becomes active.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: moved,
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            })
        {
            monitors.append(monitor)
        }
        // Local: the same while one of Kyo's own menus is open.
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: moved,
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved() }
                return event
            })
        {
            monitors.append(monitor)
        }
    }

    private func pointerMoved() {
        eventsSeen += 1
        evaluate()
    }

    private func evaluate() {
        let zone = reported ? stayZone() : entryZone()
        let now = zone.contains(NSEvent.mouseLocation)
        guard now != inside else { return }
        inside = now
        settle?.cancel()
        // A short dwell, so a pointer passing through does not open the panel,
        // and a slip off the edge does not close it.
        let work = DispatchWorkItem { [weak self] in self?.report() }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (now ? 0.18 : 0.3), execute: work)
    }

    private func report() {
        guard inside != reported else { return }
        reported = inside
        watchdog?.invalidate()
        watchdog = nil
        if inside {
            // The panel can change shape under a still pointer; keep checking.
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            watchdog = timer
        }
        onChange(inside)
    }
}
