import SwiftUI

/// The animated scene of each tour page: a little Mac screen where the notch does its thing,
/// on a loop.
struct TourIllustration: View {
    let scene: TourScene

    var body: some View {
        switch scene {
        case .welcome: WelcomeScene()
        case .open: OpenScene()
        case .panels: PanelsScene()
        case .nook: NookScene()
        case .activities: ActivitiesScene()
        case .shelf: ShelfScene()
        case .modes: ModesScene()
        case .agents: AgentsScene()
        case .settings: SettingsScene()
        }
    }
}

// MARK: Building blocks

/// A small screen with a wallpaper and a menu bar.
private struct MiniScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.24, green: 0.2, blue: 0.5), Color(red: 0.62, green: 0.32, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.black.opacity(0.25)).frame(height: 14)
            content()
        }
        .frame(width: 420, height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}

/// The notch, drawn at the top of a mini screen.
private struct MiniNotch<Content: View>: View {
    var size: CGSize
    var open = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: size.width, height: size.height)
            .background(NotchShape(topRadius: open ? 8 : 4, bottomRadius: open ? 18 : 7).fill(Color.black))
            .clipShape(NotchShape(topRadius: open ? 8 : 4, bottomRadius: open ? 18 : 7))
    }
}

extension MiniNotch where Content == EmptyView {
    init(size: CGSize, open: Bool = false) {
        self.size = size
        self.open = open
        content = { EmptyView() }
    }
}

private let closedNotch = CGSize(width: 96, height: 16)
private let openNotch = CGSize(width: 320, height: 112)

/// A blank line of text in a sketch.
private struct Line: View {
    var width: CGFloat
    var opacity = 0.3
    var body: some View { Capsule().fill(Color.white.opacity(opacity)).frame(width: width, height: 5) }
}

private struct Fingers: View {
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<2, id: \.self) { _ in
                Circle().fill(Color.white.opacity(0.9)).frame(width: 15, height: 15)
                    .shadow(color: .white.opacity(0.6), radius: 6)
            }
        }
    }
}

// MARK: Scenes

private struct WelcomeScene: View {
    private let colors: [Color] = [.pink, .purple, .blue, .orange]

    var body: some View {
        PhaseAnimator(colors.indices) { index in
            ZStack {
                Circle().fill(colors[index]).frame(width: 190, height: 190).blur(radius: 60).opacity(0.75)
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 150, height: 150)
                    .scaleEffect(index % 2 == 0 ? 1 : 1.05)
                    .shadow(color: colors[index].opacity(0.6), radius: 30)
            }
        } animation: { _ in .easeInOut(duration: 1.6) }
    }
}

private struct OpenScene: View {
    enum Step: CaseIterable { case closed, swipeDown, open, swipeUp }

    var body: some View {
        PhaseAnimator(Step.allCases) { step in
            let isOpen = step == .open || step == .swipeUp
            MiniScreen {
                ZStack(alignment: .top) {
                    MiniNotch(size: isOpen ? openNotch : closedNotch, open: isOpen) {
                        if isOpen {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 58, height: 58)
                                VStack(alignment: .leading, spacing: 7) { Line(width: 110, opacity: 0.8); Line(width: 70); Line(width: 130, opacity: 0.2) }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 18).padding(.top, 18)
                            .transition(.opacity)
                        }
                    }
                    Fingers()
                        .offset(y: step == .swipeDown ? 74 : step == .swipeUp ? 60 : isOpen ? 128 : 28)
                        .opacity(step == .swipeDown || step == .swipeUp ? 1 : 0)
                }
            }
        } animation: { step in
            switch step {
            case .closed: .easeInOut(duration: 0.7)
            case .swipeDown: .easeInOut(duration: 0.8)
            case .open: .spring(response: 0.5, dampingFraction: 0.72)
            case .swipeUp: .easeInOut(duration: 1.2)
            }
        }
    }
}

