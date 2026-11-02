import AVFoundation
import CoreLocation
import EventKit
import Speech
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, features, appearance, media, activities, widgets, modes, agents, permissions, about
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape.fill"
        case .features: "switch.2"
        case .appearance: "paintbrush.fill"
        case .media: "music.note"
        case .activities: "bolt.horizontal.fill"
        case .widgets: "square.grid.2x2.fill"
        case .modes: "moon.stars.fill"
        case .agents: "sparkle"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .features: .teal
        case .appearance: .purple
        case .media: .pink
        case .activities: .orange
        case .widgets: .blue
        case .modes: .purple
        case .agents: .indigo
        case .permissions: .green
        case .about: .secondary
        }
    }

    var title: String { L("settings.\(rawValue)") }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(pane: SettingsPane? = nil) {
        if let pane { selection.pane = pane }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.title = "Notchy"
            window.contentViewController = NSHostingController(rootView: SettingsView(selection: selection))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class SettingsSelection: ObservableObject {
    @Published var pane: SettingsPane = .general
}

struct SettingsView: View {
    @ObservedObject var selection: SettingsSelection
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { selection.pane }, set: { if let p = $0 { selection.pane = p } })) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.color.gradient))
                }
                .tag(pane)
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Notchy").font(.headline)
                        Text(UpdateChecker.currentVersion).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 4)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Form {
                switch selection.pane {
                case .general: GeneralPane()
                case .features: FeaturesPane()
                case .appearance: AppearancePane()
                case .media: MediaPane()
                case .activities: ActivitiesPane()
                case .widgets: WidgetsPane()
                case .modes: ModesPane()
                case .agents: AgentsPane()
                case .permissions: PermissionsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection.pane.title)
        }
        .frame(minWidth: 720, minHeight: 520)
        .environment(\.locale, settings.language.locale)
    }
}

