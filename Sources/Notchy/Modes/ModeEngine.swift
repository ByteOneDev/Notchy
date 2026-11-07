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
    /// Sites kept closed in the browsers while the mode is active ("youtube.com").
    var blockedSites: [String] = []

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
    }
}

/// Watches the modes' triggers and runs their actions on each change.
@MainActor
final class ModeEngine: ObservableObject {
    static let shared = ModeEngine()

    @Published private(set) var active: Set<UUID> = []
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
        let now = Set(rules.filter(isTriggered).map(\.id))
        guard now != active else { return }
        for id in active.subtracting(now) {
            end(settings.modes.first { $0.id == id }, id: id)
        }
        for rule in rules where now.contains(rule.id) && !active.contains(rule.id) {
            begin(rule)
        }
        active = now
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
        }
    }

    private func begin(_ rule: ModeRule) {
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
