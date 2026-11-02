import AppKit
import SwiftUI

@MainActor
final class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

    enum Phase: Equatable {
        case focus, shortBreak, longBreak

        var icon: String { self == .focus ? "brain.head.profile" : "cup.and.saucer.fill" }
        var color: Color { self == .focus ? Color(red: 1, green: 0.38, blue: 0.32) : Color(red: 0.35, green: 0.85, blue: 0.55) }
        var title: String {
            switch self {
            case .focus: L("pomodoro.focus")
            case .shortBreak: L("pomodoro.shortBreak")
            case .longBreak: L("pomodoro.longBreak")
            }
        }
    }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    /// Focus sessions completed in the current cycle.
    @Published private(set) var completedRounds = 0
    @Published private(set) var isActive = false
    private var endDate: Date?
    private var timer: Timer?

    var total: TimeInterval { duration(of: phase) }
    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    private func duration(of phase: Phase) -> TimeInterval {
        let settings = AppSettings.shared
        return switch phase {
        case .focus: TimeInterval(settings.pomodoroWork * 60)
        case .shortBreak: TimeInterval(settings.pomodoroShortBreak * 60)
        case .longBreak: TimeInterval(settings.pomodoroLongBreak * 60)
        }
    }

    func toggle() { isRunning ? pause() : startOrResume() }

    func startOrResume() {
        if !isActive { remaining = duration(of: phase) }
        isActive = true
        isRunning = true
        endDate = .now.addingTimeInterval(remaining)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { PomodoroTimer.shared.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
    }

    func reset() {
        timer?.invalidate()
        isRunning = false
        isActive = false
        phase = .focus
        completedRounds = 0
        remaining = duration(of: .focus)
    }

    func skip() { finishPhase(announce: false) }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finishPhase(announce: true) }
    }

    private func finishPhase(announce: Bool) {
        let rounds = AppSettings.shared.pomodoroRounds
        if phase == .focus {
            completedRounds += 1
            phase = completedRounds >= rounds ? .longBreak : .shortBreak
        } else {
            if phase == .longBreak { completedRounds = 0 }
            phase = .focus
        }
        remaining = duration(of: phase)
        if announce {
            NSSound(named: "Glass")?.play()
            LiveActivityCenter.shared.show(.pomodoro(message: phase == .focus ? L("pomodoro.backToWork") : L("pomodoro.takeBreak")), duration: 5)
        }
        if isRunning { startOrResume() }
    }
}

/// Simple countdown with presets.
@MainActor
final class QuickTimer: ObservableObject {
    static let shared = QuickTimer()

    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var isActive = false
    @Published private(set) var isRunning = false
    private var endDate: Date?
    private var timer: Timer?

    func start(minutes: Int) {
        total = TimeInterval(minutes * 60)
        remaining = total
        isActive = true
        resume()
    }

    func resume() {
        guard isActive else { return }
        isRunning = true
        endDate = .now.addingTimeInterval(remaining)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { QuickTimer.shared.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        if let endDate { remaining = max(0, endDate.timeIntervalSinceNow) }
    }

    func add(minutes: Int) {
        if !isActive { start(minutes: minutes); return }
        total += TimeInterval(minutes * 60)
        remaining += TimeInterval(minutes * 60)
        if isRunning { endDate = .now.addingTimeInterval(remaining) }
    }

    func stop() {
        timer?.invalidate()
        isActive = false
        isRunning = false
        remaining = 0
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            stop()
            NSSound(named: "Glass")?.play()
            LiveActivityCenter.shared.show(.timerDone, duration: 5)
        }
    }
}

struct TimerTabView: View {
    @ObservedObject private var pomodoro = PomodoroTimer.shared
    @ObservedObject private var timer = QuickTimer.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 18) {
            pomodoroPanel.frame(maxWidth: .infinity)
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1).padding(.vertical, 6)
            timerPanel.frame(maxWidth: .infinity)
        }
    }

    private var pomodoroPanel: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(pomodoro.phase.color.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: pomodoro.isActive ? pomodoro.progress : 0)
                    .stroke(pomodoro.phase.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: pomodoro.progress)
                VStack(spacing: 0) {
                    Text((pomodoro.isActive ? pomodoro.remaining : pomodoro.total).clock)
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    Image(systemName: pomodoro.phase.icon).font(.system(size: 11)).foregroundStyle(pomodoro.phase.color)
                }
            }
            .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("pomodoro.title")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Text(pomodoro.phase.title).font(.system(size: 15, weight: .semibold))
                HStack(spacing: 4) {
                    ForEach(0..<settings.pomodoroRounds, id: \.self) { i in
                        Circle().fill(i < pomodoro.completedRounds ? pomodoro.phase.color : Color.white.opacity(0.2)).frame(width: 6, height: 6)
                    }
                }
                HStack(spacing: 6) {
                    Button { pomodoro.toggle() } label: {
                        Image(systemName: pomodoro.isRunning ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(CircleButtonStyle(color: pomodoro.phase.color))
                    Button { pomodoro.skip() } label: { Image(systemName: "forward.end.fill") }
                        .buttonStyle(CircleButtonStyle())
                        .help(L("pomodoro.skip"))
                    Button { pomodoro.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(CircleButtonStyle())
                        .help(L("pomodoro.reset"))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var timerPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("timer.title")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            if timer.isActive {
                HStack(spacing: 12) {
                    Text(timer.remaining.clock).font(.system(size: 34, weight: .semibold).monospacedDigit()).foregroundStyle(.orange)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: Int(timer.remaining))
                    Spacer(minLength: 0)
                    Button { timer.isRunning ? timer.pause() : timer.resume() } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(CircleButtonStyle(color: .orange))
                    Button { timer.stop() } label: { Image(systemName: "xmark") }
                        .buttonStyle(CircleButtonStyle())
                }
                HStack(spacing: 6) {
                    ForEach([1, 5], id: \.self) { m in
                        Button("+\(m) min") { timer.add(minutes: m) }.buttonStyle(PillButtonStyle(color: .white.opacity(0.15)))
                    }
                }
            } else {
                let presets = [1, 3, 5, 10, 15, 20, 30, 45]
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(presets, id: \.self) { minutes in
                        Button("\(minutes) min") { timer.start(minutes: minutes) }
                            .buttonStyle(PillButtonStyle(color: .white.opacity(0.15)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct CircleButtonStyle: ButtonStyle {
    var color: Color = .white.opacity(0.15)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(color.opacity(configuration.isPressed ? 0.6 : 1)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .contentShape(Circle())
    }
}
