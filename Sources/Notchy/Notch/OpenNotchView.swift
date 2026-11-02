import SwiftUI

struct OpenNotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var weather = WeatherService.shared
    @ObservedObject private var battery = BatteryMonitor.shared

    private var tabs: [NotchTab] {
        NotchTab.allCases.filter { tab in
            switch tab {
            case .shelf: settings.shelfEnabled
            case .mirror: settings.mirrorEnabled
            case .teleprompter: settings.teleprompterEnabled
            default: true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: viewModel.notchSize.height)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .foregroundStyle(.white)
    }

    /// The row level with the hardware notch: tabs on the left, status on the right.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    TabButton(icon: tab.icon, selected: viewModel.tab == tab) {
                        withAnimation(.snappy(duration: 0.25)) { viewModel.tab = tab }
                    }
                }
            }
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
                }
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 12))
                }
                .buttonStyle(HoverButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
    }

    @ViewBuilder private var content: some View {
        switch viewModel.tab {
        case .home: HomeView()
        case .shelf: ShelfView()
        case .timer: TimerTabView()
        case .teleprompter: TeleprompterView()
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
