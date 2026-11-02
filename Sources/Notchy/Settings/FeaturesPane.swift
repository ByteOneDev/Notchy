import SwiftUI

/// Every feature of Notchy, on one page, each with its switch.
struct FeaturesPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section(L("features.panels")) {
            row("music.note", .pink, "features.music", $settings.mediaEnabled)
            row("calendar", .red, "features.calendar", $settings.calendarEnabled)
            row("tray.fill", .blue, "features.shelf", $settings.shelfEnabled)
            row("dot.radiowaves.up.forward", .blue, "features.airdrop", $settings.airDropEnabled)
            row("arrow.triangle.2.circlepath", .purple, "features.conversion", $settings.conversionEnabled)
            row("text.alignleft", .orange, "features.teleprompter", $settings.teleprompterEnabled)
            row("sparkle", .indigo, "features.agents", $settings.agentsEnabled)
            row("timer", .orange, "features.timer", $settings.timerEnabled)
            row("person.crop.square.fill", .green, "features.mirror", $settings.mirrorEnabled)
            row("cloud.sun.fill", .cyan, "features.weather", $settings.weatherEnabled)
        }
        Section {
            ForEach(HomeWidget.allCases) { widget in
                Toggle(isOn: Binding(get: { settings.homeWidgets.contains(widget.rawValue) },
                                     set: { settings.setHomeWidget(widget, shown: $0) })) {
                    label(widget.icon, widget.color, widget.title)
                }
                .disabled(!settings.homeWidgets.contains(widget.rawValue) && settings.homeWidgets.count >= HomeWidget.maxShown)
            }
        } header: {
            Text(L("features.home"))
        } footer: {
            Text(L("features.home.footer", HomeWidget.maxShown)).font(.caption).foregroundStyle(.secondary)
        }
        Section(L("features.music")) {
            row("speaker.wave.2.fill", .pink, "features.allSources", $settings.allAudioSources)
            row("circle.dashed", .pink, "features.glow", $settings.audioGlow)
            row("waveform", .pink, "features.visualizer", $settings.showVisualizer)
            row("quote.bubble.fill", .pink, "features.lyrics", $settings.showLyrics)
            row("hand.draw.fill", .pink, "features.swipeTrack", $settings.swipeToChangeTrack)
        }
        Section(L("features.activities")) {
            row("speaker.wave.3.fill", .gray, "features.volumeHUD", $settings.replaceVolumeHUD)
            row("sun.max.fill", .yellow, "features.brightnessHUD", $settings.replaceBrightnessHUD)
            row("bolt.fill", .green, "features.battery", $settings.batteryActivity)
            row("airpodspro", .blue, "features.bluetooth", $settings.bluetoothActivity)
            row("battery.25percent", .red, "features.deviceBattery", $settings.deviceBatteryActivity)
            row("display", .blue, "features.display", $settings.displayActivity)
            row("moon.fill", .indigo, "features.focus", $settings.focusActivity)
            row("cloud.rain.fill", .cyan, "features.rain", $settings.rainAlert)
            row("calendar.badge.clock", .red, "features.meeting", $settings.meetingActivity)
            row("video.badge.checkmark", .green, "features.meetingPrep", $settings.meetingPrep)
            row("video.fill", .green, "features.privacy", $settings.privacyActivity)
            row("capslock.fill", .gray, "features.capsLock", $settings.capsLockActivity)
            row("checkmark.seal.fill", .indigo, "features.agentActivity", $settings.agentActivity)
            row("gauge.with.dots.needle.67percent", .orange, "features.usageAlert", $settings.usageAlert)
            row("arrow.down.circle.fill", .blue, "features.downloads", $settings.downloadsActivity)
            row("light.max", .gray, "features.keyboardHUD", $settings.keyboardHUD)
            row("wifi", .blue, "features.networkHUD", $settings.networkHUD)
        }
        Section(L("features.system")) {
            row("lock.fill", .gray, "features.lockScreen", $settings.showOnLockScreen)
            row("moon.stars.fill", .purple, "features.modes", $settings.modesEnabled)
            row("display.2", .blue, "features.externalNotch",
                Binding(get: { settings.notchOnExternalDisplays }, set: { settings.notchOnExternalDisplays = $0 }))
            row("arrow.up.left.and.arrow.down.right", .gray, "features.hideFullscreen", $settings.hideInFullscreen)
            row("eye.slash.fill", .gray, "features.hideFromCapture", $settings.hideFromScreenCapture)
            row("cursorarrow.motionlines", .gray, "features.hover", $settings.openOnHover)
            row("rectangle.expand.vertical", .gray, "features.adaptive", $settings.adaptiveSize)
            row("hand.tap.fill", .gray, "features.haptics", $settings.haptics)
            row("speaker.fill", .gray, "features.sounds", $settings.sounds)
            row("menubar.rectangle", .gray, "features.menuBar", $settings.showMenuBarIcon)
            row("arrow.down.circle.fill", .blue, "features.autoUpdate", $settings.autoInstallUpdates)
        }
    }

    private func row(_ icon: String, _ color: Color, _ key: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { label(icon, color, L(key)) }
    }

    private func label(_ icon: String, _ color: Color, _ text: String) -> some View {
        SettingsIconLabel(icon: icon, color: color, text: text)
    }
}

/// A colored rounded icon followed by a title, like in System Settings.
struct SettingsIconLabel: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
            Text(text)
        }
    }
}
