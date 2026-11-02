import AppKit
import CoreAudio
import CoreMediaIO

@MainActor
final class CapsLockMonitor {
    static let shared = CapsLockMonitor()
    private var isOn = NSEvent.modifierFlags.contains(.capsLock)
    private var monitors: [Any] = []

    func start() {
        let handler: (NSEvent) -> Void = { event in
            MainActor.assumeIsolated { CapsLockMonitor.shared.flagsChanged(event.modifierFlags) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { handler($0); return $0 }) { monitors.append(local) }
    }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        let on = flags.contains(.capsLock)
        guard on != isOn else { return }
        isOn = on
        guard AppSettings.shared.capsLockActivity else { return }
        LiveActivityCenter.shared.show(.capsLock(on: on), duration: 1.6)
    }
}

/// Announces when the camera or the microphone starts or stops being used by any app.
@MainActor
final class PrivacyMonitor {
    static let shared = PrivacyMonitor()
    private var cameraOn = false
    private var micOn = false
    private var timer: Timer?
    /// The Mirror uses the camera itself; don't announce that.
    var ignoreCamera = false
    /// The voice-following teleprompter listens to the microphone itself.
    var ignoreMicrophone = false

    func start() {
        cameraOn = Self.isCameraInUse()
        micOn = Self.isMicrophoneInUse()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { PrivacyMonitor.shared.poll() }
        }
    }

    private func poll() {
        let camera = Self.isCameraInUse()
        let mic = Self.isMicrophoneInUse()
        let enabled = AppSettings.shared.privacyActivity
        if camera != cameraOn {
            cameraOn = camera
            if enabled, !ignoreCamera { LiveActivityCenter.shared.show(.camera(on: camera), duration: 2.5) }
        }
        if mic != micOn {
            micOn = mic
            if enabled, !ignoreMicrophone { LiveActivityCenter.shared.show(.microphone(on: mic), duration: 2.5) }
        }
    }

    private static func isMicrophoneInUse() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr else { return false }
        for device in devices {
            var running: UInt32 = 0
            var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                           mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                           mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var runningUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &runningUsed, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
    }
}
