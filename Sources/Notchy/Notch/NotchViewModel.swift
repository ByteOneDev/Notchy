import AppKit
import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, timer, mirror
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full.fill"
        case .timer: "timer"
        case .mirror: "person.crop.square.fill"
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

    static let canvasSize = CGSize(width: 780, height: 320)
    static let openWidth: CGFloat = 660
    static let openContentHeight: CGFloat = 178

    init(screen: NSScreen) {
        displayID = screen.displayID
        notchSize = screen.notchSize
        hasHardwareNotch = screen.hardwareNotchSize != nil
        shapeSize = notchSize
    }

    var isOpen: Bool { state == .open }

    var openSize: CGSize {
        CGSize(width: Self.openWidth, height: notchSize.height + Self.openContentHeight)
    }

    func open(tab: NotchTab? = nil) {
        if let tab { self.tab = tab }
        guard state != .open else { return }
        Haptics.tap()
        withAnimation(.notchOpen) { state = .open }
    }

    func close() {
        guard state != .closed else { return }
        withAnimation(.notchClose) { state = .closed }
        if tab == .mirror { tab = .home }
    }

    func toggle() { isOpen ? close() : open() }

    // MARK: Trackpad gestures

    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var gestureConsumed = false

    func handleScroll(_ event: NSEvent) {
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty && !gestureConsumed && scrollX == 0 && scrollY == 0) {
            scrollX = 0; scrollY = 0; gestureConsumed = false
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollX = 0; scrollY = 0; gestureConsumed = false
            return
        }
        guard event.momentumPhase.isEmpty, !gestureConsumed else { return }
        let natural = event.isDirectionInvertedFromDevice
        scrollX += event.scrollingDeltaX * (natural ? 1 : -1)
        scrollY += event.scrollingDeltaY * (natural ? 1 : -1)

        if abs(scrollX) > 60, abs(scrollX) > abs(scrollY) * 1.5 {
            gestureConsumed = true
            guard AppSettings.shared.swipeToChangeTrack, NowPlayingService.shared.track != nil else { return }
            Haptics.tap()
            // Fingers moving right = previous track, left = next, like swiping cards.
            scrollX > 0 ? NowPlayingService.shared.previous() : NowPlayingService.shared.next()
        } else if abs(scrollY) > 40, abs(scrollY) > abs(scrollX) {
            gestureConsumed = true
            // Fingers moving down pulls the notch open, up pushes it closed.
            if scrollY > 0, !isOpen { open() } else if scrollY < 0, isOpen { close() }
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
