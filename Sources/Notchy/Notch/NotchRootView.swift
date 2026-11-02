import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var activities = LiveActivityCenter.shared
    @ObservedObject private var media = NowPlayingService.shared
    @ObservedObject private var lock = LockScreenManager.shared
    @ObservedObject private var pomodoro = PomodoroTimer.shared
    @ObservedObject private var quickTimer = QuickTimer.shared
    @ObservedObject private var agents = AgentHub.shared

    static let tabBarHeight: CGFloat = 36
    static let tabBarGap: CGFloat = 8

    var body: some View {
        VStack(spacing: Self.tabBarGap) {
            notch
            if viewModel.isOpen {
                PanelBar(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -14)).combined(with: .scale(scale: 0.9, anchor: .top))
                            .animation(.notchOpen.delay(0.08)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
            }
            Spacer(minLength: 0)
        }
        .frame(width: NotchViewModel.canvasSize.width, height: NotchViewModel.canvasSize.height, alignment: .top)
        .environment(\.locale, settings.language.locale)
        .preferredColorScheme(.dark)
    }

    private var compact: CompactLayout {
        CompactLayout.make(
            activity: activities.current,
            media: media,
            locked: lock.isLocked,
            justUnlocked: lock.justUnlocked,
            pomodoro: pomodoro,
            timer: quickTimer,
            notchHeight: viewModel.notchSize.height
        )
    }

    private var closedSize: CGSize {
        let layout = compact
        let bump: CGFloat = viewModel.hovering && !layout.isEmpty ? 6 : (viewModel.hovering ? 14 : 0)
        let sideWidths = layout.isEmpty ? 0 : layout.leftWidth + layout.rightWidth
        return CGSize(
            width: viewModel.notchSize.width + sideWidths + bump,
            height: viewModel.notchSize.height + layout.bottomHeight + (viewModel.hovering ? 3 : 0)
        )
    }

    private var size: CGSize { viewModel.isOpen ? viewModel.openSize : closedSize }

    /// A thin outline in the artwork's color around the closed notch while sound plays.
    private var showsAudioGlow: Bool {
        settings.audioGlow && !viewModel.isOpen && media.track?.isPlaying == true
    }

    private var shape: NotchShape {
        viewModel.isOpen
            ? NotchShape(topRadius: 12, bottomRadius: 32)
            : NotchShape(topRadius: 6, bottomRadius: compact.bottomHeight > 0 ? 18 : 11)
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            if viewModel.isOpen {
                OpenNotchView(viewModel: viewModel)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(.notchOpen.delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    ))
            } else {
                ClosedNotchView(layout: compact, notchSize: viewModel.notchSize)
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(NotchBackground(appearance: settings.appearance, isOpen: viewModel.isOpen, shape: shape))
        .clipShape(shape)
        .overlay {
            if viewModel.dropTargeted {
                shape.stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            } else if showsAudioGlow {
                AudioGlow(shape: shape, color: media.accent)
                    .transition(.opacity.animation(.easeInOut(duration: 0.5)))
            }
        }
        .shadow(color: .black.opacity(viewModel.isOpen ? 0.5 : 0), radius: 14, y: 6)
        .contentShape(shape)
        .onTapGesture {
            if !viewModel.isOpen { viewModel.open() }
        }
        .contextMenu {
            Button(L("menu.settings")) { SettingsWindowController.shared.show() }
            Button(L("menu.quit")) { NSApp.terminate(nil) }
        }
        .onDrop(of: [.fileURL], isTargeted: $viewModel.dropTargeted) { providers in
            guard settings.shelfEnabled else { return false }
            ShelfStore.shared.add(providers: providers)
            viewModel.open(tab: .shelf)
            return true
        }
        .animation(.notchOpen, value: viewModel.isOpen)
        .animation(.notchActivity, value: size)
        .onChange(of: size, initial: true) { _, newSize in viewModel.shapeSize = newSize }
    }
}

/// Outline that breathes slowly in the color of what is playing.
struct AudioGlow: View {
    let shape: NotchShape
    let color: Color

    var body: some View {
        NotchOutline(topRadius: shape.topRadius, bottomRadius: shape.bottomRadius, extendBottom: 2.5)
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .shadow(color: color.opacity(0.95), radius: 4)
            .shadow(color: color.opacity(0.65), radius: 12)
            .phaseAnimator([0.55, 1.0]) { content, phase in
                content.opacity(phase)
            } animation: { _ in .easeInOut(duration: 1.8) }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.6), value: color)
    }
}

/// The floating bar of panels under the open notch. The selected panel shows its name.
struct PanelBar: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var agents = AgentHub.shared
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(viewModel.availableTabs) { tab in
                let selected = viewModel.tab == tab
                Button {
                    withAnimation(.snappy(duration: 0.28)) { viewModel.tab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if tab == .agents, !agents.pendingPermissions.isEmpty {
                                    Circle().fill(Color.orange).frame(width: 6, height: 6).offset(x: 4, y: -3)
                                }
                            }
                        if selected {
                            Text(tab.title).font(.system(size: 12, weight: .semibold)).fixedSize()
                        }
                    }
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
                    .padding(.horizontal, selected ? 12 : 9)
                    .frame(height: NotchRootView.tabBarHeight - 8)
                    .background {
                        if selected {
                            Capsule().fill(Color.white.opacity(0.16))
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(4)
        .frame(height: NotchRootView.tabBarHeight)
        .background(CapsuleBackground(appearance: settings.appearance))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
