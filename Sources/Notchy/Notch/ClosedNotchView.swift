import SwiftUI

/// What the closed notch shows on each side of the hardware notch, and optionally below it.
struct CompactLayout {
    var leftWidth: CGFloat = 0
    var rightWidth: CGFloat = 0
    var left: AnyView = AnyView(EmptyView())
    var right: AnyView = AnyView(EmptyView())
    var bottom: AnyView?
    var bottomHeight: CGFloat = 0
    var isEmpty = true

    init() {}

    init<L: View, R: View>(left: CGFloat, right: CGFloat, @ViewBuilder leading: () -> L, @ViewBuilder trailing: () -> R) {
        leftWidth = left
        rightWidth = right
        self.left = AnyView(leading())
        self.right = AnyView(trailing())
        isEmpty = false
    }

    func withBottom<B: View>(_ text: String, @ViewBuilder _ content: () -> B = { EmptyView() }) -> CompactLayout {
        var copy = self
        copy.bottom = AnyView(
            HStack(spacing: 6) {
                Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                content()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
        )
        copy.bottomHeight = 26
        return copy
    }

    @MainActor
    static func make(activity: LiveActivity?, media: NowPlayingService, locked: Bool, justUnlocked: Bool,
                     pomodoro: PomodoroTimer, timer: QuickTimer, notchHeight: CGFloat) -> CompactLayout {
        let side = max(notchHeight + 8, 42)
        if let activity { return forActivity(activity.kind, side: side) }

        if locked || justUnlocked {
            return CompactLayout(left: side, right: media.showsInClosedNotch ? side : 0) {
                Image(systemName: justUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            } trailing: {
                if media.showsInClosedNotch { AudioVisualizer(color: media.accent, playing: media.track?.isPlaying == true) }
            }
        }

        if media.showsInClosedNotch, let track = media.track {
            return CompactLayout(left: side, right: side) {
                ArtworkView(image: media.artwork, size: notchHeight - 10, radius: 6, isLogo: media.isLogoArtwork, tint: media.accent)
            } trailing: {
                if AppSettings.shared.showVisualizer {
                    AudioVisualizer(color: media.accent, playing: track.isPlaying)
                } else {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11)).foregroundStyle(media.accent)
                }
            }
        }

        let agents = AgentHub.shared
        if agents.isAnyWorking || !agents.pendingPermissions.isEmpty, let session = agents.sessions.first(where: { $0.isWorking }) ?? agents.sessions.first {
            let waiting = !agents.pendingPermissions.isEmpty
            return CompactLayout(left: side, right: side) {
                AgentGlyph(name: session.kind.displayName, size: 14)
            } trailing: {
                if waiting {
                    Image(systemName: "hand.raised.fill").font(.system(size: 12)).foregroundStyle(.orange)
                        .symbolEffect(.pulse)
                } else {
                    ProgressView().controlSize(.mini).tint(session.kind.color)
                }
            }
        }

        if pomodoro.isActive {
            return CompactLayout(left: side, right: 62) {
                Image(systemName: pomodoro.phase.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(pomodoro.phase.color)
            } trailing: {
                Text(pomodoro.remaining.clock).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(pomodoro.isRunning ? pomodoro.phase.color : .secondary)
            }
        }

        if timer.isActive {
            return CompactLayout(left: side, right: 62) {
                Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            } trailing: {
                Text(timer.remaining.clock).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.orange)
            }
        }
        return CompactLayout()
    }

