import AppKit
import ServiceManagement
import SwiftUI

/// A borderless window that sits over the menu bar and never takes focus.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Above the menu bar and its status items.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would otherwise push the window down below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class NotchHostingView: NSHostingView<NotchView> {
    var menuProvider: (() -> NSMenu)?

    /// The panel is never key, so every click is a "first" click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

@MainActor
final class NotchPanelController: NSObject {
    private let model: NotchModel
    private let panel = NotchPanel()
    /// The state being moved to; `model.state` follows a moment later.
    private var target: NotchState = .closed
    private var pending: DispatchWorkItem?

    var onOpenSettings: () -> Void = {}

    /// Where the panel is, or will next appear.
    private var currentScreen: NSScreen?
    /// The notch on each screen, or the top-centre sliver standing in for one.
    private var notchZones: [CGRect] = []
    /// The notch the pointer is on, if it is on one.
    var notchZone: CGRect {
        let pointer = NSEvent.mouseLocation
        return notchZones.first { $0.contains(pointer) } ?? .zero
    }
    /// Screen rectangle of whatever the panel covers in its current state.
    private(set) var panelZone: CGRect = .zero

    init(model: NotchModel) {
        self.model = model
        super.init()
        let hosting = NotchHostingView(rootView: NotchView(model: model))
        // The notch is exactly the area the safe area tells views to avoid.
        hosting.safeAreaRegions = []
        hosting.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        panel.contentView = hosting
        place()
    }

    /// Moves the panel to `state`, showing `content` (kept as is when nil).
    func present(_ state: NotchState, content: NotchContent?) {
        let oldHeight = model.contentHeight
        if let content {
            model.content = content
            model.contentHeight = content.height
        }
        guard state != target else {
            if target != .closed, pointerScreen != currentScreen {
                // The user has moved to another display: go with them.
                place()
            } else if target == .open, model.contentHeight > oldHeight {
                // Same state, different amount to show: keep the window in step.
                place()
            } else if target == .open, model.contentHeight < oldHeight {
                later { [weak self] in self?.place() }
            }
            return
        }
        let previous = target
        target = state
        pending?.cancel()
        pending = nil

        switch state {
        case .open:
            place()
            panel.orderFrontRegardless()
            settle(into: .open)
        case .compact where previous == .open:
            model.state = .compact
            // Shrink the window once the panel has retracted, so it stops
            // catching clicks meant for whatever is underneath.
            later { [weak self] in self?.place() }
        case .compact:
            place()
            panel.orderFrontRegardless()
            settle(into: .compact)
        case .closed:
            model.state = .closed
            later { [weak self] in
                self?.panel.orderOut(nil)
                self?.model.content = nil
            }
            updateZones()
        }
    }

    /// Lets the current outline draw first, so the change animates from it.
    private func settle(into state: NotchState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.target == state else { return }
            self.model.state = state
        }
    }

    private func later(_ work: @escaping () -> Void) {
        let item = DispatchWorkItem { [weak self] in
            self?.pending = nil
            work()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// The display the user is working on, taken to be the one with the pointer.
    private var pointerScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens
        return screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(pointer) }
            ?? screens.first { $0.safeAreaInsets.top > 0 } ?? screens.first
    }

    /// Sizes the window for the state being shown and lines it up with the
    /// notch of the pointer's screen, or its top centre when it has none.
    func place() {
        guard let screen = pointerScreen else { return }
        currentScreen = screen
        let metrics = NotchMetrics(screen: screen)
        model.metrics = metrics
        updateZones()

        // The pill's window hugs it; the open panel's leaves room for the shadow.
        let shape = metrics.size(
            for: target == .open ? .open : .compact, contentHeight: model.contentHeight)
        let ear = NotchView.ear(for: target)
        let size =
            target == .open
            ? CGSize(
                width: shape.width + 2 * NotchView.margin, height: shape.height + NotchView.margin)
            : CGSize(width: shape.width + 2 * ear, height: shape.height)
        let origin = CGPoint(
            x: screen.frame.minX + metrics.centerX - size.width / 2,
            y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func updateZones() {
        func zone(_ size: CGSize, on screen: NSScreen, metrics: NotchMetrics) -> CGRect {
            // A sliver tall even without a notch, and reaching past the top
            // edge so a pointer pressed against it counts.
            let height = max(size.height, 3)
            return CGRect(
                x: screen.frame.minX + metrics.centerX - size.width / 2,
                y: screen.frame.maxY - height, width: size.width, height: height + 4)
        }
        notchZones = NSScreen.screens.map { screen in
            let metrics = NotchMetrics(screen: screen)
            return zone(metrics.size(for: .closed), on: screen, metrics: metrics)
        }
        if let currentScreen {
            panelZone = zone(
                model.metrics.size(for: target, contentHeight: model.contentHeight),
                on: currentScreen, metrics: model.metrics)
        }
    }

    // MARK: Debugging

    /// Writes what the panel is drawing to a PNG, on grey so the outline shows.
    /// Screenshots of other apps need a permission; an app drawing itself does not.
    func writeSnapshot(to url: URL) {
        guard panel.isVisible, let view = panel.contentView,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor(white: 0.8, alpha: 1).setFill()
            view.bounds.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Where the panel sits relative to its screen, for checking alignment.
    var placement: String {
        let screen = panel.screen?.frame ?? .zero
        return "state \(target), window \(panel.frame) on screen \(screen)\n"
            + "notch zones \(notchZones), panel zone \(panelZone)"
    }

    // MARK: Right-click menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Kyo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Kyo: could not change Launch at Login: \(error.localizedDescription)")
        }
    }
}
