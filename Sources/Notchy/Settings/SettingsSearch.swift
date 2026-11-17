import SwiftUI

/// Every setting the search field can find, with the page it lives on.
enum SettingsSearch {
    struct Result: Identifiable, Hashable {
        let pane: SettingsPane
        let key: String
        var id: String { "\(pane.rawValue).\(key)" }
        /// The label, without its number placeholders ("Seuil d'alerte : %d %" → "Seuil d'alerte").
        var title: String { SettingsSearch.clean(L(key)) }
    }

    private static let entries: [(SettingsPane, String)] = [
        (.general, "settings.language"),
        (.general, "settings.launchAtLogin"),
        (.general, "settings.menuBarIcon"),
        (.general, "settings.behavior"),
        (.general, "settings.openOnHover"),
        (.general, "settings.hoverDelay"),
        (.general, "settings.swipe"),
        (.general, "settings.feedback"),
        (.general, "settings.haptics"),
        (.general, "settings.sounds"),
        (.general, "settings.soundVolume"),
        (.general, "settings.shortcuts"),
        (.general, "settings.shortcut.notch"),
        (.general, "settings.shortcut.teleprompter"),
        (.general, "settings.display"),
        (.general, "settings.displayTarget"),
        (.general, "settings.fullscreen"),
        (.general, "settings.lockScreen"),
        (.appearance, "settings.style"),
        (.appearance, "settings.dayPicker"),
        (.appearance, "settings.dayPicker.color"),
        (.appearance, "settings.size.adaptive"),
        (.appearance, "settings.size.width"),
        (.appearance, "settings.size.height"),
        (.appearance, "settings.size.preview"),
        (.appearance, "settings.size"),
        (.appearance, "settings.privacy"),
        (.appearance, "settings.hideFromCapture"),
        (.media, "settings.media.enabled"),
        (.media, "settings.media.visualizer"),
        (.media, "settings.media.lyrics"),
        (.media, "settings.media.apps"),
        (.media, "settings.media.sites"),
        (.activities, "settings.hud"),
        (.activities, "settings.hud.volume"),
        (.activities, "settings.hud.brightness"),
        (.activities, "settings.hud.needsAccessibility"),
        (.activities, "settings.activities"),
        (.activities, "settings.activity.battery"),
        (.activities, "settings.activity.bluetooth"),
        (.activities, "settings.activity.capsLock"),
        (.activities, "settings.activity.privacy"),
        (.activities, "settings.activity.meeting"),
        (.activities, "settings.activity.deviceBattery"),
        (.activities, "settings.activity.display"),
        (.activities, "settings.activity.rain"),
        (.activities, "settings.activity.focus"),
        (.activities, "settings.activity.focus.needsAccess"),
        (.agents, "settings.agents.enabled"),
        (.agents, "settings.agents.activity"),
        (.agents, "settings.agents.usageAlert"),
        (.agents, "settings.agents.threshold"),
        (.agents, "settings.agents.claude.detail"),
        (.agents, "settings.agents.integrations"),
        (.agents, "settings.agents.other"),
        (.agents, "settings.agents.otherHint"),
        (.agents, "settings.agents.codex.detail"),
        (.agents, "settings.agents.disconnect"),
        (.agents, "settings.agents.connect"),
        (.widgets, "settings.widgets.calendar"),
        (.widgets, "settings.widgets.calendar.enabled"),
        (.widgets, "settings.widgets.meetingPrep"),
        (.widgets, "settings.widgets.meetingPrep.minutes"),
        (.widgets, "settings.widgets.teleprompter"),
        (.widgets, "settings.widgets.teleprompter.enabled"),
        (.widgets, "settings.widgets.teleprompter.voice"),
        (.widgets, "settings.widgets.teleprompter.language"),
        (.widgets, "settings.widgets.weather"),
        (.widgets, "settings.widgets.weather.enabled"),
        (.widgets, "settings.widgets.weather.location"),
        (.widgets, "settings.widgets.weather.unit"),
        (.widgets, "pomodoro.title"),
        (.widgets, "settings.pomodoro.work"),
        (.widgets, "settings.pomodoro.short"),
        (.widgets, "settings.pomodoro.long"),
        (.widgets, "settings.pomodoro.rounds"),
        (.widgets, "settings.widgets.other"),
        (.widgets, "settings.widgets.shelf"),
        (.widgets, "settings.widgets.mirror"),
        (.permissions, "perm.accessibility"),
        (.permissions, "perm.calendar"),
        (.permissions, "perm.camera"),
        (.permissions, "perm.location"),
        (.permissions, "perm.automation"),
        (.permissions, "perm.microphone"),
        (.permissions, "perm.fullDisk"),
        (.about, "about.version"),
        (.about, "menu.tour"),
        (.about, "update.title"),
        (.about, "update.autoCheck"),
        (.about, "update.autoInstall"),
        (.agents, "settings.agents.account"),
        (.features, "features.panels"),
        (.features, "features.home"),
        (.features, "features.music"),
        (.features, "features.activities"),
        (.features, "features.system"),
        (.features, "settings.fullscreen"),
        (.appearance, "glow.enabled"),
        (.appearance, "glow.style"),
        (.appearance, "glow.style.diffuse"),
        (.appearance, "glow.style.line"),
        (.appearance, "glow.pulse"),
        (.appearance, "glow.color"),
        (.appearance, "glow.color.pick"),
        (.appearance, "glow.whenPaused"),
        (.appearance, "glow.title"),
        (.widgets, "home.featureOff"),
        (.widgets, "home.add"),
        (.widgets, "home.title"),
        (.widgets, "home.widget.tasks"),
        (.widgets, "tasks.source"),
        (.widgets, "permissions.granted"),
        (.widgets, "shortcuts.addShortcut"),
        (.widgets, "shortcuts.addScript"),
        (.widgets, "shortcuts.openApp"),
        (.widgets, "home.widget.shortcuts"),
        (.modes, "features.modes"),
        (.modes, "modes.add"),
        (.modes, "modes.focusHint"),
        (.modes, "modes.when"),
        (.modes, "modes.silence"),
        (.modes, "modes.pauseMusic"),
        (.modes, "modes.startShortcut"),
        (.modes, "modes.endShortcut"),
        (.modes, "modes.blocking"),
        (.modes, "modes.strict"),
        (.modes, "modes.addSite"),
    ]

    /// Settings whose label, explanation or page name contains every word typed, accents and
    /// case ignored. The pages themselves come first.
    static func results(for query: String) -> [Result] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool { let folded = fold(text); return words.allSatisfy(folded.contains) }
        var seen = Set<String>()
        var results: [Result] = []
        for pane in SettingsPane.allCases where matches(pane.title + " " + (Lif("settings.pane.\(pane.rawValue).desc") ?? "")) {
            results.append(Result(pane: pane, key: "settings.\(pane.rawValue)"))
        }
        for (pane, key) in entries {
            let text = L(key) + " " + (Lif(key + ".desc") ?? "") + " " + pane.title
            guard matches(text), seen.insert(fold(clean(L(key))) + pane.rawValue).inserted else { continue }
            results.append(Result(pane: pane, key: key))
        }
        return Array(results.prefix(40))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Loc.locale)
    }

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*[:(]?\s*%[@d]\s*(%|min|\))?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
