import SwiftUI

extension Animation {
    /// Days sliding under the calendar highlight.
    static let daySlide = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

/// Day picker on top (in the style chosen in the settings), the selected day's agenda below.
/// Swipe with two fingers to change day.
struct CalendarWidget: View {
    @ObservedObject private var service = CalendarService.shared
    @ObservedObject private var settings = AppSettings.shared
    @Namespace private var selection
    /// Days dragged with the mouse on the carousel or the ruler, fractional while the drag lasts.
    @State private var dragDays: Double = 0
    @State private var weekWidth: CGFloat = 0

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = settings.language.locale
        return calendar
    }

    private var selected: Date { service.selectedDay }

    var body: some View {
        Group {
            switch settings.dayPickerStyle {
            case .notchNook:
                VStack(alignment: .leading, spacing: 8) {
                    notchNookHeader
                    weekRow
                    agendaOrAccess
                }
            case .carousel:
                VStack(alignment: .leading, spacing: 6) {
                    titleHeader
                    dayStrip
                    agendaOrAccess
                }
            case .ruler:
                VStack(alignment: .leading, spacing: 6) {
                    notchNookHeader
                    dayRuler
                    agendaOrAccess
                }
            case .bigDate:
                HStack(alignment: .top, spacing: 16) {
                    bigDate
                    agendaOrAccess
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { service.isHovered = $0 }
    }

    @ViewBuilder private var agendaOrAccess: some View {
        if service.authorized {
            agenda
        } else {
            Button(L("calendar.allow")) { service.requestAccess() }
                .buttonStyle(PillButtonStyle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var todayButton: some View {
        Button(L("calendar.today")) {
            withAnimation(.daySlide) { service.selectedDay = calendar.startOfDay(for: .now) }
            service.reload()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.red)
        .opacity(calendar.isDateInToday(selected) ? 0 : 1)
        .disabled(calendar.isDateInToday(selected))
    }

    // MARK: NotchNook style

    /// "SAM. 7 NOV.  S45", like NotchNook's calendar.
    private var notchNookHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(selected.formatted(.dateTime.weekday(.abbreviated).locale(settings.language.locale)).uppercased())
                .foregroundStyle(.red)
            Text("\(calendar.component(.day, from: selected))")
                .contentTransition(.numericText(countsDown: !service.movedForward))
            Text(selected.formatted(.dateTime.month(.abbreviated).locale(settings.language.locale)).uppercased())
            Text(L("calendar.week", calendar.component(.weekOfYear, from: selected)))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
            todayButton
        }
        .font(.system(size: 13, weight: .bold))
        .animation(.daySlide, value: selected)
    }

    /// The selected day's week; a red disc slides to the chosen day, and the week itself
    /// slides over when the selection leaves it.
    private var weekRow: some View {
        let start = calendar.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
        let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return HStack(spacing: 0) {
            ForEach(week, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let isToday = calendar.isDateInToday(day)
                let isWeekend = calendar.isDateInWeekend(day)
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.narrow).locale(settings.language.locale)).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                    ZStack {
                        if isSelected {
                            Circle().fill(Color.red).matchedGeometryEffect(id: "selectedDay", in: selection)
                        } else if isToday {
                            Circle().stroke(Color.red.opacity(0.7), lineWidth: 1.2)
                        }
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isSelected ? .white : isToday ? .red : .white.opacity(isWeekend ? 0.45 : 0.9))
                    }
                    .frame(width: 25, height: 25)
                    Circle().fill(service.events(on: day).isEmpty ? Color.clear : Color.white.opacity(0.45))
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.daySlide) { service.selectedDay = day } }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { weekWidth = $0 }
        .contentShape(Rectangle())
        // Dragging along the week moves the disc under the pointer, a tick at each day.
        .gesture(DragGesture(minimumDistance: 3).onChanged { value in
            guard weekWidth > 0 else { return }
            let index = min(6, max(0, Int(value.location.x / (weekWidth / 7))))
            guard index < week.count, !calendar.isDate(week[index], inSameDayAs: selected) else { return }
            Haptics.tap()
            withAnimation(.daySlide) { service.selectedDay = week[index] }
        })
        .id(start)
        .transition(.asymmetric(
            insertion: .move(edge: service.movedForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: service.movedForward ? .leading : .trailing).combined(with: .opacity)))
        .frame(height: 44)
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .animation(.daySlide, value: selected)
    }

    // MARK: Carousel style

    private var titleHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(settings.language.locale)).capitalized)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer()
            todayButton
        }
    }

    // MARK: Big date style

    /// The day in big type, like a desk calendar page; swipes flip it.
    private var bigDate: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(selected.formatted(.dateTime.weekday(.wide).locale(settings.language.locale)).uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.red)
            Text("\(calendar.component(.day, from: selected))")
                .font(.system(size: 46, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText(countsDown: !service.movedForward))
            Text(selected.formatted(.dateTime.month(.wide).year().locale(settings.language.locale)).capitalized)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 4)
            todayButton
        }
        .frame(width: 92, alignment: .leading)
        .animation(.daySlide, value: selected)
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
                    let shifted = Double(offset) - dragDays
                    let distance = abs(shifted)
                    DayCell(day: day, calendar: calendar, selected: distance < 0.5, hasEvents: !service.events(on: day).isEmpty)
                        .scaleEffect(max(0.78, 1 - distance * 0.05))
                        .opacity(max(0.25, 1 - distance * 0.13))
                        .position(x: center + CGFloat(shifted) * cell, y: 21)
                        .onTapGesture { withAnimation(.daySlide) { service.selectedDay = day } }
                        .transition(.opacity)
                }
            }
        }
        .frame(height: 42)
        // The strip is cut at the edge rather than widening the panel when space is short.
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .gesture(dayDrag(spacing: 36))
        .animation(.daySlide, value: selected)
    }

    /// Drags the carousel or the ruler like the timer's: the days follow the pointer with a
    /// tick at each one, then settle on the nearest.
    private func dayDrag(spacing: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                // Dragging left brings the next days, like pulling the strip.
                let days = -Double(value.translation.width / spacing)
                if Int(days.rounded()) != Int(dragDays.rounded()) { Haptics.tap() }
                dragDays = days
            }
            .onEnded { _ in
                let step = Int(dragDays.rounded())
                // Jump the selection by whole days without animation, so nothing moves on
                // screen, then ease out what is left of the drag.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if step != 0 { service.moveSelection(by: step, animated: false) }
                    dragDays -= Double(step)
                }
                withAnimation(.daySlide) { dragDays = 0 }
            }
    }

    // MARK: Ruler style

    /// One tick per day under a fixed red needle, longer on the first day of each week, with
    /// the day numbers below; dragged or swiped like the timer's ruler.
    private var dayRuler: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 26
            let center = geo.size.width / 2
            let reach = Int(center / spacing) + 2
            let days = (-reach...reach).compactMap { calendar.date(byAdding: .day, value: $0, to: selected) }
            ZStack {
                ForEach(days, id: \.self) { day in
                    let offset = calendar.dateComponents([.day], from: selected, to: day).day ?? 0
                    let shifted = Double(offset) - dragDays
                    let isCurrent = abs(shifted) < 0.5
                    let weekStart = calendar.component(.weekday, from: day) == calendar.firstWeekday
                    let isToday = calendar.isDateInToday(day)
                    VStack(spacing: 3) {
                        Circle().fill(service.events(on: day).isEmpty ? Color.clear : Color.white.opacity(0.5))
                            .frame(width: 3, height: 3)
                        Capsule()
                            .fill(isToday ? Color.red : Color.white.opacity(weekStart ? 0.75 : 0.32))
                            .frame(width: weekStart ? 1.5 : 1, height: weekStart ? 15 : 9)
                            .frame(height: 15, alignment: .bottom)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: isCurrent ? 11 : 9, weight: isCurrent ? .bold : .semibold).monospacedDigit())
                            .foregroundStyle(isCurrent ? .white : isToday ? .red : .white.opacity(0.45))
                    }
                    .frame(width: spacing, height: 40)
                    .contentShape(Rectangle())
                    .position(x: center + CGFloat(shifted) * spacing, y: 22)
                    .onTapGesture { withAnimation(.daySlide) { service.selectedDay = day } }
                }
                VStack(spacing: 0) {
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7))
                    Capsule().frame(width: 2.5, height: 18)
                }
                .foregroundStyle(.red)
                .position(x: center, y: 14)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 44)
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                     .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .contentShape(Rectangle())
        .gesture(dayDrag(spacing: 26))
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
