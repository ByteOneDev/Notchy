import SwiftUI

/// Full calendar panel: the selected day's agenda on the left, month grid on the right.
struct CalendarPanel: View {
    @ObservedObject private var service = CalendarService.shared
    @ObservedObject private var settings = AppSettings.shared

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = settings.language.locale
        return calendar
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            agenda.frame(maxWidth: .infinity, alignment: .topLeading)
            MonthGrid(calendar: calendar, selected: service.selectedDay, events: service.events) { day in
                withAnimation(.snappy(duration: 0.25)) { service.selectedDay = day }
            }
            .frame(width: 290)
        }
        .contentShape(Rectangle())
        .onHover { service.isHovered = $0 }
    }

    private var header: some View {
        let day = service.selectedDay
        let week = calendar.component(.weekOfYear, from: day)
        return HStack(spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).locale(settings.language.locale)).uppercased())
            Text("\(calendar.component(.day, from: day))").foregroundStyle(.white)
            Text(L("calendar.week", week)).foregroundStyle(.red.opacity(0.75))
            Spacer()
            if !calendar.isDateInToday(day) {
                Button(L("calendar.today")) {
                    withAnimation(.snappy) { service.selectedDay = calendar.startOfDay(for: .now) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
            }
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.red)
    }

    @ViewBuilder private var agenda: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !service.authorized {
                Button(L("calendar.allow")) { service.requestAccess() }
                    .buttonStyle(PillButtonStyle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let events = service.events(on: service.selectedDay)
                if events.isEmpty {
                    Label(L("calendar.empty"), systemImage: "calendar.badge.checkmark")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    AgendaScroller {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(events) { EventCard(event: $0, locale: settings.language.locale) }
                        }
                    }
                }
            }
        }
    }
}

private struct EventCard: View {
    let event: CalendarService.Event
    let locale: Locale

    var body: some View {
        let color = Color(nsColor: event.color)
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(color.mix(with: .white, by: 0.35)).lineLimit(1)
                Text(timeText).font(.system(size: 11)).foregroundStyle(color.mix(with: .white, by: 0.2).opacity(0.85))
            }
            Spacer(minLength: 4)
            if let url = event.meetingURL, event.end > .now {
                Button(L("calendar.join")) { NSWorkspace.shared.open(url) }
                    .buttonStyle(PillButtonStyle(color: .green))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.16)))
        .opacity(event.end < .now ? 0.5 : 1)
    }

    private var timeText: String {
        if event.isAllDay { return L("calendar.allDay") }
        let style = Date.FormatStyle.dateTime.hour().minute().locale(locale)
        return "\(event.start.formatted(style)) – \(event.end.formatted(style))"
    }
}

struct MonthGrid: View {
    let calendar: Calendar
    let selected: Date
    let events: [CalendarService.Event]
    let onSelect: (Date) -> Void

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selected))!
    }

    /// Days of the month, padded at the start so the first weekday lines up.
    private var cells: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
        return Array(repeating: nil, count: leading) + days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer()
                Text(selected.formatted(.dateTime.month(.abbreviated).locale(calendar.locale ?? .current)).uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.red)
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        .frame(height: 15)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 18)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day)
        let weekend = calendar.isDateInWeekend(day)
        let hasEvents = events.contains { $0.start < calendar.date(byAdding: .day, value: 1, to: day)! && $0.end > day }
        return ZStack {
            if isSelected { Circle().fill(Color.red).frame(width: 19, height: 19) }
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(isSelected ? .white : isToday ? .red : .white.opacity(weekend ? 0.45 : 0.9))
            if hasEvents, !isSelected {
                Circle().fill(Color.white.opacity(0.55)).frame(width: 3, height: 3).offset(y: 8)
            }
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(day) }
    }
}