private struct PanelsScene: View {
    private let icons = ["rectangle.topthird.inset.filled", "play.fill", "calendar", "tray.fill", "text.alignleft", "sparkle", "timer"]

    var body: some View {
        PhaseAnimator(icons.indices) { index in
            MiniScreen {
                VStack(spacing: 8) {
                    MiniNotch(size: openNotch, open: true) {
                        VStack(spacing: 8) {
                            Image(systemName: icons[index]).font(.system(size: 28, weight: .semibold))
                                .contentTransition(.symbolEffect(.replace))
                            Line(width: 150, opacity: 0.35)
                        }
                        .padding(.top, 12)
                    }
                    HStack(spacing: 4) {
                        ForEach(icons.indices, id: \.self) { i in
                            Image(systemName: icons[i]).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(i == index ? .black : .white.opacity(0.7))
                                .frame(width: 26, height: 20)
                                .background(Capsule().fill(i == index ? Color.white : Color.clear))
                        }
                    }
                    .padding(4)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                }
            }
        } animation: { _ in .spring(response: 0.4, dampingFraction: 0.8).delay(0.6) }
    }
}

private struct NookScene: View {
    var body: some View {
        PhaseAnimator([false, true, true]) { shown in
            MiniScreen {
                MiniNotch(size: openNotch, open: true) {
                    HStack(spacing: 8) {
                        card(0, shown) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 30, height: 30)
                                AudioVisualizer(color: .pink, playing: true, bars: 4)
                            }
                        }
                        card(1, shown) {
                            VStack(spacing: 2) {
                                Text("SAM.").font(.system(size: 8, weight: .bold)).foregroundStyle(.red)
                                Text("7").font(.system(size: 22, weight: .semibold))
                            }
                        }
                        card(2, shown) {
                            Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 24))
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 26)
                }
            }
        } animation: { _ in .spring(response: 0.5, dampingFraction: 0.75) }
    }

    private func card<C: View>(_ index: Int, _ shown: Bool, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(width: 88, height: 66)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.12), value: shown)
    }
}

private struct ActivitiesScene: View {
    enum Step: CaseIterable { case idle, volume, airpods, battery }

    var body: some View {
        PhaseAnimator(Step.allCases) { step in
            MiniScreen {
                MiniNotch(size: CGSize(width: step == .idle ? closedNotch.width : 230, height: 22)) {
                    HStack {
                        switch step {
                        case .idle: EmptyView()
                        case .volume:
                            Image(systemName: "speaker.wave.2.fill")
                            Spacer()
                            Capsule().fill(Color.white).frame(width: 52, height: 4)
                        case .airpods:
                            Image(systemName: "airpodspro")
                            Spacer()
                            Text("82").font(.system(size: 9, weight: .bold)).padding(4).background(Circle().stroke(Color.green, lineWidth: 2))
                        case .battery:
                            Image(systemName: "bolt.fill").foregroundStyle(.green)
                            Spacer()
                            Text("64 %").font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .transition(.opacity)
                }
            }
        } animation: { _ in .spring(response: 0.45, dampingFraction: 0.75).delay(0.5) }
    }
}

private struct ShelfScene: View {
    enum Step: CaseIterable { case start, drag, drop }

    var body: some View {
        PhaseAnimator(Step.allCases) { step in
            MiniScreen {
                ZStack(alignment: .top) {
                    MiniNotch(size: step == .drop ? CGSize(width: 240, height: 80) : CGSize(width: step == .drag ? 120 : closedNotch.width, height: step == .drag ? 22 : 16),
                              open: step == .drop) {
                        if step == .drop {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.richtext.fill").font(.system(size: 26)).foregroundStyle(.blue)
                                Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 18))
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18))
                            }
                            .padding(.top, 14)
                        }
                    }
                    .overlay {
                        if step == .drag {
                            NotchShape(topRadius: 4, bottomRadius: 7).stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        }
                    }
                    Image(systemName: "doc.richtext.fill").font(.system(size: 30)).foregroundStyle(.white)
                        .offset(x: step == .start ? -150 : 0, y: step == .start ? 170 : 14)
                        .opacity(step == .drop ? 0 : 1)
                        .scaleEffect(step == .drag ? 0.7 : 1)
                }
            }
        } animation: { step in step == .drag ? .easeInOut(duration: 1.1) : .spring(response: 0.5, dampingFraction: 0.75).delay(0.4) }
    }
}

