import SwiftUI

enum LiveActivityKind: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case battery(level: Int, charging: Bool)
    case lowBattery(level: Int)
    case bluetooth(name: String, icon: String, connected: Bool, battery: Int?)
    case capsLock(on: Bool)
    case camera(on: Bool)
    case microphone(on: Bool)
    case meeting(title: String, minutes: Int)
    case conversion(name: String, progress: Double, failed: Bool)
    case pomodoro(message: String)
    case timerDone
    case airDrop(count: Int)

    /// Activities of the same group replace each other instead of queueing (volume ticks…).
    var group: String {
        switch self {
        case .volume, .brightness: "hud"
        case .battery, .lowBattery: "battery"
        case .bluetooth: "bluetooth"
        case .capsLock: "caps"
        case .camera, .microphone: "privacy"
        case .meeting: "meeting"
        case .conversion: "conversion"
        case .pomodoro, .timerDone: "timer"
        case .airDrop: "airdrop"
        }
    }
}

struct LiveActivity: Identifiable, Equatable {
    let id = UUID()
    var kind: LiveActivityKind
    var duration: TimeInterval
}

/// Queue of short-lived activities shown by the closed notch (HUDs, connections, alerts).
@MainActor
final class LiveActivityCenter: ObservableObject {
    static let shared = LiveActivityCenter()

    @Published private(set) var current: LiveActivity?
    private var queue: [LiveActivity] = []
    private var dismissWork: DispatchWorkItem?

    func show(_ kind: LiveActivityKind, duration: TimeInterval = 2.2) {
        if var current, current.kind.group == kind.group {
            // Same kind of activity: update in place and extend, without re-animating.
            current.kind = kind
            current.duration = duration
            self.current = current
            scheduleDismiss(after: duration)
            return
        }
        queue.removeAll { $0.kind.group == kind.group }
        let activity = LiveActivity(kind: kind, duration: duration)
        if current == nil || kind.group == "hud" {
            // HUDs are immediate feedback: they cut in front of anything else.
            if let current, kind.group == "hud" { queue.insert(current, at: 0) }
            present(activity)
        } else {
            queue.append(activity)
        }
    }

    func dismiss(group: String) {
        queue.removeAll { $0.kind.group == group }
        if current?.kind.group == group { next() }
    }

    private func present(_ activity: LiveActivity) {
        withAnimation(.notchActivity) { current = activity }
        scheduleDismiss(after: activity.duration)
    }

    private func scheduleDismiss(after duration: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.next() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func next() {
        dismissWork?.cancel()
        if queue.isEmpty {
            withAnimation(.notchActivity) { current = nil }
        } else {
            present(queue.removeFirst())
        }
    }
}
