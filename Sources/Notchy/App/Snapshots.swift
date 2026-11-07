import AppKit
import SwiftUI

/// Development aid: `open -n --env NOTCHY_SNAPSHOTS=<folder> Notchy.app` renders the open notch
/// (every panel, and several home layouts) to PNG files in that folder, then quits.
@MainActor
enum Snapshots {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["NOTCHY_SNAPSHOTS"] else { return }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        // Leave time for the weather, calendar and media to load.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            NowPlayingService.shared.showSampleTrack()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                render(to: folder)
                NSApp.terminate(nil)
            }
        }
    }

    private static let homeLayouts: [[HomeWidget]] = [
        [.media, .calendar], [.media], [.weather], [.media, .weather, .calendar], [.media, .tasks, .network],
        [.rain, .shortcuts, .weather], [.weather, .rain], [.tasks, .shortcuts], [.calendar, .network],
    ]

    private static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let screen = NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.main else { return }
        let model = NotchViewModel(screen: screen)
        for tab in NotchTab.allCases where tab != .mirror {
            model.tab = tab
            save(frame(OpenNotchView(viewModel: model), size: model.openSize), to: folder.appendingPathComponent("tab-\(tab.rawValue).png"))
        }
        model.tab = .timer
        QuickTimer.shared.start(minutes: 12)
        save(frame(OpenNotchView(viewModel: model), size: model.openSize), to: folder.appendingPathComponent("tab-timer-running.png"))
        QuickTimer.shared.stop()
        // The agenda scrolled down, to check the faded edges and the clipping.
        model.tab = .calendar
        CalendarService.shared.agendaMaxOffset = 90
        CalendarService.shared.scrollAgenda(by: 90)
        save(frame(OpenNotchView(viewModel: model), size: model.openSize), to: folder.appendingPathComponent("tab-calendar-scrolled.png"))
        CalendarService.shared.agendaOffset = 0
        // The glow around the closed notch, in both styles, on a wallpaper.
        let glowStyle = AppSettings.shared.glowStyle
        for style in GlowStyle.allCases {
            AppSettings.shared.glowStyle = style
            save(glowScene(notch: model.notchSize), to: folder.appendingPathComponent("glow-\(style.rawValue).png"))
        }
        AppSettings.shared.glowStyle = glowStyle
        model.tab = .home
        // Each style of the calendar's day picker (the setting is put back afterwards).
        let settings = AppSettings.shared
        let style = settings.dayPickerStyle
        for picker in DayPickerStyle.allCases {
            settings.dayPickerStyle = picker
            let view = OpenNotchView(viewModel: model, homeOverride: [.media, .calendar])
            save(frame(view, size: model.openSize), to: folder.appendingPathComponent("daypicker-\(picker.rawValue).png"))
        }
        settings.dayPickerStyle = style
        for layout in homeLayouts {
            let name = layout.map(\.rawValue).joined(separator: "-")
            let view = OpenNotchView(viewModel: model, homeOverride: layout)
            save(frame(view, size: model.openSize), to: folder.appendingPathComponent("home-\(name).png"))
        }
    }

    private static func glowScene(notch: CGSize) -> some View {
        let shape = NotchShape(topRadius: 6, bottomRadius: 11)
        let color = Color(red: 1, green: 0.42, blue: 0.35)
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.22, green: 0.18, blue: 0.42), Color(red: 0.5, green: 0.3, blue: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.black.opacity(0.3)).frame(height: notch.height)
            ZStack {
                shape.fill(Color.black)
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                    Spacer()
                    AudioVisualizer(color: color, playing: false)
                }
                .padding(.horizontal, 10)
            }
            .frame(width: notch.width + 100, height: notch.height)
            .background { if AppSettings.shared.glowStyle == .diffuse { AudioGlow(shape: shape, color: color) } }
            .overlay { if AppSettings.shared.glowStyle == .line { AudioGlow(shape: shape, color: color) } }
        }
        .frame(width: 700, height: 220)
        .environment(\.colorScheme, .dark)
    }

    private static func frame(_ view: some View, size: CGSize) -> some View {
        view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .clipShape(NotchShape(topRadius: 12, bottomRadius: 32))
            .padding(20)
            .background(Color(white: 0.35))
            .environment(\.colorScheme, .dark)
    }

    private static func save(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? data?.write(to: url)
    }
}
