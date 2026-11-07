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
    /// Minutes picked on the ruler; fractional while it moves. Remembered for next time.
    @Published private(set) var dial: Double = UserDefaults.standard.object(forKey: "timerDial") as? Double ?? 5
    /// The mouse is over the ruler: horizontal swipes turn it.
    var rulerHovered = false
    private var endDate: Date?
    private var timer: Timer?

    static let dialRange: ClosedRange<Double> = 1...180
    var dialMinutes: Int { Int(dial.rounded()) }

    /// Moves the ruler, with a haptic tick at each minute like a picker wheel.
    func setDial(_ value: Double) {
        let before = dialMinutes
        dial = min(max(value, Self.dialRange.lowerBound), Self.dialRange.upperBound)
        if dialMinutes != before { Haptics.tap() }
    }

    func turnDial(by minutes: Double) { setDial(dial + minutes) }

    /// Lands on a whole minute.
    func settleDial() {
        withAnimation(.snappy(duration: 0.25)) { dial = dial.rounded() }
        UserDefaults.standard.set(dial, forKey: "timerDial")
    }

    func startFromDial() {
        settleDial()
        start(minutes: dialMinutes)
    }

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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("timer.title")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if timer.isActive, timer.isRunning {
                    Text(L("timer.endsAt", Date.now.addingTimeInterval(timer.remaining)
                        .formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Loc.locale))))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                }
            }
            HStack(alignment: .center, spacing: 8) {
                Text((timer.isActive ? timer.remaining : TimeInterval(timer.dialMinutes * 60)).clock)
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
                    .foregroundStyle(timer.isActive ? ClassicColors.orange : .white)
                    .contentTransition(.numericText(countsDown: timer.isActive))
                    .animation(.snappy(duration: 0.2), value: timer.isActive ? Int(timer.remaining) : timer.dialMinutes)
                Spacer(minLength: 0)
                if timer.isActive {
                    Button(timer.isRunning ? L("timer.pause") : L("timer.resume")) {
                        timer.isRunning ? timer.pause() : timer.resume()
                    }
                    .buttonStyle(ClassicButtonStyle(color: timer.isRunning ? ClassicColors.orange : ClassicColors.green))
                    Button(L("common.cancel")) { timer.stop() }
                        .buttonStyle(ClassicButtonStyle(color: ClassicColors.gray))
                } else {
                    Button(L("timer.start")) { timer.startFromDial() }
                        .buttonStyle(ClassicButtonStyle(color: ClassicColors.green))
                }
            }
            if timer.isActive {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(ClassicColors.orange)
                                .frame(width: geo.size.width * (timer.total > 0 ? timer.remaining / timer.total : 0))
                                .animation(.linear(duration: 0.5), value: timer.remaining)
                        }
                    }
                    .frame(height: 6)
                    Button("+1 min") { timer.add(minutes: 1) }
                        .buttonStyle(ClassicButtonStyle(color: ClassicColors.gray, compact: true))
                }
                .frame(maxHeight: .infinity)
            } else {
                TimerRuler()
            }
        }
    }
}

/// The colors of the Clock app on iOS and macOS.
enum ClassicColors {
    static let orange = Color(red: 1, green: 0.584, blue: 0)
    static let green = Color(red: 0.204, green: 0.78, blue: 0.349)
    static let gray = Color(white: 0.6)
}

/// Clock app button: colored text on a tinted capsule.
struct ClassicButtonStyle: ButtonStyle {
    let color: Color
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, compact ? 4 : 7)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.35 : 0.22)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .contentShape(Capsule())
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}

/// A ruler of minutes under a fixed orange needle: drag it, or swipe with two fingers.
struct TimerRuler: View {
    @ObservedObject private var timer = QuickTimer.shared
    @State private var dragStart: Double?
    /// Points per minute.
    static let spacing: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let spacing = Self.spacing
            let center = size.width / 2
            let half = Double(center / spacing)
            let first = max(0, Int((timer.dial - half).rounded(.down)) - 1)
            let last = min(Int(QuickTimer.dialRange.upperBound), Int((timer.dial + half).rounded(.up)) + 1)
            guard first <= last else { return }
            for minute in first...last {
                let x = center + CGFloat(Double(minute) - timer.dial) * spacing
                let major = minute % 5 == 0
                let height: CGFloat = major ? 14 : 7
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 12))
                tick.addLine(to: CGPoint(x: x, y: 12 + height))
                context.stroke(tick, with: .color(.white.opacity(major ? 0.75 : 0.3)), lineWidth: major ? 1.5 : 1)
                if major, minute > 0 {
                    context.draw(Text("\(minute)").font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.5)),
                                 at: CGPoint(x: x, y: 36))
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7))
                Capsule().frame(width: 2.5, height: 20)
            }
            .foregroundStyle(ClassicColors.orange)
            .offset(y: 2)
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                     .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .frame(height: 44)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil { dragStart = timer.dial }
                // Dragging left brings longer times, like pulling the ruler.
                timer.setDial((dragStart ?? timer.dial) - Double(value.translation.width / Self.spacing))
            }
            .onEnded { _ in
                dragStart = nil
                timer.settleDial()
            })
        .onHover { timer.rulerHovered = $0 }
        .onDisappear { timer.rulerHovered = false }
        .help(L("timer.rulerHint"))
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
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}
