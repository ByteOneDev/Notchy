import AppKit
import Combine

@main
enum NotchyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        _ = LockScreenManager.shared
        NowPlayingService.shared.start()
        BatteryMonitor.shared.start()
        BluetoothMonitor.shared.start()
        MediaKeyMonitor.shared.start()
        CapsLockMonitor.shared.start()
        PrivacyMonitor.shared.start()
        CalendarService.shared.start()
        WeatherService.shared.start()
        DeviceBatteryMonitor.shared.start()
        DisplayMonitor.shared.start()
        FocusMonitor.shared.start()
        AgentHub.shared.start()
        HotKeyCenter.shared.start()
        NotchManager.shared.start()

        AppSettings.shared.$showMenuBarIcon
            .sink { [weak self] show in self?.setStatusItemVisible(show) }
            .store(in: &cancellables)
        AppSettings.shared.$language
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildMenu() } }
            .store(in: &cancellables)

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            SettingsWindowController.shared.show(pane: .permissions)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    private func setStatusItemVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Self.menuBarGlyph
            statusItem = item
            rebuildMenu()
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// The logo reduced to a template glyph: a screen outline with its notch.
    static let menuBarGlyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { _ in
            let screen = NSBezierPath(roundedRect: NSRect(x: 1, y: 1.5, width: 16, height: 11.5), xRadius: 3, yRadius: 3)
            screen.lineWidth = 1.5
            NSColor.black.setStroke()
            screen.stroke()
            let notch = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 0.75, width: 7, height: 4.5), xRadius: 1.8, yRadius: 1.8)
            NSColor.black.setFill()
            notch.fill()
            NSRect(x: 5.5, y: 0.75, width: 7, height: 2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private func rebuildMenu() {
        guard let statusItem else { return }
        statusItem.menu = Self.makeMenu(target: self)
    }

    static func makeMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L("menu.open"), action: #selector(openNotch), keyEquivalent: "").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",").target = target
        menu.addItem(withTitle: L("menu.updates"), action: #selector(checkUpdates), keyEquivalent: "").target = target
        menu.addItem(.separator())
        menu.addItem(withTitle: L("menu.quit"), action: #selector(quit), keyEquivalent: "q").target = target
        return menu
    }

    @objc func openNotch() { NotchManager.shared.openPrimary() }
    @objc func openSettings() { SettingsWindowController.shared.show() }
    @objc func checkUpdates() { UpdateChecker.shared.check(userInitiated: true) }
    @objc func quit() { NSApp.terminate(nil) }
}
