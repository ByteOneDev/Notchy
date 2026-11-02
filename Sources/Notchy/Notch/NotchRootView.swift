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

    var body: some View {
        VStack(spacing: 0) {
            notch
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

    private var shape: NotchShape {
        viewModel.isOpen
            ? NotchShape(topRadius: 12, bottomRadius: 30)
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
            }
        }
        .shadow(color: .black.opacity(viewModel.isOpen ? 0.55 : 0), radius: 14, y: 6)
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
