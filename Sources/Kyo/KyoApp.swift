import AppKit

@main
@MainActor
enum KyoApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // No Dock icon, no menu bar item: the notch panel is the whole interface.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
