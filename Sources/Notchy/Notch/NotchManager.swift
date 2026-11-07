import AppKit
import Combine

/// Creates one notch window per target screen and keeps them in sync with the display setup.
@MainActor
final class NotchManager {
    static let shared = NotchManager()

    private(set) var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var fullscreenTimer: Timer?

    func start() {
        rebuild()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        AppSettings.shared.$displayTarget
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuild() } }
            .store(in: &cancellables)
        // The window is sized after the open notch: resize it once the sliders settle.
        AppSettings.shared.$openWidth.combineLatest(AppSettings.shared.$openHeight, AppSettings.shared.$adaptiveSize)
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.resizeWindows() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification))
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.updateFullscreen() }
            }
            .store(in: &cancellables)
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullscreen() }
        }
    }

    /// The notch the user most likely looks at: the one under the mouse, else the first one.
    var primaryViewModel: NotchViewModel? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           let controller = controllers[screen.displayID] {
            return controller.viewModel
        }
        return controllers.values.first?.viewModel
    }

    /// A full-screen app hides the notch under the mouse: it must not open, and the system
    /// HUDs take over for volume and brightness.
    var isFullscreenActive: Bool {
        guard let controller = primaryController else { return false }
        return controller.viewModel.hiddenForFullscreen || !controller.panel.isOnActiveSpace
    }

    private var primaryController: NotchWindowController? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }), let controller = controllers[screen.displayID] {
            return controller
        }
        return controllers.values.first
    }

    func openPrimary(tab: NotchTab? = nil) {
        guard !isFullscreenActive else { return }
        primaryViewModel?.open(tab: tab)
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch AppSettings.shared.displayTarget {
        case .all:
            return screens
        case .main:
            return NSScreen.main.map { [$0] } ?? Array(screens.prefix(1))
        case .builtIn:
            if let builtIn = screens.first(where: { $0.isBuiltIn }) { return [builtIn] }
            return NSScreen.main.map { [$0] } ?? Array(screens.prefix(1))
        }
    }

    private func resizeWindows() {
        controllers.values.forEach { $0.updateFrame() }
    }

    func rebuild() {
        controllers.values.forEach { $0.invalidate() }
        controllers.removeAll()
        for screen in targetScreens() {
            controllers[screen.displayID] = NotchWindowController(screen: screen)
        }
    }

    private func updateFullscreen() {
        let enabled = AppSettings.shared.hideInFullscreen
        let fullscreenDisplays = enabled ? Self.fullscreenSpaceDisplays().union(Self.displaysWithFullscreenWindow()) : []
        for (id, controller) in controllers {
            let hidden = fullscreenDisplays.contains(id)
            if controller.viewModel.hiddenForFullscreen != hidden {
                controller.viewModel.hiddenForFullscreen = hidden
                if hidden { controller.viewModel.close() }
            }
        }
    }

    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias ManagedSpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let managedSpaces: (connection: ConnectionFn, copy: ManagedSpacesFn)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let connection = dlsym(handle, "SLSMainConnectionID"),
              let copy = dlsym(handle, "SLSCopyManagedDisplaySpaces") else { return nil }
        return (unsafeBitCast(connection, to: ConnectionFn.self), unsafeBitCast(copy, to: ManagedSpacesFn.self))
    }()

    /// Displays showing a full-screen app's Space (green button), whichever app is in front.
    /// Read from the window server (SkyLight, private): Space type 4 is a full-screen Space.
    private static func fullscreenSpaceDisplays() -> Set<CGDirectDisplayID> {
        guard let api = managedSpaces,
              let displays = api.copy(api.connection())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result = Set<CGDirectDisplayID>()
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any], current["type"] as? Int == 4 else { continue }
            let identifier = display["Display Identifier"] as? String
            for screen in NSScreen.screens {
                // "Main" when all displays share their Spaces.
                guard identifier == "Main" || identifier == screen.uuidString else { continue }
                result.insert(screen.displayID)
            }
        }
        return result
    }

    /// The menu bar is a Window Server window at the main menu level along the top of the display.
    private static func menuBarWindowVisible(on display: CGRect, windows: [[String: Any]]) -> Bool {
        windows.contains { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "Window Server",
                  (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return abs(bounds.minY - display.minY) < 2 && bounds.intersects(display)
        }
    }

    /// Displays where the frontmost app has a window covering the whole screen, menu bar included.
    private static func displaysWithFullscreenWindow() -> Set<CGDirectDisplayID> {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontPID != ProcessInfo.processInfo.processIdentifier,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var result = Set<CGDirectDisplayID>()
        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == frontPID,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            for screen in NSScreen.screens {
                let display = CGDisplayBounds(screen.displayID)
                if bounds.equalTo(display) {
                    result.insert(screen.displayID)
                    continue
                }
                // On notched screens full-screen apps stop under the notch. Tell them apart from
                // a merely maximized window by the menu bar, which is hidden in full screen.
                let topInset = max(screen.safeAreaInsets.top, 1)
                let coversBelowNotch = abs(bounds.width - display.width) < 1
                    && bounds.minY - display.minY <= topInset + 1
                    && bounds.maxY >= display.maxY - 1
                let menuBarHidden = screen.visibleFrame.maxY >= screen.frame.maxY - 1
                    || !menuBarWindowVisible(on: display, windows: info)
                if coversBelowNotch, menuBarHidden { result.insert(screen.displayID) }
            }
        }
        return result
    }
}
