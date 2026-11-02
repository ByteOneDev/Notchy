import SwiftUI

struct OpenNotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var battery = BatteryMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: viewModel.notchSize.height)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .id(viewModel.tab)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .foregroundStyle(.white)
        .animation(.snappy(duration: 0.25), value: viewModel.tab)
    }

    /// The row level with the hardware notch: date on the left, status on the right.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(settings.language.locale)).uppercased())
                    .foregroundStyle(.red)
                Text(viewModel.tab.title.uppercased()).foregroundStyle(.white.opacity(0.4))
            }
            .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: viewModel.notchSize.width + 16)
            HStack(spacing: 10) {
                if settings.weatherEnabled, let current = weather.current {
                    HStack(spacing: 4) {
                        Image(systemName: current.symbol).symbolRenderingMode(.multicolor)
                        Text(current.temperatureText)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .help(weather.cityName)
                }
                if let level = battery.level {
                    BatteryGlyph(level: level, charging: battery.isCharging)
                        .help(battery.minutesToFull.map { L("battery.fullIn", BatteryMonitor.durationText(minutes: $0)) } ?? "")
                }
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12))
                }
                .buttonStyle(HoverButtonStyle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 2)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.tab {
        case .home: HomeView()
        case .music: MusicPanel()
        case .calendar: CalendarPanel()
        case .shelf: ShelfView()
        case .teleprompter: TeleprompterView()
        case .agents: AgentsView()
        case .timer: TimerTabView()
        case .mirror: MirrorView()
        }
    }
}


struct TabButton: View {
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? .black : .white.opacity(hovering ? 1 : 0.7))
                .frame(width: 28, height: 22)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(hovering ? 0.15 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct HoverButtonStyle: ButtonStyle {
    var padding: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration, padding: padding)
    }

    private struct HoverButtonBody: View {
        let configuration: Configuration
        let padding: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(padding)
                .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.25 : hovering ? 0.12 : 0)))
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

struct HomeView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 18) {
            if settings.mediaEnabled {
                MediaPlayerView()
                    .frame(width: settings.calendarEnabled ? 380 : nil)
                    .frame(maxWidth: settings.calendarEnabled ? nil : .infinity)
            }
            if settings.mediaEnabled && settings.calendarEnabled {
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1).padding(.vertical, 6)
            }
            if settings.calendarEnabled {
                CalendarWidget()
            }
            if !settings.mediaEnabled && !settings.calendarEnabled {
                WeatherDetailView().frame(maxWidth: .infinity)
            }
        }
    }
}
