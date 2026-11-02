import AppKit
import AudioToolbox
import CoreAudio

/// Replaces the system volume and brightness HUDs: the media keys are intercepted with an
/// event tap (needs Accessibility), applied by Notchy and shown in the notch instead.
@MainActor
final class MediaKeyMonitor {
    static let shared = MediaKeyMonitor()

    private var tap: CFMachPort?
    private var retryTimer: Timer?
    private(set) var isTapActive = false

    // NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h
    private enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    func start() {
        installTap()
        if tap == nil {
            // Accessibility may be granted later from the settings: keep trying.
            retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self else { return timer.invalidate() }
                    self.installTap()
                    if self.tap != nil { timer.invalidate() }
                }
            }
        }
    }

    private func installTap() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { MediaKeyMonitor.shared.reenable() }
                return Unmanaged.passUnretained(event)
            }
            let consumed = MainActor.assumeIsolated { MediaKeyMonitor.shared.handle(event) }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback, userInfo: nil) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isTapActive = true
    }

    private func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the key was handled and must not reach the system.
    private func handle(_ cgEvent: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: cgEvent), event.type == .systemDefined, event.subtype.rawValue == 8 else { return false }
        let data = event.data1
        guard let key = Key(rawValue: (data & 0xFFFF0000) >> 16) else { return false }
        let isDown = ((data & 0xFF00) >> 8) == 0xA
        let settings = AppSettings.shared
        // Option+Shift gives finer steps, like macOS.
        let fine = event.modifierFlags.contains(.option) && event.modifierFlags.contains(.shift)
        let step: Float = fine ? 1 / 64 : 1 / 16

        switch key {
        case .soundUp, .soundDown, .mute:
            guard settings.replaceVolumeHUD, VolumeController.isAvailable else { return false }
            guard isDown else { return true }
            switch key {
            case .mute: VolumeController.toggleMute()
            case .soundUp: VolumeController.change(by: step)
            default: VolumeController.change(by: -step)
            }
            LiveActivityCenter.shared.show(.volume(level: VolumeController.volume, muted: VolumeController.isMuted), duration: 1.6)
            return true
        case .brightnessUp, .brightnessDown:
            guard settings.replaceBrightnessHUD, BrightnessController.isAvailable else { return false }
            guard isDown else { return true }
            BrightnessController.change(by: key == .brightnessUp ? step : -step)
            LiveActivityCenter.shared.show(.brightness(level: BrightnessController.brightness), duration: 1.6)
            return true
        }
    }
}

/// Volume of the default output device through Core Audio.
enum VolumeController {
    private static var device: AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    /// HDMI and some USB devices have no software volume: leave those to the system.
    static var isAvailable: Bool {
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &volumeAddress)
            && AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr && settable.boolValue
    }

    static var volume: Float {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value)
        return value
    }

    static var isMuted: Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &muteAddress) else { return false }
        AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value)
        return value != 0
    }

    static func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        guard AudioObjectHasProperty(device, &muteAddress) else { return }
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func toggleMute() { setMuted(!isMuted) }

    static func change(by delta: Float) {
        // Snap to the step grid so 16 presses always go from 0 to 100 %.
        let steps = (1 / abs(delta)).rounded()
        var value = Float32(min(1, max(0, ((volume * steps).rounded() + (delta > 0 ? 1 : -1)) / steps)))
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if isMuted, delta > 0 { setMuted(false) }
        if value == 0 { setMuted(true) }
    }
}

/// Built-in display brightness through the private DisplayServices framework.
enum BrightnessController {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
    private static let getBrightness: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setBrightness: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }

    private static var display: CGDirectDisplayID {
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &displays, &count)
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    static var isAvailable: Bool {
        guard let getBrightness else { return false }
        var value: Float = 0
        return getBrightness(display, &value) == 0
    }

    static var brightness: Float {
        var value: Float = 0
        _ = getBrightness?(display, &value)
        return value
    }

    static func change(by delta: Float) {
        let steps = (1 / abs(delta)).rounded()
        let value = min(1, max(0, ((brightness * steps).rounded() + (delta > 0 ? 1 : -1)) / steps))
        _ = setBrightness?(display, value)
    }
}
