import AppKit
import IOBluetooth
import IOKit

/// Warns when a mouse, keyboard, trackpad or pair of headphones runs low.
@MainActor
final class DeviceBatteryMonitor {
    static let shared = DeviceBatteryMonitor()
    private var warned: [String: Int] = [:]
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { DeviceBatteryMonitor.shared.check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.check() }
    }

    private func check() {
        guard AppSettings.shared.deviceBatteryActivity else { return }
        for device in Self.accessories() + Self.headphones() {
            let lastWarning = warned[device.name] ?? 101
            if device.level > 30 {
                warned[device.name] = nil
            } else if let threshold = [20, 10, 5].last(where: { device.level <= $0 }), threshold < lastWarning {
                warned[device.name] = threshold
                LiveActivityCenter.shared.show(.deviceBattery(name: device.name, icon: device.icon, level: device.level), duration: 4)
            }
        }
    }

    private struct Device {
        let name: String
        let icon: String
        let level: Int
    }

    /// Apple accessories (Magic Mouse, Keyboard, Trackpad) expose their battery in the I/O Registry.
    private static func accessories() -> [Device] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var devices: [Device] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let level = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int,
                  let name = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String else { continue }
            let lower = name.lowercased()
            let icon = lower.contains("keyboard") ? "keyboard" : lower.contains("trackpad") ? "rectangle.and.hand.point.up.left" : "magicmouse"
            devices.append(Device(name: name, icon: icon, level: level))
        }
        return devices
    }

    private static func headphones() -> [Device] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
            .compactMap { device in
                guard let level = BluetoothMonitor.battery(of: device) else { return nil }
                return Device(name: device.name ?? "Bluetooth", icon: BluetoothMonitor.icon(for: device), level: level)
            }
    }
}

/// Announces external displays being plugged in or out.
@MainActor
final class DisplayMonitor {
    static let shared = DisplayMonitor()
    private var known: [CGDirectDisplayID: String] = [:]

    func start() {
        known = Self.externalDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DisplayMonitor.shared.screensChanged() }
        }
    }

    private func screensChanged() {
        let current = Self.externalDisplays()
        defer { known = current }
        guard AppSettings.shared.displayActivity else { return }
        for (id, name) in current where known[id] == nil {
            LiveActivityCenter.shared.show(.display(name: name, connected: true), duration: 3)
        }
        for (id, name) in known where current[id] == nil {
            LiveActivityCenter.shared.show(.display(name: name, connected: false), duration: 3)
        }
    }

    private static func externalDisplays() -> [CGDirectDisplayID: String] {
        Dictionary(NSScreen.screens.filter { !$0.isBuiltIn }.map { ($0.displayID, $0.localizedName) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Follows the Focus mode (Ne pas déranger, Travail…). macOS has no public API for it, so this
/// reads the Focus database, which requires Full Disk Access.
@MainActor
final class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()

    @Published private(set) var current: (name: String, symbol: String)?
    private var currentID: String?
    private var timer: Timer?
    private var started = false

    private static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

    static var hasAccess: Bool {
        FileManager.default.isReadableFile(atPath: directory.appendingPathComponent("Assertions.json").path)
    }

    func start() {
        currentID = Self.activeModeID()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { FocusMonitor.shared.poll() }
        }
    }

    private func poll() {
        guard Self.hasAccess else { return }
        let id = Self.activeModeID()
        // First successful read (access just granted): remember the state without announcing it.
        guard started else { started = true; currentID = id; current = id.map(Self.mode(for:)); return }
        guard id != currentID else { return }
        let previous = currentID
        currentID = id
        current = id.map(Self.mode(for:))
        guard AppSettings.shared.focusActivity else { return }
        if let id {
            let mode = Self.mode(for: id)
            LiveActivityCenter.shared.show(.focus(name: mode.name, symbol: mode.symbol, on: true), duration: 2.5)
        } else if let previous {
            let mode = Self.mode(for: previous)
            LiveActivityCenter.shared.show(.focus(name: mode.name, symbol: mode.symbol, on: false), duration: 2.5)
        }
    }

    private static func json(_ file: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func activeModeID() -> String? {
        guard let entries = json("Assertions.json")?["data"] as? [[String: Any]] else { return nil }
        for entry in entries {
            for record in entry["storeAssertionRecords"] as? [[String: Any]] ?? [] {
                if let details = record["assertionDetails"] as? [String: Any],
                   let id = details["assertionDetailsModeIdentifier"] as? String {
                    return id
                }
            }
        }
        return nil
    }

    private static func mode(for id: String) -> (name: String, symbol: String) {
        let entries = json("ModeConfigurations.json")?["data"] as? [[String: Any]] ?? []
        for entry in entries {
            if let configs = entry["modeConfigurations"] as? [String: Any],
               let config = configs[id] as? [String: Any],
               let mode = config["mode"] as? [String: Any],
               let name = mode["name"] as? String, !name.isEmpty {
                return (name, mode["symbolImageName"] as? String ?? "moon.fill")
            }
        }
        return (L("focus.dnd"), "moon.fill")
    }
}
