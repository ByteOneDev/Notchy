import AppKit
import Combine
import SwiftUI

/// A mode: when its trigger is true, Notchy applies its actions; when it stops, it undoes them.
struct ModeRule: Codable, Identifiable, Equatable {
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        /// A Pomodoro focus session is under way.
        case pomodoro
        /// A calendar event with a video call link starts (two minutes before) until it ends.
        case meeting
        /// Between two times, on chosen days.
        case schedule
        /// An app is in front.
        case app
        /// An external display is connected.
        case externalDisplay
        /// Only from the Modes widget.
        case manual

        var id: String { rawValue }
        var title: String { L("modes.trigger.\(rawValue)") }
    }

    var id = UUID()
    var name: String
    var icon: String
    var enabled = true
    var trigger: Trigger
    /// Minutes since midnight; a range that ends before it starts runs overnight.
    var startMinutes = 9 * 60
    var endMinutes = 18 * 60
    /// `Calendar` weekdays, 1 = Sunday.
    var weekdays: [Int] = [2, 3, 4, 5, 6]
    var appBundleID = ""
    var appName = ""
    // Actions
    var pauseMusic = false
    /// No Notchy sounds, and only the activities that matter (HUDs, timers, meetings…).
    var silence = true
    /// Shortcut run when the mode starts, e.g. one that turns a macOS Focus on.
    var startShortcut = ""
    var endShortcut = ""
    /// Sites kept closed in the browsers while the mode is active ("youtube.com",
    /// "youtube.com/shorts"), and whole categories of sites (`SiteCatalog`).
    var blockedSites: [String] = []
    var blockedCategories: [String] = []
    /// Strict: once started, the mode can't be switched off, edited or deleted before it ends.
    var strict = false
    /// How long a strict mode lasts when its trigger has no end of its own (by hand, an app, a display).
    var strictMinutes = 60

    /// Every site the mode blocks, its categories' included.
    var allBlockedSites: [String] {
        var seen = Set<String>()
        return (blockedSites + blockedCategories.flatMap { SiteCatalog.category($0)?.domains ?? [] })
            .filter { seen.insert($0).inserted }
    }

    static var defaults: [ModeRule] {
        [
            ModeRule(name: L("modes.default.focus"), icon: "brain.head.profile", trigger: .pomodoro),
            ModeRule(name: L("modes.default.meeting"), icon: "video.fill", trigger: .meeting, pauseMusic: true),
        ]
    }

    static let icons = ["brain.head.profile", "video.fill", "moon.fill", "briefcase.fill", "book.fill", "gamecontroller.fill",
                        "laptopcomputer", "headphones", "house.fill", "figure.run", "paintbrush.fill", "chevron.left.forwardslash.chevron.right"]
}

extension ModeRule {
    /// Tolerates modes saved by older versions: a missing setting takes its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = ModeRule(name: "", icon: "moon.fill", trigger: .schedule)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? base.name
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? base.icon
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? base.enabled
        trigger = try c.decodeIfPresent(Trigger.self, forKey: .trigger) ?? base.trigger
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? base.startMinutes
        endMinutes = try c.decodeIfPresent(Int.self, forKey: .endMinutes) ?? base.endMinutes
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? base.weekdays
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID) ?? base.appBundleID
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? base.appName
        pauseMusic = try c.decodeIfPresent(Bool.self, forKey: .pauseMusic) ?? base.pauseMusic
        silence = try c.decodeIfPresent(Bool.self, forKey: .silence) ?? base.silence
        startShortcut = try c.decodeIfPresent(String.self, forKey: .startShortcut) ?? base.startShortcut
        endShortcut = try c.decodeIfPresent(String.self, forKey: .endShortcut) ?? base.endShortcut
        blockedSites = try c.decodeIfPresent([String].self, forKey: .blockedSites) ?? base.blockedSites
        blockedCategories = try c.decodeIfPresent([String].self, forKey: .blockedCategories) ?? base.blockedCategories
        strict = try c.decodeIfPresent(Bool.self, forKey: .strict) ?? base.strict
        strictMinutes = try c.decodeIfPresent(Int.self, forKey: .strictMinutes) ?? base.strictMinutes
    }
}

