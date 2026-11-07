import AppKit
import EventKit
import SwiftUI

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: NSColor
        let meetingURL: URL?
    }

    @Published private(set) var authorized = false
    @Published private(set) var events: [Event] = []
    @Published var selectedDay = Calendar.current.startOfDay(for: .now) {
        didSet {
            agendaOffset = 0
            if selectedDay != oldValue { movedForward = selectedDay > oldValue }
        }
    }
    /// Direction of the last day change, for the transitions.
    private(set) var movedForward = true
    /// The mouse is over the calendar widget: horizontal swipes change the day.
    var isHovered = false
    /// The agenda list is under the mouse, and how far down it can go. The notch scrolls it
    /// itself: a scroll view would swallow the swipes that change the day.
    var agendaHovered = false
    var agendaMaxOffset: CGFloat = 0
    @Published var agendaOffset: CGFloat = 0
    /// Video call the mirror is currently preparing for.
    @Published private(set) var prepEvent: Event?
    private var prepared = Set<String>()
    private let store = EKEventStore()
    private var announced = Set<String>()
    private var timer: Timer?

    func start() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarService.shared.reload() }
        }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { CalendarService.shared.checkUpcomingMeeting() }
        }
    }

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            authorized = granted
            reload()
            if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func scrollAgenda(by delta: CGFloat) {
        agendaOffset = min(max(0, agendaOffset + delta), agendaMaxOffset)
    }

    func moveSelection(by days: Int) {
        guard let day = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) else { return }
        withAnimation(.daySlide) { selectedDay = day }
        // Swiping far from the loaded range: load events around the new day.
        if abs(day.timeIntervalSince(loadedCenter)) > 10 * 86_400 { reload() }
    }

    private var loadedCenter = Calendar.current.startOfDay(for: .now)

    /// Loads a month of events around the selected day.
    func reload() {
        guard authorized else { events = []; return }
        let calendar = Calendar.current
        loadedCenter = selectedDay
        let start = calendar.date(byAdding: .day, value: -15, to: selectedDay)!
        let end = calendar.date(byAdding: .day, value: 31, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                Event(id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                      title: event.title ?? "",
                      start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                      color: event.calendar.color ?? .systemBlue,
                      meetingURL: Self.meetingURL(in: event))
            }
    }

    func events(on day: Date) -> [Event] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.start < end && $0.end > start }
    }

    private func checkUpcomingMeeting() {
        let settings = AppSettings.shared
        let now = Date.now
        if let prep = prepEvent, prep.start.addingTimeInterval(5 * 60) < now { endMeetingPrep() }
        for event in events where !event.isAllDay && event.end > now {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            if settings.meetingActivity, !announced.contains(event.id), minutes <= 5, minutes >= 0 {
                announced.insert(event.id)
                LiveActivityCenter.shared.show(.meeting(title: event.title, minutes: minutes), duration: 6)
            }
            // Video calls: open the mirror a moment before, to check hair and framing.
            if settings.meetingPrep, settings.mirrorEnabled, event.meetingURL != nil, !prepared.contains(event.id),
               minutes <= settings.meetingPrepMinutes, minutes >= 0 {
                prepared.insert(event.id)
                prepEvent = event
                NotchManager.shared.openPrimary(tab: .mirror)
            }
        }
    }

    func endMeetingPrep() {
        prepEvent = nil
        if let viewModel = NotchManager.shared.primaryViewModel, viewModel.tab == .mirror { viewModel.close() }
    }

    /// Video call link (Meet, Zoom, Teams, FaceTime…) found in the event.
    private static func meetingURL(in event: EKEvent) -> URL? {
        let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "facetime.apple.com", "whereby.com", "webex.com"]
        if let url = event.url, hosts.contains(where: { url.host()?.hasSuffix($0) == true }) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap(\.url).first { url in hosts.contains { url.host()?.hasSuffix($0) == true } }
    }
}
