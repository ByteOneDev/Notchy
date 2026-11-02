import AppKit
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, music, calendar, shelf, teleprompter, agents, timer, mirror
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "rectangle.topthird.inset.filled"
        case .music: "play.fill"
        case .calendar: "calendar"
        case .shelf: "tray.fill"
        case .teleprompter: "text.alignleft"
        case .agents: "sparkle"
        case .timer: "timer"
        case .mirror: "person.crop.square.fill"
        }
    }

    var title: String { L("tab.\(rawValue)") }

    /// Each panel's own size (content below the notch row), at the default scale.
    var baseSize: CGSize {
        switch self {
        case .home: CGSize(width: 860, height: 170)
        case .music: CGSize(width: 620, height: 168)
        case .calendar: CGSize(width: 740, height: 210)
        case .shelf: CGSize(width: 700, height: 148)
        case .teleprompter: CGSize(width: 660, height: 220)
        case .agents: CGSize(width: 780, height: 196)
        case .timer: CGSize(width: 660, height: 156)
        case .mirror: CGSize(width: 600, height: 210)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }

    /// Size of the hardware notch, nil on screens without one.
    var hardwareNotchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }

    /// Notch to draw: the hardware one, or a simulated one sized like the menu bar.
    var notchSize: CGSize {
        if let size = hardwareNotchSize { return size }
        let menuBar = frame.maxY - visibleFrame.maxY
        return CGSize(width: 190, height: max(24, min(menuBar, 32)))
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    enum State { case closed, open }

    @Published private(set) var state: State = .closed
    @Published var tab: NotchTab = .home
    @Published var hovering = false
    @Published var hiddenForFullscreen = false
    @Published var dropTargeted = false
    /// Size of the notch shape as currently drawn; used for mouse hit testing.
    @Published var shapeSize: CGSize = .zero

    let displayID: CGDirectDisplayID
    let notchSize: CGSize
    let hasHardwareNotch: Bool

    /// The window: big enough for the largest panel plus the panel bar and the shadow.
    static var canvasSize: CGSize {
        let sizes = NotchTab.allCases.map(panelSize(for:))
        return CGSize(width: (sizes.map(\.width).max() ?? 860) + 140,
                      height: (sizes.map(\.height).max() ?? 170) + 140)
    }

    /// Size of a panel below the notch row: its own size when adaptive, else the Nook's,
    /// scaled by the width and height set in the settings.
    static func panelSize(for tab: NotchTab) -> CGSize {
        let settings = AppSettings.shared
        let base = settings.adaptiveSize ? tab.baseSize : NotchTab.home.baseSize
        let widthScale = settings.openWidth / AppSettings.defaultOpenWidth
        let heightScale = settings.openHeight / AppSettings.defaultOpenHeight
        return CGSize(width: (base.width * widthScale).rounded(), height: (base.height * heightScale).rounded())
    }

    init(screen: NSScreen) {
        displayID = screen.displayID
        notchSize = screen.notchSize
        hasHardwareNotch = screen.hardwareNotchSize != nil
        shapeSize = notchSize
    }

    var isOpen: Bool { state == .open }

    var openSize: CGSize {
        let panel = Self.panelSize(for: tab)
        // Never narrower than the notch plus the header on each side of it.
        return CGSize(width: max(panel.width, notchSize.width + 380), height: notchSize.height + panel.height)
    }

    func open(tab: NotchTab? = nil) {
        // In full screen the notch stays out of the way.
        guard !hiddenForFullscreen else { return }
        if let tab { self.tab = tab }
        guard state != .open else { return }
        Haptics.tap()
        Sounds.play(.open)
        withAnimation(.notchOpen) { state = .open }
    }

    func close() {
        guard state != .closed else { return }
        withAnimation(.notchClose) { state = .closed }
        if tab == .mirror { tab = .home }
    }

    func toggle() { isOpen ? close() : open() }

    /// Panels shown in the bar, according to what is enabled in the settings.
    var availableTabs: [NotchTab] {
        let settings = AppSettings.shared
        return NotchTab.allCases.filter { tab in
            switch tab {
            case .music: settings.mediaEnabled
            case .calendar: settings.calendarEnabled
            case .shelf: settings.shelfEnabled
            case .teleprompter: settings.teleprompterEnabled
            case .agents: settings.agentsEnabled
            case .mirror: settings.mirrorEnabled
            case .timer: settings.timerEnabled
            case .home: true
            }
        }
    }

    // MARK: Trackpad gestures

    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var gestureConsumed = false

    func handleScroll(_ event: NSEvent) {
        guard !hiddenForFullscreen else { return }
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty && !gestureConsumed && scrollX == 0 && scrollY == 0) {
            scrollX = 0; scrollY = 0; gestureConsumed = false
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollX = 0; scrollY = 0; gestureConsumed = false
            return
        }
        guard event.momentumPhase.isEmpty, !gestureConsumed else { return }
        let natural = event.isDirectionInvertedFromDevice
        // Deltas in the direction the fingers move.
        scrollX += event.scrollingDeltaX * (natural ? 1 : -1)
        scrollY += event.scrollingDeltaY * (natural ? 1 : -1)

        // In the teleprompter, vertical scrolling moves the text instead of closing the notch.
        if isOpen, tab == .teleprompter, !Teleprompter.shared.isEditing, abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            Teleprompter.shared.nudge(by: -event.scrollingDeltaY * (natural ? 1 : -1))
            scrollX = 0; scrollY = 0
            return
        }

        // Over the calendar, a horizontal swipe walks through the days, one day every 45 pt.
        if isOpen, tab == .home || tab == .calendar, CalendarService.shared.isHovered, abs(scrollX) > 45, abs(scrollX) > abs(scrollY) {
            Haptics.tap()
            // Fingers moving left = next day, like turning pages.
            CalendarService.shared.moveSelection(by: scrollX < 0 ? 1 : -1)
            scrollX = 0
            return
        }

        if abs(scrollX) > 60, abs(scrollX) > abs(scrollY) * 1.5 {
            gestureConsumed = true
            guard AppSettings.shared.swipeToChangeTrack, NowPlayingService.shared.track != nil else { return }
            Haptics.tap()
            // Fingers moving right = previous track, left = next, like swiping cards.
            scrollX > 0 ? NowPlayingService.shared.previous() : NowPlayingService.shared.next()
        } else if abs(scrollY) > 30, abs(scrollY) > abs(scrollX) {
            gestureConsumed = true
            // Closed: a two-finger swipe either way opens. Open: swiping up closes.
            if !isOpen { open() } else if scrollY < 0, !isPinned { close() }
        }
    }

    /// The notch stays open while the teleprompter is being read or edited.
    var isPinned: Bool {
        switch tab {
        case .teleprompter: Teleprompter.shared.isRunning || Teleprompter.shared.isEditing
        case .mirror: CalendarService.shared.prepEvent != nil
        case .agents: !AgentHub.shared.pendingPermissions.isEmpty
        default: false
        }
    }
}

extension Animation {
    static let notchOpen = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let notchClose = Animation.spring(response: 0.38, dampingFraction: 0.9)
    static let notchActivity = Animation.spring(response: 0.36, dampingFraction: 0.75)
}

enum Haptics {
    @MainActor static func tap() {
        guard AppSettings.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
