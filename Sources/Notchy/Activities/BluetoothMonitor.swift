import Foundation
import IOBluetooth

/// Announces Bluetooth audio devices (AirPods, headphones…) when they connect or disconnect.
@MainActor
final class BluetoothMonitor: NSObject {
    static let shared = BluetoothMonitor()

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var startDate = Date.now

    func start() {
        startDate = .now
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnectNotifications[address] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        // At launch every already-connected device is reported: stay quiet then.
        guard Date.now.timeIntervalSince(startDate) > 3 else { return }
        announce(device, connected: true)
        // AirPods report their battery a moment after connecting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, device.isConnected(), let battery = Self.battery(of: device) else { return }
            if LiveActivityCenter.shared.current?.kind.group == "bluetooth" {
                LiveActivityCenter.shared.show(.bluetooth(name: Self.name(of: device), icon: Self.icon(for: device), connected: true, battery: battery), duration: 3)
            }
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let address = device.addressString { disconnectNotifications[address] = nil }
        announce(device, connected: false)
    }

    private func announce(_ device: IOBluetoothDevice, connected: Bool) {
        guard AppSettings.shared.bluetoothActivity, Self.isInteresting(device) else { return }
        LiveActivityCenter.shared.show(
            .bluetooth(name: Self.name(of: device), icon: Self.icon(for: device), connected: connected,
                       battery: connected ? Self.battery(of: device) : nil),
            duration: 3.5
        )
    }

    private static func name(of device: IOBluetoothDevice) -> String {
        device.name ?? "Bluetooth"
    }

    /// Audio devices, keyboards, mice and trackpads.
    private static func isInteresting(_ device: IOBluetoothDevice) -> Bool {
        let major = device.deviceClassMajor
        return major == kBluetoothDeviceClassMajorAudio || major == kBluetoothDeviceClassMajorPeripheral
            || (device.name ?? "").localizedCaseInsensitiveContains("airpods")
    }

    static func icon(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if device.deviceClassMajor == kBluetoothDeviceClassMajorPeripheral {
            if name.contains("keyboard") || name.contains("clavier") { return "keyboard" }
            if name.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
            return "computermouse"
        }
        if device.deviceClassMinor == kBluetoothDeviceClassMinorAudioLoudspeaker { return "hifispeaker.fill" }
        return "headphones"
    }

    /// Battery through IOBluetooth's undocumented accessors (AirPods / Beats expose them).
    private static func battery(of device: IOBluetoothDevice) -> Int? {
        func read(_ name: String) -> Int? {
            let selector = NSSelectorFromString(name)
            guard device.responds(to: selector) else { return nil }
            typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
            let value = unsafeBitCast(device.method(for: selector), to: Getter.self)(device, selector)
            return value > 0 && value <= 100 ? Int(value) : nil
        }
        let buds = [read("batteryPercentLeft"), read("batteryPercentRight")].compactMap { $0 }
        if let lowest = buds.min() { return lowest }
        return read("batteryPercentSingle") ?? read("batteryPercentCombined")
    }
}
