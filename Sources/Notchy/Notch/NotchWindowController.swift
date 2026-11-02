import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 8
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that also forwards trackpad scrolls (swipe gestures) to the notch.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the notch window of one screen and decides when it reacts to the mouse.
@MainActor
final class NotchWindowController {
    let viewModel: NotchViewModel
    let panel: NotchPanel
    private var screen: NSScreen
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var dragPasteboardCount = NSPasteboard(name: .drag).changeCount

    init(screen: NSScreen) {
        self.screen = screen
        viewModel = NotchViewModel(screen: screen)
        panel = NotchPanel(frame: Self.frame(for: screen))

        let hosting = NotchHostingView(rootView: NotchRootView(viewModel: viewModel))
        hosting.onScroll = { [weak viewModel] event in viewModel?.handleScroll(event) }
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.orderFrontRegardless()

        installMouseMonitors()
        observeState()
        LockScreenManager.shared.attach(panel)
    }

    func invalidate() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        LockScreenManager.shared.detach(panel)
        panel.orderOut(nil)
        panel.close()
    }

    func updateFrame() {
        panel.setFrame(Self.frame(for: screen), display: true)
    }

    private static func frame(for screen: NSScreen) -> NSRect {
        let size = NotchViewModel.canvasSize
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Area of the screen (bottom-left origin) where the mouse interacts with the notch.
    private func interactiveRect() -> NSRect {
        var size = viewModel.isOpen ? viewModel.openSize : viewModel.shapeSize
        // The panel bar floats under the open notch.
        if viewModel.isOpen { size.height += NotchRootView.tabBarGap + NotchRootView.tabBarHeight }
        // A little slack around the closed notch makes it easier to hit.
        let slackX: CGFloat = viewModel.isOpen ? 12 : 10
        let slackY: CGFloat = viewModel.isOpen ? 12 : 6
        return NSRect(
            x: screen.frame.midX - size.width / 2 - slackX,
            y: screen.frame.maxY - size.height - slackY,
            width: size.width + slackX * 2,
            height: size.height + slackY
        )
    }

    private func installMouseMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved(event) }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handler($0); return $0 }) { monitors.append(local) }
        let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dragEnded() }
        }
        if let up { monitors.append(up) }
    }

    private func observeState() {
        // Keep the notch (calendar, music…) out of screenshots, recordings and screen sharing.
        AppSettings.shared.$hideFromScreenCapture
            .sink { [weak self] hide in self?.panel.sharingType = hide ? .none : .readOnly }
            .store(in: &cancellables)
        // Without .fullScreenAuxiliary, macOS itself keeps the window out of full-screen spaces.
        AppSettings.shared.$hideInFullscreen
            .sink { [weak self] hide in
                var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                if !hide { behavior.insert(.fullScreenAuxiliary) }
                self?.panel.collectionBehavior = behavior
            }
            .store(in: &cancellables)
        viewModel.$tab
            .removeDuplicates()
            .dropFirst()
            .sink { _ in Haptics.tap() }
            .store(in: &cancellables)
        viewModel.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if state == .open { self.panel.makeKey() }
            }
            .store(in: &cancellables)
        viewModel.$hiddenForFullscreen
            .removeDuplicates()
            .combineLatest(LiveActivityCenter.shared.$current.map { $0 != nil }.removeDuplicates())
            .sink { [weak self] hidden, hasActivity in
                guard let self else { return }
                // In full screen the notch disappears, but HUDs still show up.
                let visible = !hidden || hasActivity
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.panel.animator().alphaValue = visible ? 1 : 0
                }
            }
            .store(in: &cancellables)
    }

    private func mouseMoved(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        guard screen.frame.contains(location) || viewModel.isOpen else { return }
        if viewModel.hiddenForFullscreen || !panel.isOnActiveSpace {
            panel.ignoresMouseEvents = true
            return
        }
        let inside = interactiveRect().contains(location)
        panel.ignoresMouseEvents = !inside

        if event.type == .leftMouseDragged { draggingFiles(at: location) }

        if inside {
            closeWork?.cancel(); closeWork = nil
            if !viewModel.hovering {
                withAnimation(.notchActivity) { viewModel.hovering = true }
                scheduleOpen()
            }
        } else {
            openWork?.cancel(); openWork = nil
            if viewModel.hovering { withAnimation(.notchActivity) { viewModel.hovering = false } }
            if viewModel.isOpen { scheduleClose() }
        }
    }

    private func scheduleOpen() {
        guard AppSettings.shared.openOnHover, !viewModel.isOpen else { return }
        openWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.viewModel.hovering else { return }
                self.viewModel.open()
            }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AppSettings.shared.hoverDelay, execute: work)
    }

    private func scheduleClose() {
        guard closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.closeWork = nil
                guard !self.viewModel.hovering, !self.viewModel.dropTargeted, !self.viewModel.isPinned else { return }
                self.viewModel.close()
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Opens the shelf when files are dragged up to the notch.
    private func draggingFiles(at location: NSPoint) {
        guard AppSettings.shared.shelfEnabled else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragPasteboardCount,
              pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        let zone = interactiveRect().insetBy(dx: -40, dy: -30)
        if zone.contains(location), !viewModel.isOpen {
            viewModel.open(tab: .shelf)
        }
    }

    private func dragEnded() {
        dragPasteboardCount = NSPasteboard(name: .drag).changeCount
    }
}
