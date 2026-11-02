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
        model.tab = .home
        for layout in homeLayouts {
            let name = layout.map(\.rawValue).joined(separator: "-")
            let view = OpenNotchView(viewModel: model, homeOverride: layout)
            save(frame(view, size: model.openSize), to: folder.appendingPathComponent("home-\(name).png"))
        }
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
