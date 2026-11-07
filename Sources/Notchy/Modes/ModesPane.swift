import SwiftUI
import UniformTypeIdentifiers

struct ModesPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = ModeEngine.shared
    @State private var shortcuts: [String] = []
    @State private var expanded: UUID?

    var body: some View {
        Section {
            Toggle(L("features.modes"), isOn: $settings.modesEnabled)
        } footer: {
            Text(L("modes.footer")).font(.caption).foregroundStyle(.secondary)
        }
        ForEach($settings.modes) { $mode in
            Section {
                DisclosureGroup(isExpanded: Binding(get: { expanded == mode.id }, set: { expanded = $0 ? mode.id : nil })) {
                    editor($mode)
                } label: {
                    HStack(spacing: 10) {
                        SettingsIconLabel(icon: mode.icon, color: .purple, text: mode.name)
                        Text(mode.trigger.title).font(.caption).foregroundStyle(.secondary)
                        if engine.active.contains(mode.id) {
                            Text(L("modes.active")).font(.caption.weight(.semibold)).foregroundStyle(.purple)
                        }
                        Spacer()
                        Toggle("", isOn: $mode.enabled).labelsHidden()
                    }
                }
            }
            .disabled(!settings.modesEnabled)
        }
        Section {
            Button(L("modes.add")) {
                let mode = ModeRule(name: L("modes.new"), icon: "moon.fill", trigger: .schedule)
                settings.modes.append(mode)
                expanded = mode.id
            }
            .disabled(!settings.modesEnabled)
        } footer: {
            Text(L("modes.focusHint")).font(.caption).foregroundStyle(.secondary)
        }
        .task { shortcuts = await ShortcutRunner.availableShortcuts() }
    }

    @ViewBuilder private func editor(_ mode: Binding<ModeRule>) -> some View {
        TextField(L("shortcuts.name"), text: mode.name)
        Picker(L("shortcuts.icon"), selection: mode.icon) {
            ForEach(ModeRule.icons, id: \.self) { Image(systemName: $0).tag($0) }
        }
        Picker(L("modes.when"), selection: mode.trigger) {
            ForEach(ModeRule.Trigger.allCases) { Text($0.title).tag($0) }
        }
        switch mode.wrappedValue.trigger {
        case .schedule:
            DatePicker(L("modes.from"), selection: time(mode.startMinutes), displayedComponents: .hourAndMinute)
            DatePicker(L("modes.to"), selection: time(mode.endMinutes), displayedComponents: .hourAndMinute)
            LabeledContent(L("modes.days")) {
                HStack(spacing: 4) {
                    // Monday first, like the French calendar.
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        let on = mode.wrappedValue.weekdays.contains(day)
                        Button {
                            if on { mode.wrappedValue.weekdays.removeAll { $0 == day } } else { mode.wrappedValue.weekdays.append(day) }
                        } label: {
                            Text(Self.dayLetter(day)).font(.caption.weight(.semibold)).frame(width: 22, height: 22)
                                .background(Circle().fill(on ? Color.purple : Color.primary.opacity(0.08)))
                                .foregroundStyle(on ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .app:
            LabeledContent(L("modes.app")) {
                HStack {
                    Text(mode.wrappedValue.appName.isEmpty ? "—" : mode.wrappedValue.appName).foregroundStyle(.secondary)
                    Button(L("modes.chooseApp")) { chooseApp(mode) }
                }
            }
        case .pomodoro, .meeting, .externalDisplay, .manual:
            EmptyView()
        }
        Toggle(L("modes.silence"), isOn: mode.silence)
        Toggle(L("modes.pauseMusic"), isOn: mode.pauseMusic)
        SiteBlockingEditor(categories: mode.blockedCategories, sites: mode.blockedSites)
        shortcutPicker(L("modes.startShortcut"), mode.startShortcut)
        shortcutPicker(L("modes.endShortcut"), mode.endShortcut)
        HStack {
            Spacer()
            Button(L("modes.delete"), role: .destructive) {
                let id = mode.wrappedValue.id
                expanded = nil
                // After the editor is gone: its bindings must not outlive the mode.
                DispatchQueue.main.async { settings.modes.removeAll { $0.id == id } }
            }
        }
    }

    private func shortcutPicker(_ title: String, _ selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text(L("modes.noShortcut")).tag("")
            if !selection.wrappedValue.isEmpty, !shortcuts.contains(selection.wrappedValue) {
                Text(selection.wrappedValue).tag(selection.wrappedValue)
            }
            ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
        }
    }

    /// Minutes since midnight as a date today, for the time pickers.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private static func dayLetter(_ weekday: Int) -> String {
        var calendar = Calendar.current
        calendar.locale = Loc.locale
        return String(calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
    }

    private func chooseApp(_ mode: Binding<ModeRule>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        mode.wrappedValue.appBundleID = id
        mode.wrappedValue.appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// What a mode blocks: whole categories, and sites added one by one with completion
/// ("you" → youtube.com, Return adds the first suggestion).
private struct SiteBlockingEditor: View {
    @Binding var categories: [String]
    @Binding var sites: [String]
    @State private var draft = ""

    private var suggestions: [String] { SiteCatalog.suggestions(for: draft, excluding: sites) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("modes.blocking")).font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                ForEach(SiteCatalog.categories) { category in
                    categoryTile(category)
                }
            }
            if !sites.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(sites, id: \.self) { site in
                        HStack(spacing: 4) {
                            Text(site).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 2)
                            Button { sites.removeAll { $0 == site } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
            }
            TextField(L("modes.addSite"), text: $draft, prompt: Text(L("modes.addSite.prompt")))
                .onSubmit(addDraft)
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(suggestions.prefix(4).enumerated()), id: \.element) { index, site in
                        Button { add(site) } label: {
                            HStack(spacing: 3) {
                                Text(site)
                                if index == 0 { Image(systemName: "return").font(.system(size: 9)) }
                            }
                            .font(.system(size: 11, weight: index == 0 ? .semibold : .regular))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(index == 0 ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(L("modes.blockedSites.hint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func categoryTile(_ category: SiteCatalog.Category) -> some View {
        let on = categories.contains(category.id)
        return Button {
            if on { categories.removeAll { $0 == category.id } } else { categories.append(category.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon).foregroundStyle(on ? .white : category.color).frame(width: 16)
                Text(category.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(category.domains.count)").font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(on ? .white.opacity(0.8) : .secondary)
            }
            .foregroundStyle(on ? .white : .primary)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? category.color : Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(category.domains.joined(separator: ", "))
    }

    /// Return: the first suggestion when the text isn't an address yet, else the address typed.
    private func addDraft() {
        if !draft.contains("."), let first = suggestions.first {
            add(first)
        } else {
            for site in SiteBlocker.parse(draft) where !sites.contains(site) { sites.append(site) }
            draft = ""
        }
    }

    private func add(_ site: String) {
        if !sites.contains(site) { sites.append(site) }
        draft = ""
    }
}
