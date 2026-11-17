import AppKit
import KyoCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ReminderController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        // `--demo` plays a made-up day through every phase in about a minute and a half.
        // Add `--busy` to pretend a call is in progress and see the quieter reminder.
        let arguments = CommandLine.arguments
        let demo = arguments.contains("--demo")
        let busy = demo && arguments.contains("--busy")
        let controller = ReminderController(
            source: demo ? DemoSource(busy: busy) : CalendarSource(),
            config: demo ? DemoSource.config : nil,
            micIsLive: busy ? { true } : { Microphone.isLive })
        // Demo only: on the real calendar it would write meeting titles to disk.
        if demo, let flag = arguments.firstIndex(of: "--snapshot"),
            arguments.indices.contains(flag + 1)
        {
            controller.diagnostics = Diagnostics(
                directory: URL(fileURLWithPath: arguments[flag + 1]))
            controller.isMuted = true
        }
        self.controller = controller
        controller.start()

        if !demo { enableLaunchAtLoginOnce() }
    }

    /// Opening Kyo while it is already running shows what is next.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller?.peek()
        return false
    }

    /// A reminder that is not running reminds nobody, so the installed copy
    /// starts at login unless that is later switched off from the menu.
    private func enableLaunchAtLoginOnce() {
        let key = "didEnableLaunchAtLogin"
        guard !UserDefaults.standard.bool(forKey: key),
            Bundle.main.bundlePath.hasPrefix("/Applications/")
        else { return }
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            NSLog("Kyo: could not enable Launch at Login: \(error.localizedDescription)")
        }
    }
}
