import SwiftUI

/// Widgets the home panel can show, in the order chosen in the settings.
enum HomeWidget: String, CaseIterable, Identifiable {
    case media, calendar, weather, rain, tasks, shortcuts, modes, network
    var id: String { rawValue }

    /// The home panel is one row: beyond three widgets it gets cramped.
    static let maxShown = 3

    var icon: String {
        switch self {
        case .media: "music.note"
        case .calendar: "calendar"
        case .weather: "cloud.sun.fill"
        case .rain: "cloud.rain.fill"
        case .tasks: "checklist"
        case .shortcuts: "square.grid.2x2.fill"
        case .modes: "moon.stars.fill"
        case .network: "network"
        }
    }

    var color: Color {
        switch self {
        case .media: .pink
        case .calendar: .red
        case .weather, .rain: .cyan
        case .tasks: .orange
        case .shortcuts: .indigo
        case .modes: .purple
        case .network: .blue
        }
    }

    var title: String { L("home.widget.\(rawValue)") }

    /// The feature behind the widget is switched on.
    @MainActor var isAvailable: Bool {
        let settings = AppSettings.shared
        return switch self {
        case .media: settings.mediaEnabled
        case .calendar: settings.calendarEnabled
        case .weather, .rain: settings.weatherEnabled
        case .modes: settings.modesEnabled
        case .tasks, .shortcuts, .network: true
        }
    }
}

struct HomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    /// Widgets to show instead of the ones in the settings (snapshots).
    var override: [HomeWidget]?

    private var widgets: [HomeWidget] {
        if let override { return override }
        return Array(settings.homeWidgets.compactMap(HomeWidget.init).filter(\.isAvailable).prefix(HomeWidget.maxShown))
    }

    var body: some View {
        let widgets = self.widgets
        HStack(spacing: 18) {
            if widgets.isEmpty {
                if settings.weatherEnabled {
                    WeatherWidget(wide: true)
                } else {
                    Button(L("home.choose")) { SettingsWindowController.shared.show(pane: .widgets) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            ForEach(Array(widgets.enumerated()), id: \.element) { index, widget in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1).padding(.vertical, 6)
                }
                view(for: widget, count: widgets.count)
            }
        }
    }

    @ViewBuilder private func view(for widget: HomeWidget, count: Int) -> some View {
        switch widget {
        case .media:
            if count == 1 {
                MediaPlayerView().frame(maxWidth: .infinity)
            } else {
                MediaPlayerView(compact: count == 3).frame(width: count == 2 ? 380 : 300)
            }
        case .calendar: CalendarWidget()
        case .weather: WeatherWidget(wide: count == 1)
        case .rain: RainWidget()
        case .tasks: TasksWidget()
        case .shortcuts: ShortcutsWidget()
        case .modes: ModesWidget()
        case .network: NetworkWidget()
        }
    }
}

/// Title row shared by the small home widgets.
struct WidgetHeader<Trailing: View>: View {
    let widget: HomeWidget
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: widget.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(widget.color)
            Text(widget.title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 4)
            trailing()
        }
    }
}

extension WidgetHeader where Trailing == EmptyView {
    init(widget: HomeWidget) {
        self.widget = widget
        trailing = { EmptyView() }
    }
}