private struct ModesScene: View {
    var body: some View {
        PhaseAnimator([false, true]) { on in
            MiniScreen {
                VStack(spacing: 16) {
                    MiniNotch(size: CGSize(width: on ? 190 : closedNotch.width, height: on ? 22 : 16)) {
                        if on {
                            HStack {
                                Image(systemName: "brain.head.profile").foregroundStyle(.purple)
                                Spacer()
                                Text("Focus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.purple)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                        }
                    }
                    // A browser tab that the mode blocks.
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in Circle().fill([Color.red, .yellow, .green][i]).frame(width: 6, height: 6) }
                            Spacer()
                            Text(on ? "127.0.0.1" : "youtube.com").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                            Spacer()
                        }
                        ZStack {
                            if on {
                                VStack(spacing: 4) {
                                    Text("🌙").font(.system(size: 22))
                                    Text(L("tour.modes.blocked")).font(.system(size: 11, weight: .semibold))
                                }
                                .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "play.rectangle.fill").font(.system(size: 34)).foregroundStyle(.red)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(8)
                    .frame(width: 220, height: 120)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.6)))
                }
            }
        } animation: { _ in .spring(response: 0.5, dampingFraction: 0.75).delay(1.0) }
    }
}

private struct AgentsScene: View {
    enum Step: CaseIterable { case working, asking, approved }

    var body: some View {
        PhaseAnimator(Step.allCases) { step in
            MiniScreen {
                MiniNotch(size: step == .asking ? CGSize(width: 280, height: 90) : CGSize(width: 190, height: 22), open: step == .asking) {
                    switch step {
                    case .working:
                        HStack {
                            AgentGlyph(name: "Claude", size: 12)
                            Spacer()
                            ProgressView().controlSize(.mini).tint(.orange)
                        }
                        .padding(.horizontal, 10)
                    case .asking:
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                AgentGlyph(name: "Claude", size: 12)
                                Text("Bash · npm test").font(.system(size: 11, weight: .semibold, design: .monospaced))
                            }
                            HStack(spacing: 8) {
                                Text(L("tour.agents.allow")).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.green))
                                Text(L("tour.agents.deny")).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.15)))
                            }
                        }
                        .padding(.top, 14)
                    case .approved:
                        HStack {
                            AgentGlyph(name: "Claude", size: 12)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                    }
                }
            }
        } animation: { _ in .spring(response: 0.5, dampingFraction: 0.75).delay(0.9) }
    }
}

private struct SettingsScene: View {
    var body: some View {
        PhaseAnimator([0, 1, 2, 3]) { step in
            HStack(spacing: 34) {
                Image(systemName: "gearshape.fill").font(.system(size: 92)).foregroundStyle(.white.opacity(0.85))
                    .rotationEffect(.degrees(Double(step) * 60))
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<4, id: \.self) { row in
                        let on = (row + step) % 3 != 0
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 5).fill([Color.pink, .blue, .purple, .orange][row]).frame(width: 18, height: 18)
                            Line(width: 90, opacity: 0.5)
                            Capsule().fill(on ? Color.green : Color.white.opacity(0.2)).frame(width: 30, height: 18)
                                .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 14, height: 14).padding(2) }
                        }
                    }
                }
            }
        } animation: { _ in .spring(response: 0.5, dampingFraction: 0.7).delay(0.7) }
    }
}
