import AppKit
import Carbon.HIToolbox
import SwiftUI

struct KeyboardShortcutSetting: Equatable {
    var keyCode: Int
    /// NSEvent.ModifierFlags raw value (device-independent bits only).
    var modifiers: UInt

    /// ⌃⌥ Space: free on most setups (⌥ Space types a non-breaking space on French keyboards).
    static let defaultToggleNotch = KeyboardShortcutSetting(keyCode: kVK_Space, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue)

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static func keyName(_ code: Int) -> String {
        switch code {
        case kVK_Space: return L("key.space")
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        // Character produced by the key on the current keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let layout = unsafeBitCast(layoutData, to: CFData.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { pointer in
            UCKeyTranslate(pointer, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

/// Global keyboard shortcuts through Carbon hot keys (no permission needed).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum Action: UInt32 {
        case toggleNotch = 1, teleprompter = 2
    }

    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    /// Suspended while the settings window records a new shortcut.
    var isSuspended = false { didSet { reload() } }

    func start() {
        installHandler()
        reload()
    }

    func reload() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        guard !isSuspended else { return }
        let settings = AppSettings.shared
        register(settings.toggleNotchShortcut, action: .toggleNotch)
        register(settings.teleprompterShortcut, action: .teleprompter)
    }

    private func register(_ shortcut: KeyboardShortcutSetting?, action: Action) {
        guard let shortcut else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4E544359), id: action.rawValue) // 'NTCY'
        if RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
           let ref {
            refs.append(ref)
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.perform(Action(rawValue: id.id)) }
            }
            return noErr
        }, 1, &type, nil, nil)
    }

    private func perform(_ action: Action?) {
        switch action {
        case .toggleNotch:
            guard let viewModel = NotchManager.shared.primaryViewModel else { return }
            viewModel.toggle()
        case .teleprompter:
            NotchManager.shared.openPrimary(tab: .teleprompter)
            Teleprompter.shared.toggle()
        case nil:
            break
        }
    }
}

/// Button that records a shortcut: click, then press the keys.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcutSetting?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? L("shortcut.recording") : shortcut?.display ?? L("shortcut.none"))
                    .frame(minWidth: 110)
            }
            if shortcut != nil, !recording {
                Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // A global shortcut needs at least one of ⌘ ⌥ ⌃.
            guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            shortcut = KeyboardShortcutSetting(keyCode: Int(event.keyCode), modifiers: flags.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        HotKeyCenter.shared.isSuspended = false
    }
}