    // swiftlint:disable:next function_body_length
    private static func forActivity(_ kind: LiveActivityKind, side: CGFloat) -> CompactLayout {
        switch kind {
        case let .volume(level, muted):
            let symbol = muted || level == 0 ? "speaker.slash.fill" : "speaker.wave.\(level < 0.34 ? 1 : level < 0.67 ? 2 : 3).fill"
            return CompactLayout(left: side, right: 110) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            } trailing: {
                LevelBar(level: muted ? 0 : Double(level), color: .white)
            }
        case let .brightness(level):
            return CompactLayout(left: side, right: 110) {
                Image(systemName: level < 0.5 ? "sun.min.fill" : "sun.max.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.yellow)
                    .contentTransition(.symbolEffect(.replace))
            } trailing: {
                LevelBar(level: Double(level), color: .yellow)
            }
        case let .battery(level, charging, minutesToFull):
            let layout = CompactLayout(left: 70, right: 70) {
                HStack(spacing: 4) {
                    Image(systemName: charging ? "bolt.fill" : "powerplug.fill").foregroundStyle(charging ? .green : .white)
                    Text(charging ? L("battery.charging") : L("battery.unplugged")).font(.system(size: 11, weight: .semibold))
                }.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            } trailing: {
                BatteryGlyph(level: level, charging: charging)
            }
            if charging, let minutesToFull {
                return layout.withBottom(L("battery.fullIn", BatteryMonitor.durationText(minutes: minutesToFull)))
            }
            return layout
        case let .lowBattery(level):
            return CompactLayout(left: side, right: 70) {
                Image(systemName: "battery.25percent").font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
            } trailing: {
                BatteryGlyph(level: level, charging: false)
            }.withBottom(L("battery.low"))
        case let .bluetooth(name, icon, connected, battery):
            return CompactLayout(left: side, right: battery == nil ? side : 62) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: connected)
            } trailing: {
                if let battery, connected {
                    RingGauge(value: Double(battery) / 100, color: battery <= 20 ? .red : .green, label: "\(battery)")
                } else {
                    Circle().fill(connected ? Color.blue : Color.gray).frame(width: 7, height: 7)
                }
            }.withBottom(name) {
                Text(connected ? L("bluetooth.connected") : L("bluetooth.disconnected"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case let .capsLock(on):
            return CompactLayout(left: side, right: side) {
                Image(systemName: on ? "capslock.fill" : "capslock").font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? .green : .white)
                    .contentTransition(.symbolEffect(.replace))
            } trailing: {
                Circle().fill(on ? Color.green : Color.gray.opacity(0.6)).frame(width: 7, height: 7)
            }
        case let .camera(on):
            return CompactLayout(left: side, right: side) {
                Image(systemName: on ? "video.fill" : "video.slash.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? .green : .white)
            } trailing: {
                Circle().fill(on ? Color.green : Color.gray.opacity(0.6)).frame(width: 7, height: 7)
            }
        case let .microphone(on):
            return CompactLayout(left: side, right: side) {
                Image(systemName: on ? "mic.fill" : "mic.slash.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? .orange : .white)
            } trailing: {
                Circle().fill(on ? Color.orange : Color.gray.opacity(0.6)).frame(width: 7, height: 7)
            }
        case let .meeting(title, minutes):
            return CompactLayout(left: side, right: 62) {
                Image(systemName: "calendar").font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
            } trailing: {
                Text(minutes <= 0 ? L("meeting.now") : L("meeting.in", minutes)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.red)
            }.withBottom(title)
        case let .conversion(name, progress, failed):
            return CompactLayout(left: side, right: 62) {
                Image(systemName: failed ? "exclamationmark.triangle.fill" : progress >= 1 ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(failed ? .red : progress >= 1 ? .green : .white)
            } trailing: {
                RingGauge(value: progress, color: failed ? .red : .green, label: failed ? "!" : "\(Int(progress * 100))")
            }.withBottom(failed ? L("convert.failed") : progress >= 1 ? L("convert.done") : name)
        case let .pomodoro(message):
            return CompactLayout(left: side, right: side) {
                Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.red)
            } trailing: {
                Image(systemName: "bell.fill").font(.system(size: 12)).foregroundStyle(.red).symbolEffect(.wiggle, options: .repeat(3))
            }.withBottom(message)
        case .timerDone:
            return CompactLayout(left: side, right: side) {
                Image(systemName: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            } trailing: {
                Image(systemName: "bell.fill").font(.system(size: 12)).foregroundStyle(.orange).symbolEffect(.wiggle, options: .repeat(3))
            }.withBottom(L("timer.done"))
        case let .airDrop(count):
            return CompactLayout(left: side, right: side) {
                Image(systemName: "dot.radiowaves.up.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(.blue)
            } trailing: {
                Text("\(count)").font(.system(size: 12, weight: .bold)).foregroundStyle(.blue)
            }.withBottom(L("airdrop.sending"))
        case let .deviceBattery(name, icon, level):
            return CompactLayout(left: side, right: 62) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            } trailing: {
                RingGauge(value: Double(level) / 100, color: .red, label: "\(level)")
            }.withBottom(name) {
                Text(L("battery.low")).font(.system(size: 12)).foregroundStyle(.red)
            }
        case let .display(name, connected):
            return CompactLayout(left: side, right: side) {
                Image(systemName: connected ? "display" : "display.trianglebadge.exclamationmark")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: connected)
            } trailing: {
                Circle().fill(connected ? Color.blue : Color.gray).frame(width: 7, height: 7)
            }.withBottom(name) {
                Text(connected ? L("bluetooth.connected") : L("bluetooth.disconnected"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case let .focus(name, symbol, on):
            return CompactLayout(left: side, right: 76) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? .indigo : .white.opacity(0.5))
                    .symbolEffect(.bounce, value: on)
            } trailing: {
                Text(on ? L("focus.on") : L("focus.off")).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(on ? .indigo : .white.opacity(0.6))
            }.withBottom(name)
        case let .rain(minutes, heavy):
            return CompactLayout(left: side, right: 76) {
                Image(systemName: heavy ? "cloud.heavyrain.fill" : "cloud.rain.fill").symbolRenderingMode(.multicolor)
                    .font(.system(size: 14))
            } trailing: {
                Text(minutes <= 0 ? L("rain.now") : L("meeting.in", minutes)).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
            }.withBottom(heavy ? L("rain.heavy") : L("rain.coming"))
        case let .agentDone(agent, project):
            return CompactLayout(left: side, right: side) {
                AgentGlyph(name: agent, size: 14)
            } trailing: {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(.green)
                    .symbolEffect(.bounce, value: project)
            }.withBottom(L("agents.done", agent)) {
                Text(project).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case let .agentAttention(agent, message):
            return CompactLayout(left: side, right: side) {
                AgentGlyph(name: agent, size: 14)
            } trailing: {
                Image(systemName: "bell.fill").font(.system(size: 12)).foregroundStyle(.orange)
                    .symbolEffect(.wiggle, options: .repeat(2))
            }.withBottom(message)
        case let .usageWarning(percent, window):
            return CompactLayout(left: side, right: 62) {
                Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
            } trailing: {
                RingGauge(value: Double(percent) / 100, color: percent >= 95 ? .red : .orange, label: "\(percent)")
            }.withBottom(L("usage.warning", percent, window))
        case let .update(version, state):
            return CompactLayout(left: side, right: 62) {
                Image(systemName: state == .installed ? "checkmark.seal.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state == .installed ? .green : .blue)
                    .symbolEffect(.pulse, isActive: state == .installing)
            } trailing: {
                Text(version).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            }.withBottom(state == .installed ? L("update.done", version)
                         : state == .installing ? L("update.installing", version) : L("update.available", version))
        }
    }
}

struct ClosedNotchView: View {
    let layout: CompactLayout
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                layout.left
                    .frame(width: layout.leftWidth, height: notchSize.height)
                Spacer(minLength: notchSize.width)
                layout.right
                    .frame(width: layout.rightWidth, height: notchSize.height)
            }
            .padding(.horizontal, 4)
            .frame(height: notchSize.height)
            if let bottom = layout.bottom {
                bottom.frame(height: layout.bottomHeight, alignment: .top)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Small building blocks

struct LevelBar: View {
    let level: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(color).frame(width: max(4, geo.size.width * level))
                }
            }
            .frame(height: 5)
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.trailing, 6)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

struct RingGauge: View {
    let value: Double
    let color: Color
    let label: String

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.system(size: 8, weight: .bold).monospacedDigit()).foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
        .animation(.easeOut, value: value)
    }
}

struct BatteryGlyph: View {
    let level: Int
    let charging: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(level) %").font(.system(size: 11, weight: .semibold).monospacedDigit())
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5), lineWidth: 1).frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: max(2, 18 * CGFloat(level) / 100), height: 7).padding(.leading, 2)
            }
        }
        .foregroundStyle(.white)
    }

    private var color: Color { charging ? .green : level <= 20 ? .red : .white }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat
    /// The image is a site or app logo: fit it on a tile tinted with its color.
    var isLogo = false
    var tint: Color = .white

    var body: some View {
        Group {
            if let image, isLogo {
                ZStack {
                    tint.opacity(0.22)
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
                        .padding(size * 0.2)
                }
            } else if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.gray.opacity(0.5), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct AudioVisualizer: View {
    let color: Color
    let playing: Bool
    var bars = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !playing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = t * (3.2 + Double(i) * 0.9) + Double(i) * 1.7
                    let value = playing ? 0.3 + 0.7 * abs(sin(phase) * cos(phase * 0.43)) : 0.15
                    Capsule().fill(color)
                        .frame(width: 2.5, height: max(3, 14 * value))
                }
            }
            .animation(.easeInOut(duration: 0.12), value: playing)
        }
        .frame(height: 16)
    }
}

extension TimeInterval {
    /// "4:05" or "1:02:03".
    var clock: String {
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
