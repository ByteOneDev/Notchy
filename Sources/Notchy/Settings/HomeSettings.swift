import EventKit
import SwiftUI
import UniformTypeIdentifiers

/// Which widgets the home panel shows, and in what order.
struct HomeLayoutSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Section {
            let shown = settings.homeWidgets.compactMap(HomeWidget.init)
            ForEach(Array(shown.enumerated()), id: \.element) { index, widget in
                HStack {
                    SettingsIconLabel(icon: widget.icon, color: widget.color, text: widget.title)
                    if !widget.isAvailable {
                        Text(L("home.featureOff")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { settings.moveHomeWidget(widget, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0)
                    Button { settings.moveHomeWidget(widget, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == shown.count - 1)
                    Button { settings.setHomeWidget(widget, shown: false) } label: { Image(systemName: "minus.circle.fill") }
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
            let hidden = HomeWidget.allCases.filter { !settings.homeWidgets.contains($0.rawValue) }
            Menu(L("home.add")) {
                ForEach(hidden) { widget in
                    Button { settings.setHomeWidget(widget, shown: true) } label: { Label(widget.title, systemImage: widget.icon) }
                }
            }
            .disabled(hidden.isEmpty || shown.count >= HomeWidget.maxShown)
        } header: {
            Text(L("home.title"))
        } footer: {
            Text(L("features.home.footer", HomeWidget.maxShown)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TasksSettingsSection: View {
    @ObservedObject private var tasks = TasksService.shared

    var body: some View {
        Section(L("home.widget.tasks")) {
            LabeledContent(L("tasks.source")) {
                if tasks.authorized {
                    Label(L("permissions.granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(L("tasks.allow")) { tasks.requestAccess() }
                }
            }
        }
    }
}

/// The tiles of the shortcuts widget: add, edit, reorder, delete.
struct ShortcutTilesSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var available: [String] = []
    @State private var editing: ShortcutTile?

    private static let examples: [(key: String, icon: String, command: String)] = [
        ("shortcuts.example.dark", "circle.lefthalf.filled",
         "osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode'"),
        ("shortcuts.example.awake", "cup.and.saucer.fill", "caffeinate -d -t 3600 >/dev/null 2>&1 &\necho \"☕️ 1 h\""),
        ("shortcuts.example.eject", "eject.fill",
         "osascript -e 'tell application \"Finder\" to eject (every disk whose ejectable is true)'"),
        ("shortcuts.example.port", "xmark.octagon.fill", "lsof -ti tcp:3000 | xargs kill && echo \"Port 3000 libre\""),
    ]

    var body: some View {
        Section {
            ForEach(Array(settings.shortcutTiles.enumerated()), id: \.element.id) { index, tile in
                HStack(spacing: 10) {
                    Image(systemName: tile.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill((Color(hex: tile.colorHex) ?? .indigo).gradient))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.name)
                        Text(tile.kind == .shortcut ? L("shortcuts.kind.shortcut") : tile.target.components(separatedBy: "\n").first ?? "")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                    Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == settings.shortcutTiles.count - 1)
                    Button { editing = tile } label: { Image(systemName: "pencil") }
                    Button { settings.shortcutTiles.removeAll { $0.id == tile.id } } label: { Image(systemName: "minus.circle.fill") }
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Menu(L("shortcuts.addShortcut")) {
                    if available.isEmpty { Text(L("shortcuts.none")) }
                    ForEach(available, id: \.self) { name in
                        Button(name) { add(ShortcutTile(kind: .shortcut, name: name, target: name, icon: "bolt.fill", colorHex: nextColor)) }
                    }
                }
                Menu(L("shortcuts.addScript")) {
                    Button(L("shortcuts.blankScript")) {
                        let tile = ShortcutTile(kind: .script, name: L("shortcuts.script"), target: "", icon: "terminal.fill", colorHex: nextColor)
                        add(tile)
                        editing = tile
                    }
                    Divider()
                    ForEach(Self.examples, id: \.key) { example in
                        Button(L(example.key)) {
                            add(ShortcutTile(kind: .script, name: L(example.key), target: example.command, icon: example.icon, colorHex: nextColor))
                        }
                    }
                }
                Spacer()
                Button(L("shortcuts.openApp")) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                    .buttonStyle(.link)
            }
        } header: {
            Text(L("home.widget.shortcuts"))
        } footer: {
            Text(L("shortcuts.footer")).font(.caption).foregroundStyle(.secondary)
        }
        .task { available = await ShortcutRunner.availableShortcuts() }
        .sheet(item: $editing) { tile in
            ShortcutTileEditor(tile: tile, available: available) { edited in
                if let index = settings.shortcutTiles.firstIndex(where: { $0.id == edited.id }) {
                    settings.shortcutTiles[index] = edited
                }
            }
        }
    }

    private var nextColor: String {
        ShortcutTile.palette[settings.shortcutTiles.count % ShortcutTile.palette.count]
    }

    private func add(_ tile: ShortcutTile) {
        settings.shortcutTiles.append(tile)
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard settings.shortcutTiles.indices.contains(target) else { return }
        settings.shortcutTiles.swapAt(index, target)
    }
}

private struct ShortcutTileEditor: View {
    @State var tile: ShortcutTile
    let available: [String]
    let onSave: (ShortcutTile) -> Void
    @Environment(\.dismiss) private var dismiss

    static let icons = ["bolt.fill", "terminal.fill", "play.fill", "moon.fill", "sun.max.fill", "cup.and.saucer.fill", "eject.fill",
                        "folder.fill", "doc.text.fill", "photo.fill", "camera.fill", "text.viewfinder", "qrcode", "globe",
                        "paperplane.fill", "hammer.fill", "chevron.left.forwardslash.chevron.right", "xmark.octagon.fill",
                        "lock.fill", "speaker.wave.2.fill", "headphones", "house.fill", "briefcase.fill", "sparkles"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField(L("shortcuts.name"), text: $tile.name)
                Picker(L("shortcuts.kind"), selection: $tile.kind) {
                    Text(L("shortcuts.kind.shortcut")).tag(ShortcutTile.Kind.shortcut)
                    Text(L("shortcuts.kind.script")).tag(ShortcutTile.Kind.script)
                }
                .pickerStyle(.segmented)
                if tile.kind == .shortcut {
                    Picker(L("shortcuts.kind.shortcut"), selection: $tile.target) {
                        if !available.contains(tile.target) { Text(tile.target.isEmpty ? "—" : tile.target).tag(tile.target) }
                        ForEach(available, id: \.self) { Text($0).tag($0) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("shortcuts.command"))
                        TextEditor(text: $tile.target)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 90)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                        Text(L("shortcuts.commandHint")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent(L("shortcuts.icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 4), count: 8), spacing: 4) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Button { tile.icon = icon } label: {
                                Image(systemName: icon).frame(width: 24, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(tile.icon == icon ? Color.accentColor.opacity(0.3) : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                LabeledContent(L("shortcuts.color")) {
                    HStack(spacing: 6) {
                        ForEach(ShortcutTile.palette, id: \.self) { hex in
                            Button { tile.colorHex = hex } label: {
                                Circle().fill(Color(hex: hex) ?? .gray).frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: tile.colorHex == hex ? 2 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(L("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("common.ok")) {
                    onSave(tile)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tile.name.isEmpty || tile.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 460)
    }
}
