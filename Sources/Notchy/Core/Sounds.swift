import AppKit

/// Discreet system sounds for the notch, at the volume set in the settings.
@MainActor
enum Sounds {
    enum Effect {
        /// The notch opens.
        case open
        /// Something connected or changed (headphones, charger, display…).
        case activity
        /// Something that needs attention (low battery, rain, meeting).
        case alert

        var name: String {
            switch self {
            case .open: "Pop"
            case .activity: "Tink"
            case .alert: "Purr"
            }
        }
    }

    static func play(_ effect: Effect) {
        let settings = AppSettings.shared
        guard settings.sounds, !ModeEngine.shared.isSilenced, let sound = NSSound(named: effect.name)?.copy() as? NSSound else { return }
        sound.volume = Float(settings.soundVolume)
        sound.play()
    }

    static func effect(for kind: LiveActivityKind) -> Effect? {
        switch kind {
        case .volume, .brightness, .keyboard, .capsLock, .conversion, .pomodoro, .timerDone, .download, .shortcut: nil
        case .lowBattery, .deviceBattery, .meeting, .rain, .usageWarning, .agentAttention: .alert
        case .agentDone, .update: .activity
        case .battery, .bluetooth, .camera, .microphone, .airDrop, .display, .focus, .network, .mode: .activity
        }
    }
}
