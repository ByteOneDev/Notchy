import AppKit
import EventKit

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

    /// Loads two weeks of events around today.
    func reload() {
        guard authorized else { events = []; return }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: .now))!
        let end = calendar.date(byAdding: .day, value: 21, to: start)!
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
        guard AppSettings.shared.meetingActivity else { return }
        let now = Date.now
        for event in events where !event.isAllDay && !announced.contains(event.id) {
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            if minutes <= 5 && minutes >= 0 {
                announced.insert(event.id)
                LiveActivityCenter.shared.show(.meeting(title: event.title, minutes: minutes), duration: 6)
            }
        }
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