private struct GeneralPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section {
            Picker(L("settings.language"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            Toggle(L("settings.launchAtLogin"), isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
            Toggle(L("settings.menuBarIcon"), isOn: $settings.showMenuBarIcon)
        }
        Section(L("settings.behavior")) {
            Toggle(L("settings.openOnHover"), isOn: $settings.openOnHover)
            if settings.openOnHover {
                LabeledContent(L("settings.hoverDelay")) {
                    Slider(value: $settings.hoverDelay, in: 0...0.6, step: 0.05) { EmptyView() }
                        .frame(width: 180)
                    Text("\(Int(settings.hoverDelay * 1000)) ms").monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
            }
            Toggle(L("settings.swipe"), isOn: $settings.swipeToChangeTrack)
        }
        Section(L("settings.feedback")) {
            Toggle(L("settings.haptics"), isOn: $settings.haptics)
            Toggle(L("settings.sounds"), isOn: $settings.sounds)
            if settings.sounds {
                LabeledContent(L("settings.soundVolume")) {
                    Slider(value: $settings.soundVolume, in: 0.05...1) { EmptyView() } onEditingChanged: { editing in
                        if !editing { Sounds.play(.activity) }
                    }
                    .frame(width: 200)
                }
            }
        }
        Section(L("settings.shortcuts")) {
            LabeledContent(L("settings.shortcut.notch")) {
                ShortcutRecorder(shortcut: $settings.toggleNotchShortcut)
            }
            LabeledContent(L("settings.shortcut.teleprompter")) {
                ShortcutRecorder(shortcut: $settings.teleprompterShortcut)
            }
        }
        Section(L("settings.display")) {
            Picker(L("settings.displayTarget"), selection: $settings.displayTarget) {
                Text(L("settings.display.builtIn")).tag(DisplayTarget.builtIn)
                Text(L("settings.display.main")).tag(DisplayTarget.main)
                Text(L("settings.display.all")).tag(DisplayTarget.all)
            }
            Toggle(L("settings.hideFullscreen"), isOn: $settings.hideInFullscreen)
            Toggle(L("settings.lockScreen"), isOn: $settings.showOnLockScreen)
        }
    }
}

private struct AppearancePane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section(L("settings.style")) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(NotchAppearance.allCases) { style in
                    StyleCard(style: style, selected: settings.appearance == style)
                        .onTapGesture { withAnimation(.snappy) { settings.appearance = style } }
                }
            }
            .padding(.vertical, 6)
            Text(L("settings.style.hint")).font(.caption).foregroundStyle(.secondary)
        }
        GlowSettingsSection()
        Section {
            Toggle(L("settings.size.adaptive"), isOn: $settings.adaptiveSize)
            LabeledContent(L("settings.size.width")) {
                Slider(value: $settings.openWidth, in: 640...1200, step: 10) { EmptyView() }.frame(width: 200)
                Text("\(Int(settings.openWidth)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            }
            LabeledContent(L("settings.size.height")) {
                Slider(value: $settings.openHeight, in: 140...240, step: 5) { EmptyView() }.frame(width: 200)
                Text("\(Int(settings.openHeight)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            }
            HStack {
                Spacer()
                Button(L("settings.size.reset")) {
                    settings.openWidth = AppSettings.defaultOpenWidth
                    settings.openHeight = AppSettings.defaultOpenHeight
                }
                Button(L("settings.size.preview")) { NotchManager.shared.openPrimary() }
            }
        } header: {
            Text(L("settings.size"))
        } footer: {
            Text(L("settings.size.hint")).font(.caption).foregroundStyle(.secondary)
        }
        Section(L("settings.privacy")) {
            Toggle(L("settings.hideFromCapture"), isOn: $settings.hideFromScreenCapture)
            Text(L("settings.hideFromCapture.hint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private struct StyleCard: View {
        let style: NotchAppearance
        let selected: Bool

        var body: some View {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    LinearGradient(colors: [.blue, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    NotchBackground(appearance: style, isOpen: true, shape: NotchShape(topRadius: 6, bottomRadius: 14))
                        .frame(width: 120, height: 44)
                }
                .frame(width: 190, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
                Text(L("settings.style.\(style.rawValue)")).font(.callout.weight(selected ? .semibold : .regular))
            }
            .contentShape(Rectangle())
        }
    }
}

private struct MediaPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var newDomain = ""

    private static let knownApps: [(String, String)] = [
        ("com.spotify.client", "Spotify"), ("com.apple.Music", "Musique / Music"), ("com.apple.podcasts", "Podcasts"),
        ("com.deezer.deezer-desktop", "Deezer"), ("com.tidal.desktop", "TIDAL"), ("com.amazon.music", "Amazon Music"),
        ("com.shiftystudio.overcast", "Overcast"), ("au.com.shiftyjelly.PocketCasts", "Pocket Casts"),
        ("com.apple.Safari", "Safari"), ("com.google.Chrome", "Chrome"), ("company.thebrowser.Browser", "Arc"),
        ("com.brave.Browser", "Brave"), ("com.microsoft.edgemac", "Edge"), ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("com.operasoftware.Opera", "Opera"),
    ]

    var body: some View {
        Section {
            Toggle(L("settings.media.enabled"), isOn: $settings.mediaEnabled)
            Toggle(L("settings.media.visualizer"), isOn: $settings.showVisualizer)
            Toggle(L("settings.media.lyrics"), isOn: $settings.showLyrics)
        }
        Section {
            ForEach(Self.knownApps, id: \.0) { bundleID, name in
                Toggle(isOn: Binding(
                    get: { settings.allowedApps.contains(bundleID) },
                    set: { on in
                        if on { settings.allowedApps.append(bundleID) } else { settings.allowedApps.removeAll { $0 == bundleID } }
                    })) {
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(.secondary)
                        }
                        Text(name)
                    }
                }
            }
        } header: {
            Text(L("settings.media.apps"))
        } footer: {
            Text(L("settings.media.apps.hint")).font(.caption).foregroundStyle(.secondary)
        }
        Section {
            ForEach(settings.allowedDomains, id: \.self) { domain in
                HStack {
                    Text(domain)
                    Spacer()
                    Button { settings.allowedDomains.removeAll { $0 == domain } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
            }
            HStack {
                TextField(L("settings.media.addDomain"), text: $newDomain)
                    .onSubmit(addDomain)
                Button(L("common.add"), action: addDomain).disabled(newDomain.isEmpty)
            }
        } header: {
            Text(L("settings.media.sites"))
        } footer: {
            Text(L("settings.media.sites.hint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func addDomain() {
        var domain = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        if let host = URL(string: domain.contains("://") ? domain : "https://\(domain)")?.host() { domain = host }
        if domain.hasPrefix("www.") { domain.removeFirst(4) }
        guard !domain.isEmpty, !settings.allowedDomains.contains(domain) else { return }
        settings.allowedDomains.append(domain)
        newDomain = ""
    }
}

private struct ActivitiesPane: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section(L("settings.hud")) {
            Toggle(L("settings.hud.volume"), isOn: $settings.replaceVolumeHUD)
            Toggle(L("settings.hud.brightness"), isOn: $settings.replaceBrightnessHUD)
            if !AXIsProcessTrusted() {
                Label(L("settings.hud.needsAccessibility"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        Section(L("settings.activities")) {
            Toggle(L("settings.activity.battery"), isOn: $settings.batteryActivity)
            Toggle(L("settings.activity.bluetooth"), isOn: $settings.bluetoothActivity)
            Toggle(L("settings.activity.capsLock"), isOn: $settings.capsLockActivity)
            Toggle(L("settings.activity.privacy"), isOn: $settings.privacyActivity)
            Toggle(L("settings.activity.meeting"), isOn: $settings.meetingActivity)
            Toggle(L("settings.activity.deviceBattery"), isOn: $settings.deviceBatteryActivity)
            Toggle(L("settings.activity.display"), isOn: $settings.displayActivity)
            Toggle(L("settings.activity.rain"), isOn: $settings.rainAlert)
            Toggle(L("settings.activity.focus"), isOn: $settings.focusActivity)
            if settings.focusActivity, !FocusMonitor.hasAccess {
                Label(L("settings.activity.focus.needsAccess"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

private struct AgentsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var claudeState = AgentIntegrations.claudeState
    @State private var codexState = AgentIntegrations.codexState
    @State private var error: String?

    var body: some View {
        Section {
            Toggle(L("settings.agents.enabled"), isOn: $settings.agentsEnabled)
            Toggle(L("settings.agents.activity"), isOn: $settings.agentActivity)
            Toggle(L("settings.agents.usageAlert"), isOn: $settings.usageAlert)
            if settings.usageAlert {
                Stepper(L("settings.agents.threshold", settings.usageAlertThreshold), value: $settings.usageAlertThreshold, in: 50...95, step: 5)
            }
        }
        Section {
            integrationRow(name: "Claude Code", icon: AgentKind.claude.symbol, color: AgentKind.claude.color,
                           installed: claudeState != .notInstalled,
                           detail: claudeState == .installedWithoutStatusLine ? L("settings.agents.claude.noStatus") : L("settings.agents.claude.detail")) {
                if claudeState == .notInstalled { try AgentIntegrations.installClaude() } else { try AgentIntegrations.uninstallClaude() }
            }
            integrationRow(name: "Codex", icon: AgentKind.codex.symbol, color: AgentKind.codex.color,
                           installed: codexState == .installed,
                           detail: codexDetail, disabled: codexState == .codexMissing || codexState == .otherNotify) {
                if codexState == .installed { try AgentIntegrations.uninstallCodex() } else { try AgentIntegrations.installCodex() }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        } header: {
            Text(L("settings.agents.integrations"))
        } footer: {
            Text(L("settings.agents.footer")).font(.caption).foregroundStyle(.secondary)
        }
        Section(L("settings.agents.other")) {
            Text(L("settings.agents.otherHint")).font(.caption).foregroundStyle(.secondary)
            Text(#"curl -d '{"agent":"gemini","project":"demo","status":"working","step":"…"}' \#(AgentIntegrations.baseURL)/agent"#)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var codexDetail: String {
        switch codexState {
        case .codexMissing: L("settings.agents.codex.missing")
        case .otherNotify: L("settings.agents.codex.otherNotify")
        default: L("settings.agents.codex.detail")
        }
    }

    private func integrationRow(name: String, icon: String, color: Color, installed: Bool, detail: String,
                                disabled: Bool = false, action: @escaping () throws -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                    if installed { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(installed ? L("settings.agents.disconnect") : L("settings.agents.connect")) {
                do {
                    try action()
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
                claudeState = AgentIntegrations.claudeState
                codexState = AgentIntegrations.codexState
            }
            .disabled(disabled)
        }
    }
}

private struct WidgetsPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var cityQuery = ""
    @State private var cityError = false

    var body: some View {
        HomeLayoutSection()
        ShortcutTilesSection()
        TasksSettingsSection()
        Section(L("settings.widgets.calendar")) {
            Toggle(L("settings.widgets.calendar.enabled"), isOn: $settings.calendarEnabled)
            Toggle(L("settings.widgets.meetingPrep"), isOn: $settings.meetingPrep)
            if settings.meetingPrep {
                Stepper(L("settings.widgets.meetingPrep.minutes", settings.meetingPrepMinutes), value: $settings.meetingPrepMinutes, in: 1...10)
            }
        }
        Section(L("settings.widgets.teleprompter")) {
            Toggle(L("settings.widgets.teleprompter.enabled"), isOn: $settings.teleprompterEnabled)
            Toggle(L("settings.widgets.teleprompter.voice"), isOn: $settings.teleprompterFollowsVoice)
            Picker(L("settings.widgets.teleprompter.language"), selection: $settings.teleprompterLanguage) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
        }
        Section(L("settings.widgets.weather")) {
            Toggle(L("settings.widgets.weather.enabled"), isOn: $settings.weatherEnabled)
            Toggle(L("settings.widgets.weather.location"), isOn: $settings.weatherUsesLocation)
                .onChange(of: settings.weatherUsesLocation) { WeatherService.shared.refresh() }
            if !settings.weatherUsesLocation {
                HStack {
                    TextField(L("settings.widgets.weather.city"), text: $cityQuery, prompt: Text(settings.weatherCity))
                        .onSubmit(searchCity)
                    Button(L("common.ok"), action: searchCity).disabled(cityQuery.isEmpty)
                }
                if cityError { Text(L("settings.widgets.weather.notFound")).font(.caption).foregroundStyle(.red) }
            }
            Picker(L("settings.widgets.weather.unit"), selection: $settings.temperatureUnit) {
                Text("°C").tag(TemperatureUnit.celsius)
                Text("°F").tag(TemperatureUnit.fahrenheit)
            }
            .pickerStyle(.segmented)
        }
        Section(L("pomodoro.title")) {
            Stepper(L("settings.pomodoro.work", settings.pomodoroWork), value: $settings.pomodoroWork, in: 5...90, step: 5)
            Stepper(L("settings.pomodoro.short", settings.pomodoroShortBreak), value: $settings.pomodoroShortBreak, in: 1...30)
            Stepper(L("settings.pomodoro.long", settings.pomodoroLongBreak), value: $settings.pomodoroLongBreak, in: 5...60, step: 5)
            Stepper(L("settings.pomodoro.rounds", settings.pomodoroRounds), value: $settings.pomodoroRounds, in: 2...8)
        }
        Section(L("settings.widgets.other")) {
            Toggle(L("settings.widgets.shelf"), isOn: $settings.shelfEnabled)
            Toggle(L("settings.widgets.mirror"), isOn: $settings.mirrorEnabled)
        }
    }

    private func searchCity() {
        let query = cityQuery
        Task {
            cityError = !(await WeatherService.shared.setCity(query))
            if !cityError { cityQuery = "" }
        }
    }
}

private struct PermissionsPane: View {
    @State private var tick = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Section {
            row(L("perm.accessibility"), L("perm.accessibility.why"), "keyboard", AXIsProcessTrusted()) {
                AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                open("Privacy_Accessibility")
            }
            row(L("perm.calendar"), L("perm.calendar.why"), "calendar", EKEventStore.authorizationStatus(for: .event) == .fullAccess) {
                CalendarService.shared.requestAccess()
            }
            row(L("perm.camera"), L("perm.camera.why"), "camera.fill", AVCaptureDevice.authorizationStatus(for: .video) == .authorized) {
                if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .video) { _ in }
                } else { open("Privacy_Camera") }
            }
            row(L("perm.location"), L("perm.location.why"), "location.fill", [.authorized, .authorizedAlways].contains(CLLocationManager().authorizationStatus)) {
                if CLLocationManager().authorizationStatus == .notDetermined { WeatherService.shared.refresh() } else { open("Privacy_LocationServices") }
            }
            row(L("perm.automation"), L("perm.automation.why"), "applescript.fill", nil) {
                open("Privacy_Automation")
            }
            row(L("perm.microphone"), L("perm.microphone.why"), "mic.fill",
                AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && SFSpeechRecognizer.authorizationStatus() == .authorized) {
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined || SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                    SFSpeechRecognizer.requestAuthorization { _ in AVCaptureDevice.requestAccess(for: .audio) { _ in } }
                } else { open("Privacy_Microphone") }
            }
            row(L("perm.fullDisk"), L("perm.fullDisk.why"), "internaldrive.fill", FocusMonitor.hasAccess) {
                open("Privacy_AllFiles")
            }
        } footer: {
            Text(L("perm.footer")).font(.caption).foregroundStyle(.secondary)
        }
        .id(tick)
        .onReceive(timer) { _ in tick += 1 }
    }

    private func row(_ title: String, _ detail: String, _ icon: String, _ granted: Bool?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted == true {
                Label(L("perm.granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon)
            } else {
                Button(granted == nil ? L("perm.open") : L("perm.grant"), action: action)
            }
        }
    }

    private func open(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

private struct AboutPane: View {
    @ObservedObject private var updater = UpdateChecker.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notchy").font(.title2.bold())
                    Text(L("about.version", UpdateChecker.currentVersion)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        Section(L("update.title")) {
            HStack {
                if updater.isInstalling { ProgressView().controlSize(.small) }
                Text(updater.statusText.isEmpty ? L("about.version", UpdateChecker.currentVersion) : updater.statusText)
                Spacer()
                if updater.availableVersion != nil, updater.canSelfUpdate {
                    Button(L("update.installNow")) { updater.install(force: true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(updater.isInstalling)
                } else if let url = updater.availableURL {
                    Button(L("about.download")) { NSWorkspace.shared.open(url) }
                } else {
                    Button(L("menu.updates")) { updater.check(userInitiated: true) }
                }
            }
            Toggle(L("update.autoCheck"), isOn: $settings.autoCheckUpdates)
            Toggle(L("update.autoInstall"), isOn: $settings.autoInstallUpdates)
                .disabled(!settings.autoCheckUpdates)
            if !updater.canSelfUpdate {
                Label(L("update.notInApplications"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        Section {
            Link("GitHub — ByteOneDev/Notchy", destination: URL(string: "https://github.com/ByteOneDev/Notchy")!)
        }
    }
}
