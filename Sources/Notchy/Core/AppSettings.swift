import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case fr, en
    var id: String { rawValue }
    var label: String { self == .fr ? "Français" : "English" }
    var locale: Locale { Locale(identifier: self == .fr ? "fr_FR" : "en_US") }
}

enum NotchAppearance: String, CaseIterable, Identifiable {
    case black, translucent, glass, liquidGlass
    var id: String { rawValue }
}

enum DisplayTarget: String, CaseIterable, Identifiable {
    case builtIn, main, all
    var id: String { rawValue }
}

/// How the light around the notch is drawn while audio plays.
enum GlowStyle: String, CaseIterable, Identifiable {
    /// A soft backlight: the notch hides the light source and only the halo spills onto the screen.
    case diffuse
    /// A glowing line along the notch's edge.
    case line
    var id: String { rawValue }
}

/// How the home calendar picks its day.
enum DayPickerStyle: String, CaseIterable, Identifiable {
    case notchNook, carousel, ruler, bigDate
    var id: String { rawValue }
    var title: String { L("settings.dayPicker.\(rawValue)") }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
}

/// Persisted user preferences. Every property writes itself to UserDefaults on change.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    // General
    @Published var language: AppLanguage { didSet { save(language.rawValue, "language"); Loc.language = language } }
    @Published var appearance: NotchAppearance { didSet { save(appearance.rawValue, "appearance") } }
    @Published var displayTarget: DisplayTarget { didSet { save(displayTarget.rawValue, "displayTarget") } }
    @Published var openOnHover: Bool { didSet { save(openOnHover, "openOnHover") } }
    @Published var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    @Published var haptics: Bool { didSet { save(haptics, "haptics") } }
    @Published var hideInFullscreen: Bool { didSet { save(hideInFullscreen, "hideInFullscreen") } }
    @Published var showOnLockScreen: Bool { didSet { save(showOnLockScreen, "showOnLockScreen") } }
    @Published var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }

    // Media
    @Published var mediaEnabled: Bool { didSet { save(mediaEnabled, "mediaEnabled") } }
    @Published var allowedApps: [String] { didSet { save(allowedApps, "allowedApps") } }
    @Published var allowedDomains: [String] { didSet { save(allowedDomains, "allowedDomains") } }
    @Published var showVisualizer: Bool { didSet { save(showVisualizer, "showVisualizer") } }
    @Published var showLyrics: Bool { didSet { save(showLyrics, "showLyrics") } }
    @Published var swipeToChangeTrack: Bool { didSet { save(swipeToChangeTrack, "swipeToChangeTrack") } }
    @Published var allAudioSources: Bool { didSet { save(allAudioSources, "allAudioSources") } }
    @Published var audioGlow: Bool { didSet { save(audioGlow, "audioGlow") } }
    @Published var glowStyle: GlowStyle { didSet { save(glowStyle.rawValue, "glowStyle") } }
    @Published var glowWidth: Double { didSet { save(glowWidth, "glowWidth") } }
    @Published var glowBlur: Double { didSet { save(glowBlur, "glowBlur") } }
    @Published var glowIntensity: Double { didSet { save(glowIntensity, "glowIntensity") } }
    @Published var glowOffset: Double { didSet { save(glowOffset, "glowOffset") } }
    @Published var glowPulse: Bool { didSet { save(glowPulse, "glowPulse") } }
    @Published var glowPulseSpeed: Double { didSet { save(glowPulseSpeed, "glowPulseSpeed") } }
    @Published var glowUsesArtworkColor: Bool { didSet { save(glowUsesArtworkColor, "glowUsesArtworkColor") } }
    @Published var glowColorHex: String { didSet { save(glowColorHex, "glowColorHex") } }
    @Published var glowWhenPaused: Bool { didSet { save(glowWhenPaused, "glowWhenPaused") } }
    @Published var autoCheckUpdates: Bool { didSet { save(autoCheckUpdates, "autoCheckUpdates") } }
    @Published var autoInstallUpdates: Bool { didSet { save(autoInstallUpdates, "autoInstallUpdates") } }

    // Live activities
    @Published var replaceVolumeHUD: Bool { didSet { save(replaceVolumeHUD, "replaceVolumeHUD") } }
    @Published var replaceBrightnessHUD: Bool { didSet { save(replaceBrightnessHUD, "replaceBrightnessHUD") } }
    @Published var batteryActivity: Bool { didSet { save(batteryActivity, "batteryActivity") } }
    @Published var bluetoothActivity: Bool { didSet { save(bluetoothActivity, "bluetoothActivity") } }
    @Published var capsLockActivity: Bool { didSet { save(capsLockActivity, "capsLockActivity") } }
    @Published var privacyActivity: Bool { didSet { save(privacyActivity, "privacyActivity") } }
    @Published var meetingActivity: Bool { didSet { save(meetingActivity, "meetingActivity") } }

    // Widgets
    @Published var calendarEnabled: Bool { didSet { save(calendarEnabled, "calendarEnabled") } }
    @Published var dayPickerStyle: DayPickerStyle { didSet { save(dayPickerStyle.rawValue, "dayPickerStyle") } }
    @Published var weatherEnabled: Bool { didSet { save(weatherEnabled, "weatherEnabled") } }
    @Published var weatherUsesLocation: Bool { didSet { save(weatherUsesLocation, "weatherUsesLocation") } }
    @Published var weatherCity: String { didSet { save(weatherCity, "weatherCity") } }
    @Published var weatherLatitude: Double { didSet { save(weatherLatitude, "weatherLatitude") } }
    @Published var weatherLongitude: Double { didSet { save(weatherLongitude, "weatherLongitude") } }
    @Published var temperatureUnit: TemperatureUnit { didSet { save(temperatureUnit.rawValue, "temperatureUnit") } }
    @Published var pomodoroWork: Int { didSet { save(pomodoroWork, "pomodoroWork") } }
    @Published var pomodoroShortBreak: Int { didSet { save(pomodoroShortBreak, "pomodoroShortBreak") } }
    @Published var pomodoroLongBreak: Int { didSet { save(pomodoroLongBreak, "pomodoroLongBreak") } }
    @Published var pomodoroRounds: Int { didSet { save(pomodoroRounds, "pomodoroRounds") } }
    @Published var mirrorEnabled: Bool { didSet { save(mirrorEnabled, "mirrorEnabled") } }
    @Published var shelfEnabled: Bool { didSet { save(shelfEnabled, "shelfEnabled") } }
    @Published var teleprompterEnabled: Bool { didSet { save(teleprompterEnabled, "teleprompterEnabled") } }
    @Published var timerEnabled: Bool { didSet { save(timerEnabled, "timerEnabled") } }
    @Published var airDropEnabled: Bool { didSet { save(airDropEnabled, "airDropEnabled") } }
    @Published var conversionEnabled: Bool { didSet { save(conversionEnabled, "conversionEnabled") } }
    @Published var teleprompterFollowsVoice: Bool { didSet { save(teleprompterFollowsVoice, "teleprompterFollowsVoice") } }
    @Published var teleprompterLanguage: AppLanguage { didSet { save(teleprompterLanguage.rawValue, "teleprompterLanguage") } }
    @Published var rainAlert: Bool { didSet { save(rainAlert, "rainAlert") } }
    @Published var meetingPrep: Bool { didSet { save(meetingPrep, "meetingPrep") } }
    @Published var meetingPrepMinutes: Int { didSet { save(meetingPrepMinutes, "meetingPrepMinutes") } }

    // More live activities
    @Published var deviceBatteryActivity: Bool { didSet { save(deviceBatteryActivity, "deviceBatteryActivity") } }
    @Published var displayActivity: Bool { didSet { save(displayActivity, "displayActivity") } }
    @Published var focusActivity: Bool { didSet { save(focusActivity, "focusActivity") } }

    // AI agents
    @Published var agentsEnabled: Bool { didSet { save(agentsEnabled, "agentsEnabled") } }
    @Published var agentActivity: Bool { didSet { save(agentActivity, "agentActivity") } }
    @Published var usageAlert: Bool { didSet { save(usageAlert, "usageAlert") } }
    @Published var usageAlertThreshold: Int { didSet { save(usageAlertThreshold, "usageAlertThreshold") } }
    @Published var usageFromAccount: Bool { didSet { save(usageFromAccount, "usageFromAccount") } }

    // Notch size, sounds, privacy
    @Published var openWidth: Double { didSet { save(openWidth, "openWidth") } }
    @Published var openHeight: Double { didSet { save(openHeight, "openHeight") } }
    @Published var adaptiveSize: Bool { didSet { save(adaptiveSize, "adaptiveSize") } }
    @Published var hideFromScreenCapture: Bool { didSet { save(hideFromScreenCapture, "hideFromScreenCapture") } }
    @Published var sounds: Bool { didSet { save(sounds, "sounds") } }
    @Published var soundVolume: Double { didSet { save(soundVolume, "soundVolume") } }

    // Home, modes and extra activities (all off by default)
    @Published var homeWidgets: [String] { didSet { save(homeWidgets, "homeWidgets") } }
    @Published var shortcutTiles: [ShortcutTile] { didSet { saveCodable(shortcutTiles, "shortcutTiles") } }
    @Published var modesEnabled: Bool { didSet { save(modesEnabled, "modesEnabled") } }
    @Published var modes: [ModeRule] { didSet { saveCodable(modes, "modes") } }
    @Published var downloadsActivity: Bool { didSet { save(downloadsActivity, "downloadsActivity") } }
    @Published var keyboardHUD: Bool { didSet { save(keyboardHUD, "keyboardHUD") } }
    @Published var networkHUD: Bool { didSet { save(networkHUD, "networkHUD") } }

    // Keyboard shortcuts
    @Published var toggleNotchShortcut: KeyboardShortcutSetting? { didSet { saveShortcut(toggleNotchShortcut, "toggleNotchShortcut") } }
    @Published var teleprompterShortcut: KeyboardShortcutSetting? { didSet { saveShortcut(teleprompterShortcut, "teleprompterShortcut") } }

    static let defaultOpenWidth: Double = 860
    static let defaultOpenHeight: Double = 170

    static let defaultAllowedApps = [
        "com.spotify.client", "com.apple.Music", "com.apple.podcasts", "com.deezer.deezer-desktop",
        "com.tidal.desktop", "com.amazon.music", "com.shiftystudio.overcast", "au.com.shiftyjelly.PocketCasts",
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]
    static let defaultAllowedDomains = [
        "youtube.com", "music.youtube.com", "open.spotify.com", "deezer.com", "soundcloud.com",
        "music.apple.com", "podcasts.apple.com", "tidal.com", "music.amazon.com", "radiofrance.fr",
        "podcasts.google.com", "pocketcasts.com", "overcast.fm", "twitch.tv",
    ]

    private init() {
        let d = UserDefaults.standard
        func value<T>(_ key: String, _ fallback: T) -> T { d.object(forKey: key) as? T ?? fallback }
        language = AppLanguage(rawValue: value("language", "fr")) ?? .fr
        appearance = NotchAppearance(rawValue: value("appearance", "liquidGlass")) ?? .liquidGlass
        displayTarget = DisplayTarget(rawValue: value("displayTarget", "builtIn")) ?? .builtIn
        openOnHover = value("openOnHover", false)
        hoverDelay = value("hoverDelay", 0.12)
        haptics = value("haptics", true)
        hideInFullscreen = value("hideInFullscreen", true)
        showOnLockScreen = value("showOnLockScreen", true)
        showMenuBarIcon = value("showMenuBarIcon", true)
        mediaEnabled = value("mediaEnabled", true)
        allowedApps = value("allowedApps", Self.defaultAllowedApps)
        allowedDomains = value("allowedDomains", Self.defaultAllowedDomains)
        showVisualizer = value("showVisualizer", true)
        showLyrics = value("showLyrics", true)
        swipeToChangeTrack = value("swipeToChangeTrack", true)
        allAudioSources = value("allAudioSources", true)
        audioGlow = value("audioGlow", true)
        glowStyle = GlowStyle(rawValue: value("glowStyle", "diffuse")) ?? .diffuse
        glowWidth = value("glowWidth", Self.GlowDefaults.width)
        glowBlur = value("glowBlur", Self.GlowDefaults.blur)
        glowIntensity = value("glowIntensity", Self.GlowDefaults.intensity)
        glowOffset = value("glowOffset", Self.GlowDefaults.offset)
        glowPulse = value("glowPulse", true)
        glowPulseSpeed = value("glowPulseSpeed", Self.GlowDefaults.pulseSpeed)
        glowUsesArtworkColor = value("glowUsesArtworkColor", true)
        glowColorHex = value("glowColorHex", "#A78BFA")
        glowWhenPaused = value("glowWhenPaused", false)
        autoCheckUpdates = value("autoCheckUpdates", true)
        autoInstallUpdates = value("autoInstallUpdates", true)
        replaceVolumeHUD = value("replaceVolumeHUD", true)
        replaceBrightnessHUD = value("replaceBrightnessHUD", true)
        batteryActivity = value("batteryActivity", true)
        bluetoothActivity = value("bluetoothActivity", true)
        capsLockActivity = value("capsLockActivity", true)
        privacyActivity = value("privacyActivity", true)
        meetingActivity = value("meetingActivity", true)
        calendarEnabled = value("calendarEnabled", true)
        dayPickerStyle = DayPickerStyle(rawValue: value("dayPickerStyle", "notchNook")) ?? .notchNook
        weatherEnabled = value("weatherEnabled", true)
        weatherUsesLocation = value("weatherUsesLocation", true)
        weatherCity = value("weatherCity", "Paris")
        weatherLatitude = value("weatherLatitude", 48.8566)
        weatherLongitude = value("weatherLongitude", 2.3522)
        temperatureUnit = TemperatureUnit(rawValue: value("temperatureUnit", "celsius")) ?? .celsius
        pomodoroWork = value("pomodoroWork", 25)
        pomodoroShortBreak = value("pomodoroShortBreak", 5)
        pomodoroLongBreak = value("pomodoroLongBreak", 15)
        pomodoroRounds = value("pomodoroRounds", 4)
        mirrorEnabled = value("mirrorEnabled", true)
        shelfEnabled = value("shelfEnabled", true)
        teleprompterEnabled = value("teleprompterEnabled", true)
        timerEnabled = value("timerEnabled", true)
        airDropEnabled = value("airDropEnabled", true)
        conversionEnabled = value("conversionEnabled", true)
        teleprompterFollowsVoice = value("teleprompterFollowsVoice", false)
        teleprompterLanguage = AppLanguage(rawValue: value("teleprompterLanguage", "fr")) ?? .fr
        rainAlert = value("rainAlert", true)
        meetingPrep = value("meetingPrep", true)
        meetingPrepMinutes = value("meetingPrepMinutes", 2)
        deviceBatteryActivity = value("deviceBatteryActivity", true)
        displayActivity = value("displayActivity", true)
        focusActivity = value("focusActivity", true)
        agentsEnabled = value("agentsEnabled", true)
        agentActivity = value("agentActivity", true)
        usageAlert = value("usageAlert", true)
        usageAlertThreshold = value("usageAlertThreshold", 80)
        usageFromAccount = value("usageFromAccount", true)
        openWidth = value("openWidth", Self.defaultOpenWidth)
        openHeight = value("openHeight", Self.defaultOpenHeight)
        adaptiveSize = value("adaptiveSize", true)
        hideFromScreenCapture = value("hideFromScreenCapture", true)
        sounds = value("sounds", true)
        soundVolume = value("soundVolume", 0.3)
        homeWidgets = value("homeWidgets", [HomeWidget.media.rawValue, HomeWidget.calendar.rawValue])
        shortcutTiles = Self.loadCodable("shortcutTiles") ?? []
        modesEnabled = value("modesEnabled", false)
        modes = Self.loadCodable("modes") ?? ModeRule.defaults
        downloadsActivity = value("downloadsActivity", false)
        keyboardHUD = value("keyboardHUD", false)
        networkHUD = value("networkHUD", false)
        toggleNotchShortcut = Self.loadShortcut("toggleNotchShortcut") ?? KeyboardShortcutSetting.defaultToggleNotch
        teleprompterShortcut = Self.loadShortcut("teleprompterShortcut") ?? nil
        isLoaded = true
        Loc.language = language
        // 0.7.2 moved the glow to a diffuse backlight: start everyone from its settings once.
        if !d.bool(forKey: "glowDiffuseMigrated") {
            d.set(true, forKey: "glowDiffuseMigrated")
            resetGlow()
        }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func saveCodable<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func loadCodable<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// A notch on the external displays too (simulated where there is no hardware notch).
    var notchOnExternalDisplays: Bool {
        get { displayTarget == .all }
        set { displayTarget = newValue ? .all : .builtIn }
    }

    /// Adds or removes a widget from the home panel (at most `HomeWidget.maxShown`).
    func setHomeWidget(_ widget: HomeWidget, shown: Bool) {
        if shown, !homeWidgets.contains(widget.rawValue), homeWidgets.count < HomeWidget.maxShown {
            homeWidgets.append(widget.rawValue)
        } else if !shown {
            homeWidgets.removeAll { $0 == widget.rawValue }
        }
    }

    func moveHomeWidget(_ widget: HomeWidget, by offset: Int) {
        guard let index = homeWidgets.firstIndex(of: widget.rawValue) else { return }
        let target = index + offset
        guard homeWidgets.indices.contains(target) else { return }
        homeWidgets.swapAt(index, target)
    }

    /// Optional properties assigned at the end of init still fire their observers: ignore those.
    private var isLoaded = false

    private func saveShortcut(_ shortcut: KeyboardShortcutSetting?, _ key: String) {
        guard isLoaded else { return }
        // An explicit "none" is stored so the default does not come back.
        defaults.set(shortcut.map { [$0.keyCode, Int($0.modifiers)] } ?? [], forKey: key)
        HotKeyCenter.shared.reload()
    }

    private static func loadShortcut(_ key: String) -> KeyboardShortcutSetting?? {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [Int] else { return nil }
        return .some(raw.count == 2 ? KeyboardShortcutSetting(keyCode: raw[0], modifiers: UInt(raw[1])) : nil)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Notchy: launch at login failed: \(error)")
            }
        }
    }
}

extension AppSettings {
    enum GlowDefaults {
        static let width: Double = 7
        static let blur: Double = 30
        static let intensity: Double = 1
        static let offset: Double = 0
        static let pulseSpeed: Double = 2.2
    }

    func resetGlow() {
        glowStyle = .diffuse
        glowWidth = GlowDefaults.width
        glowBlur = GlowDefaults.blur
        glowIntensity = GlowDefaults.intensity
        glowOffset = GlowDefaults.offset
        glowPulse = true
        glowPulseSpeed = GlowDefaults.pulseSpeed
        glowUsesArtworkColor = true
        glowWhenPaused = false
    }
}

extension Color {
    /// "#RRGGBB".
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}
