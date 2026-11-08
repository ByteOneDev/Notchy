import SwiftUI

/// A guided tour of Notchy: one animated scene per feature.
@MainActor
final class TourWindowController: NSObject, NSWindowDelegate {
    static let shared = TourWindowController()
    private var window: NSWindow?

    /// Once per install, the first time a version with the tour starts.
    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tourShown") else { return }
        UserDefaults.standard.set(true, forKey: "tourShown")
        show()
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = .black
            window.contentViewController = NSHostingController(rootView: TourView { [weak self] in self?.window?.close() })
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu bar app unless the settings are still open.
        let others = NSApp.windows.filter { $0 !== window && $0.isVisible && $0.styleMask.contains(.titled) }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}

enum TourScene: Int, CaseIterable, Identifiable {
    case welcome, open, panels, nook, activities, shelf, modes, agents, settings
    var id: Int { rawValue }
    var title: String { L("tour.\(self).title") }
    var text: String { L("tour.\(self).text") }
}

struct TourView: View {
    let close: () -> Void
    @State private var scene: TourScene = .welcome
    @State private var forward = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RadialGradient(colors: [Color(red: 0.2, green: 0.12, blue: 0.35), .black], center: .top, startRadius: 20, endRadius: 420)
                TourIllustration(scene: scene)
                    .id(scene)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(height: 300)
            .clipped()
            VStack(spacing: 10) {
                Text(scene.title).font(.system(size: 22, weight: .bold))
                    .id("title\(scene.rawValue)").transition(.opacity)
                Text(scene.text).font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center).frame(maxWidth: 500).fixedSize(horizontal: false, vertical: true)
                    .id("text\(scene.rawValue)").transition(.opacity)
            }
            .padding(.top, 22)
            .padding(.horizontal, 30)
            Spacer(minLength: 0)
            footer.padding(.horizontal, 26).padding(.bottom, 22)
        }
        .frame(width: 680, height: 520)
        .background(Color.black)
        .foregroundStyle(.white)
        .environment(\.locale, Loc.locale)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { go(by: 1); return .handled }
        .onKeyPress(.leftArrow) { go(by: -1); return .handled }
    }

    private var footer: some View {
        HStack {
            Button(L("tour.skip")) { close() }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.45))
                .opacity(scene == TourScene.allCases.last ? 0 : 1)
            Spacer()
            HStack(spacing: 7) {
                ForEach(TourScene.allCases) { item in
                    Capsule().fill(item == scene ? Color.white : Color.white.opacity(0.25))
                        .frame(width: item == scene ? 18 : 7, height: 7)
                        .onTapGesture { jump(to: item) }
                }
            }
            .animation(.snappy, value: scene)
            Spacer()
            HStack(spacing: 8) {
                if scene != .welcome {
                    Button(L("tour.back")) { go(by: -1) }.buttonStyle(TourButtonStyle(primary: false))
                }
                if scene == TourScene.allCases.last {
                    Button(L("tour.done")) {
                        close()
                        SettingsWindowController.shared.show(pane: .features)
                    }
                    .buttonStyle(TourButtonStyle(primary: true))
                } else {
                    Button(scene == .welcome ? L("tour.start") : L("tour.next")) { go(by: 1) }
                        .buttonStyle(TourButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func go(by step: Int) {
        guard let next = TourScene(rawValue: scene.rawValue + step) else { return }
        jump(to: next)
    }

    private func jump(to next: TourScene) {
        forward = next.rawValue > scene.rawValue
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { scene = next }
    }
}

struct TourButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primary ? .black : .white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.12)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(Capsule())
    }
}

/// One tour page as it first appears, for the snapshots.
struct TourPageSnapshot: View {
    let scene: TourScene

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RadialGradient(colors: [Color(red: 0.2, green: 0.12, blue: 0.35), .black], center: .top, startRadius: 20, endRadius: 420)
                TourIllustration(scene: scene)
            }
            .frame(height: 300)
            VStack(spacing: 10) {
                Text(scene.title).font(.system(size: 22, weight: .bold))
                Text(scene.text).font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center).frame(maxWidth: 500).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .frame(width: 680, height: 460)
        .background(Color.black)
        .foregroundStyle(.white)
    }
}