/// Watches the modes' triggers and runs their actions on each change.
@MainActor
final class ModeEngine: ObservableObject {
    static let shared = ModeEngine()

    @Published private(set) var active: Set<UUID> = []
    /// Modes switched on from the widget, kept until switched off (and across restarts).
    @Published private(set) var manualOn: Set<UUID> = Set((UserDefaults.standard.stringArray(forKey: "modesManualOn") ?? []).compactMap(UUID.init))
    /// Modes switched off from the widget while their trigger is true; forgotten once it isn't.
    private var manualOff: Set<UUID> = []
    /// Strict modes and when they may end; kept across restarts so quitting doesn't lift them.
    @Published private(set) var lockedUntil: [UUID: Date] = ModeEngine.loadLocks()
    private var lockTimer: Timer?
    /// Modes that paused the music, to resume it when the last one ends.
    private var pausedMusic: Set<UUID> = []
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    var isSilenced: Bool {
        AppSettings.shared.modes.contains { active.contains($0.id) && $0.silence }
    }

    var activeModes: [ModeRule] { AppSettings.shared.modes.filter { active.contains($0.id) } }

    func start() {
        let settings = AppSettings.shared
        let pomodoro = PomodoroTimer.shared
        let soon = { [weak self] in DispatchQueue.main.async { self?.evaluate() } }
        settings.$modesEnabled.dropFirst().sink { _ in soon() }.store(in: &cancellables)
        settings.$modes.dropFirst().sink { _ in soon() }.store(in: &cancellables)
        pomodoro.$isActive.combineLatest(pomodoro.$phase).dropFirst().sink { _ in soon() }.store(in: &cancellables)
        CalendarService.shared.$events.dropFirst().sink { _ in soon() }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { _ in soon() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { _ in soon() }.store(in: &cancellables)
        // Times and meetings move on by themselves.
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated { ModeEngine.shared.evaluate() }
        }
        evaluate()
    }

    func evaluate() {
        let settings = AppSettings.shared
        let rules = settings.modesEnabled ? settings.modes.filter(\.enabled) : []
        // A strict mode that has run its time is free again; a manual one also stops.
        let expired = lockedUntil.filter { $0.value <= .now }.map(\.key)
        if !expired.isEmpty {
            expired.forEach { lockedUntil[$0] = nil }
            manualOn.subtract(expired)
            saveManualAndLocks()
        }
        let locked = Set(lockedUntil.keys).intersection(settings.modes.map(\.id))
        let triggered = Set(rules.filter(isTriggered).map(\.id))
        manualOff.formIntersection(triggered)
        // Locked modes stay on whatever happens: trigger gone, switched off, modes disabled.
        let now = triggered.subtracting(manualOff).union(manualOn.intersection(rules.map(\.id))).union(locked)
        scheduleLockCheck()
        guard now != active else { return }
        for id in active.subtracting(now) {
            end(settings.modes.first { $0.id == id }, id: id)
        }
        for rule in settings.modes where now.contains(rule.id) && !active.contains(rule.id) {
            begin(rule)
        }
        active = now
    }

    // MARK: Strict modes

    func isLocked(_ id: UUID) -> Bool { (lockedUntil[id] ?? .distantPast) > .now }

    /// A strict mode is on: the modes can't be switched off as a whole either.
    var anyLocked: Bool { lockedUntil.values.contains { $0 > .now } }

    /// When a strict mode that starts now ends: with its trigger when that has an end, else
    /// after its own duration.
    private func lockEnd(for rule: ModeRule) -> Date {
        let now = Date.now
        let fallback = now.addingTimeInterval(TimeInterval(max(1, rule.strictMinutes) * 60))
        switch rule.trigger {
        case .pomodoro:
            let pomodoro = PomodoroTimer.shared
            return pomodoro.isActive && pomodoro.phase == .focus ? now.addingTimeInterval(pomodoro.remaining) : fallback
        case .meeting:
            return CalendarService.shared.events.first { event in
                !event.isAllDay && event.meetingURL != nil && event.start.addingTimeInterval(-120) <= now && event.end > now
            }?.end ?? fallback
        case .schedule:
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            var end = calendar.date(byAdding: .minute, value: rule.endMinutes, to: today) ?? fallback
            if end <= now { end = calendar.date(byAdding: .day, value: 1, to: end) ?? fallback }
            return end
        case .app, .externalDisplay, .manual:
            return fallback
        }
    }

