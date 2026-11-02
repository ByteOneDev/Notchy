import Foundation
import IOKit.ps

@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var level: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    /// Minutes until full, when macOS has estimated it.
    @Published private(set) var minutesToFull: Int?
    private var warnedLevels = Set<Int>()
    private var runLoopSource: CFRunLoopSource?

    func start() {
        read(announce: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.read(announce: true) }
        }, context)?.takeRetainedValue()
        if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
    }

    private func read(announce: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let toFull = description[kIOPSTimeToFullChargeKey] as? Int ?? -1

            let pluggedChanged = pluggedIn != isPluggedIn
            level = newLevel
            isCharging = charging || (pluggedIn && newLevel >= 100)
            isPluggedIn = pluggedIn
            minutesToFull = charging && toFull > 0 ? toFull : nil

            guard announce, AppSettings.shared.batteryActivity else { return }
            let center = LiveActivityCenter.shared
            if pluggedChanged {
                warnedLevels.removeAll()
                center.show(.battery(level: newLevel, charging: pluggedIn, minutesToFull: minutesToFull), duration: 3.5)
            } else if center.current?.kind.group == "battery", pluggedIn {
                // The estimate usually arrives a moment after plugging in.
                center.show(.battery(level: newLevel, charging: true, minutesToFull: minutesToFull), duration: 3)
            } else if !pluggedIn {
                for threshold in [20, 10, 5] where newLevel <= threshold && !warnedLevels.contains(threshold) {
                    warnedLevels.formUnion([20, 10, 5].filter { $0 >= threshold })
                    center.show(.lowBattery(level: newLevel), duration: 4)
                    break
                }
            }
            return
        }
    }

    /// "1 h 05" / "45 min".
    nonisolated static func durationText(minutes: Int) -> String {
        minutes >= 60 ? String(format: "%d h %02d", minutes / 60, minutes % 60) : "\(minutes) min"
    }
}
