import SwiftUI

/// A button of the shortcuts widget: one of the Mac's Shortcuts, or a shell command.
struct ShortcutTile: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case shortcut, script }

    var id = UUID()
    var kind: Kind
    var name: String
    /// Name of the Shortcut, or the shell command (files dropped on the tile are $1, $2…).
    var target: String
    var icon: String
    var colorHex: String

    static let palette = ["#6366F1", "#EC4899", "#F97316", "#22C55E", "#06B6D4", "#A855F7", "#EF4444", "#64748B"]
}

/// Runs Shortcuts with the `shortcuts` command line tool, and scripts with zsh.
@MainActor
final class ShortcutRunner: ObservableObject {
    static let shared = ShortcutRunner()

    enum Status: Equatable { case running, done, failed }

    @Published private(set) var status: [UUID: Status] = [:]
    /// Last text a tile produced, shown under the tiles for a moment.
    @Published private(set) var message: String?
    private var messageWork: DispatchWorkItem?

    func run(_ tile: ShortcutTile, files: [URL] = []) {
        guard status[tile.id] != .running else { return }
        status[tile.id] = .running
        Task {
            let result = await Self.execute(tile.kind, tile.target, files: files)
            status[tile.id] = result.ok ? .done : .failed
            show(result.output.isEmpty ? nil : result.output)
            if !result.ok, result.output.isEmpty { show(L("shortcuts.failed", tile.name)) }
            // The notch may have closed during a long script: say it finished.
            if NotchManager.shared.primaryViewModel?.isOpen != true {
                LiveActivityCenter.shared.show(.shortcut(name: tile.name, icon: tile.icon, failed: !result.ok), duration: 3)
            }
            try? await Task.sleep(for: .seconds(2))
            if status[tile.id] != .running { status[tile.id] = nil }
        }
    }

    /// Runs a Shortcut by name without showing anything (used by the modes).
    func runSilently(shortcut name: String) {
        guard !name.isEmpty else { return }
        Task { _ = await Self.execute(.shortcut, name, files: []) }
    }

    private func show(_ text: String?) {
        messageWork?.cancel()
        withAnimation(.snappy) { message = text }
        guard text != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { withAnimation(.snappy) { self?.message = nil } }
        }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    nonisolated private static func execute(_ kind: ShortcutTile.Kind, _ target: String, files: [URL]) async -> (ok: Bool, output: String) {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            switch kind {
            case .shortcut:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                // The shortcut's result comes out on stdout.
                process.arguments = ["run", target] + (files.isEmpty ? [] : ["-i"] + files.map(\.path))
            case .script:
                // A login shell, so the user's PATH (Homebrew…) is there.
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", target, "notchy"] + files.map(\.path)
                process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            }
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch { return (false, error.localizedDescription) }
            // Read while it runs so a chatty script can't fill the pipe and hang.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus == 0, String(text.prefix(300)))
        }.value
    }

    /// Names of the user's Shortcuts.
    nonisolated static func availableShortcuts() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
        }.value
    }
}

struct ShortcutsWidget: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var runner = ShortcutRunner.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(widget: .shortcuts) {
                Button {
                    SettingsWindowController.shared.show(pane: .widgets)
                } label: {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(HoverButtonStyle(padding: 3))
            }
            if settings.shortcutTiles.isEmpty {
                Spacer(minLength: 0)
                Text(L("shortcuts.empty")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if let message = runner.message {
                Text(message)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(settings.shortcutTiles.prefix(6)) { tile in
                        ShortcutTileButton(tile: tile, status: runner.status[tile.id])
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ShortcutTileButton: View {
    let tile: ShortcutTile
    let status: ShortcutRunner.Status?
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        Button {
            Haptics.tap()
            ShortcutRunner.shared.run(tile)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill((Color(hex: tile.colorHex) ?? .indigo).gradient)
                    switch status {
                    case .running: ProgressView().controlSize(.small).tint(.white)
                    case .done: Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    case .failed: Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    case nil: Image(systemName: tile.icon).font(.system(size: 14, weight: .semibold))
                    }
                }
                .frame(height: 34)
                .scaleEffect(targeted ? 1.08 : hovering ? 1.03 : 1)
                Text(tile.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.15), value: hovering)
        .animation(.snappy(duration: 0.15), value: targeted)
        .help(tile.kind == .shortcut ? tile.target : tile.name)
        // Files dropped on a tile are its input.
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            ShelfStore.loadURLs(from: providers) { urls in ShortcutRunner.shared.run(tile, files: urls) }
            return true
        }
    }
}