    /// Re-check right when the next lock ends, not at the next 20-second tick.
    private func scheduleLockCheck() {
        lockTimer?.invalidate()
        guard let next = lockedUntil.values.filter({ $0 > .now }).min() else { return }
        lockTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow + 0.5, repeats: false) { _ in
            MainActor.assumeIsolated { ModeEngine.shared.evaluate() }
        }
    }

    private func saveManualAndLocks() {
        UserDefaults.standard.set(manualOn.map(\.uuidString), forKey: "modesManualOn")
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: lockedUntil.map { ($0.key.uuidString, $0.value.timeIntervalSince1970) }),
                                  forKey: "modesLockedUntil")
    }

    private static func loadLocks() -> [UUID: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: "modesLockedUntil") as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, Date(timeIntervalSince1970: value)) }
        })
    }

    private func isTriggered(_ rule: ModeRule) -> Bool {
        let now = Date.now
        switch rule.trigger {
        case .pomodoro:
            let pomodoro = PomodoroTimer.shared
            return pomodoro.isActive && pomodoro.phase == .focus
        case .meeting:
            return CalendarService.shared.events.contains { event in
                !event.isAllDay && event.meetingURL != nil && event.start.addingTimeInterval(-120) <= now && event.end > now
            }
        case .schedule:
            let calendar = Calendar.current
            let parts = calendar.dateComponents([.hour, .minute, .weekday], from: now)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let weekday = parts.weekday ?? 1
            if rule.startMinutes <= rule.endMinutes {
                return rule.weekdays.contains(weekday) && minutes >= rule.startMinutes && minutes < rule.endMinutes
            }
            // Overnight: the evening belongs to today, the early morning to the day before.
            let yesterday = weekday == 1 ? 7 : weekday - 1
            return (rule.weekdays.contains(weekday) && minutes >= rule.startMinutes)
                || (rule.weekdays.contains(yesterday) && minutes < rule.endMinutes)
        case .app:
            return !rule.appBundleID.isEmpty && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == rule.appBundleID
        case .externalDisplay:
            return NSScreen.screens.contains { !$0.isBuiltIn }
        case .manual:
            return false
        }
    }

    /// From the widget: on if it is off, off if it is on, whatever its trigger says. A strict
    /// mode under way can't be switched off.
    func toggle(_ rule: ModeRule) {
        if active.contains(rule.id), isLocked(rule.id) {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return
        }
        Haptics.tap()
        if active.contains(rule.id) {
            manualOn.remove(rule.id)
            if isTriggered(rule) { manualOff.insert(rule.id) }
        } else {
            manualOff.remove(rule.id)
            if !isTriggered(rule) { manualOn.insert(rule.id) }
        }
        saveManualAndLocks()
        evaluate()
    }

    private func begin(_ rule: ModeRule) {
        if rule.strict, lockedUntil[rule.id] == nil {
            lockedUntil[rule.id] = lockEnd(for: rule)
            saveManualAndLocks()
        }
        LiveActivityCenter.shared.show(.mode(name: rule.name, symbol: rule.icon, on: true), duration: 2.5)
        let media = NowPlayingService.shared
        if rule.pauseMusic, media.track?.isPlaying == true {
            media.pause()
            pausedMusic.insert(rule.id)
        }
        ShortcutRunner.shared.runSilently(shortcut: rule.startShortcut)
    }

    private func end(_ rule: ModeRule?, id: UUID) {
        if let rule {
            LiveActivityCenter.shared.show(.mode(name: rule.name, symbol: rule.icon, on: false), duration: 2)
            ShortcutRunner.shared.runSilently(shortcut: rule.endShortcut)
        }
        if pausedMusic.remove(id) != nil, pausedMusic.isEmpty {
            NowPlayingService.shared.play()
        }
    }
}
