import SwiftUI

extension Animation {
    /// Days sliding under the calendar highlight.
    static let daySlide = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(settings.language.locale)).capitalized)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Spacer()
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

    /// A carousel: the highlight stays in the middle and the days slide under it, smaller and
    /// fainter towards the edges. Two-finger swipes or a click move it.
    private var dayStrip: some View {
        GeometryReader { geo in
            let cell: CGFloat = 36
            let center = geo.size.width / 2
            let reach = Int(center / cell) + 2
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 34, height: 42)
                    .shadow(color: .white.opacity(0.25), radius: 6)
                    .position(x: center, y: 21)
                // Identified by date, so the days shared before and after a change slide over.
                let days = (-reach...reach).compactMap { calendar.date(byAdding: .day, value: $0, to: selected) }
                ForEach(days, id: \.self) { day in
                    let offset = calendar.dateComponents([.day], from: selected, to: day).day ?? 0
                    let distance = abs(Double(offset))
                    DayCell(day: day, calendar: calendar, selected: offset == 0, hasEvents: !service.events(on: day).isEmpty)
                        .scaleEffect(offset == 0 ? 1 : max(0.78, 1 - distance * 0.05))
                        .opacity(max(0.25, 1 - distance * 0.13))
                        .position(x: center + CGFloat(offset) * cell, y: 21)
                        .onTapGesture { withAnimation(.daySlide) { service.selectedDay = day } }
                        .transition(.opacity)
                }
            }
        }
        .frame(height: 42)
        // The strip is cut at the edge rather than widening the panel when space is short.
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .animation(.daySlide, value: selected)
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
            AgendaScroller {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { EventRow(event: $0, locale: settings.language.locale) }
                }
            }
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
