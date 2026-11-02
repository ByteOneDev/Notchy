import EventKit
import SwiftUI

/// Incomplete reminders from Apple's Reminders app, synced with the iPhone.
@MainActor
final class TasksService: ObservableObject {
    static let shared = TasksService()

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let color: NSColor

        var isOverdue: Bool { due.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false }
    }

    @Published private(set) var authorized = false
    @Published private(set) var items: [Item] = []
    private let store = EKEventStore()

    func start() {
        authorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { TasksService.shared.reload() }
        }
        reload()
    }

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToReminders()) ?? false
            authorized = granted
            reload()
            if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func reload() {
        guard authorized else { items = []; return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            // Dated tasks first, soonest first; then the others, newest first.
            let items = (reminders ?? [])
                .sorted { a, b in
                    switch (a.dueDateComponents?.date, b.dueDateComponents?.date) {
                    case let (x?, y?): x < y
                    case (_?, nil): true
                    case (nil, _?): false
                    case (nil, nil): (a.creationDate ?? .distantPast) > (b.creationDate ?? .distantPast)
                    }
                }
                .prefix(30)
                .map { Item(id: $0.calendarItemIdentifier, title: $0.title ?? "", due: $0.dueDateComponents?.date,
                            color: $0.calendar?.color ?? .systemOrange) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { TasksService.shared.items = items }
            }
        }
    }

    func complete(_ item: Item) {
        withAnimation(.snappy) { items.removeAll { $0.id == item.id } }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authorized, !title.isEmpty, let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        try? store.save(reminder, commit: true)
        reload()
    }
}

struct TasksWidget: View {
    @ObservedObject private var tasks = TasksService.shared
    @State private var draft = ""
    @State private var checking: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(widget: .tasks) {
                if tasks.items.count > 4 {
                    Text(L("calendar.more", tasks.items.count - 4)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
            }
            if !tasks.authorized {
                Spacer(minLength: 0)
                Button(L("tasks.allow")) { tasks.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                Spacer(minLength: 0)
            } else {
                if tasks.items.isEmpty {
                    Text(L("tasks.empty")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(tasks.items.prefix(4)) { item in row(item) }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    TextField(L("tasks.new"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            tasks.add(draft)
                            draft = ""
                        }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: TasksService.Item) -> some View {
        HStack(spacing: 7) {
            Button {
                Haptics.tap()
                withAnimation(.snappy) { checking = item.id }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { tasks.complete(item) }
            } label: {
                Image(systemName: checking == item.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: item.color))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .strikethrough(checking == item.id)
            Spacer(minLength: 4)
            if let due = item.due {
                Text(due.formatted(.relative(presentation: .named).locale(Loc.locale)))
                    .font(.system(size: 10))
                    .foregroundStyle(item.isOverdue ? .red : .white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }
}
