import SwiftUI

/// Week strip on top, the selected day's agenda below. Swipe with two fingers to change day.
struct CalendarWidget: View {
    @ObservedObject private var service = CalendarService.shared
    @ObservedObject private var settings = AppSettings.shared

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = settings.language.locale
        return calendar
    }

    private var selected: Date { service.selectedDay }

    /// A sliding window of days that keeps the selected day in the same slot.
    private var days: [Date] {
        (-3...7).compactMap { calendar.date(byAdding: .day, value: $0, to: selected) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(settings.language.locale)).capitalized)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Spacer()
                let hidden = service.events(on: selected).count - 2
                if service.authorized, hidden > 0 {
                    Text(L("calendar.more", hidden))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                if !calendar.isDateInToday(selected) {
                    Button(L("calendar.today")) {
                        withAnimation(.snappy) { service.selectedDay = calendar.startOfDay(for: .now) }
                        service.reload()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
                }
            }
            dayStrip
            if service.authorized {
                agenda
            } else {
                Button(L("calendar.allow")) { service.requestAccess() }
                    .buttonStyle(PillButtonStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onHover { service.isHovered = $0 }
    }

    private var dayStrip: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                DayCell(day: day, calendar: calendar, selected: calendar.isDate(day, inSameDayAs: selected),
                        hasEvents: !service.events(on: day).isEmpty)
                    .onTapGesture { withAnimation(.snappy(duration: 0.25)) { service.selectedDay = day } }
                    .transition(.opacity)
            }
        }
        .frame(height: 42)
        // The strip is cut at the edge rather than widening the panel when space is short.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                     .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }

    @ViewBuilder private var agenda: some View {
        let events = service.events(on: selected)
        if events.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark").foregroundStyle(.white.opacity(0.4))
                Text(L("calendar.empty")).foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // No scroll view: it would swallow the two-finger swipes that change the day.
            let shown = Array(events.prefix(2))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { EventRow(event: $0, locale: settings.language.locale) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct DayCell: View {
    let day: Date
    let calendar: Calendar
    let selected: Bool
    let hasEvents: Bool

    var body: some View {
        let isToday = calendar.isDateInToday(day)
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.narrow).locale(calendar.locale ?? .current)))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(selected ? .black.opacity(0.6) : .white.opacity(0.4))
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(selected ? .black : isToday ? .red : .white)
            Circle().fill(hasEvents ? (selected ? Color.black.opacity(0.5) : Color.white.opacity(0.5)) : .clear)
                .frame(width: 3, height: 3)
        }
        .frame(width: 32, height: 40)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Color.white : Color.clear))
        .contentShape(Rectangle())
    }
}

private struct EventRow: View {
    let event: CalendarService.Event
    let locale: Locale

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: event.color)).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(timeText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 4)
            if let url = event.meetingURL, event.end > .now {
                Button(L("calendar.join")) { NSWorkspace.shared.open(url) }
                    .buttonStyle(PillButtonStyle(color: .green))
            }
        }
        .opacity(event.end < .now ? 0.45 : 1)
    }

    private var timeText: String {
        if event.isAllDay { return L("calendar.allDay") }
        let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        return "\(event.start.formatted(style)) – \(event.end.formatted(style))"
    }
}

struct PillButtonStyle: ButtonStyle {
    var color: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color == .white ? .black : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}
