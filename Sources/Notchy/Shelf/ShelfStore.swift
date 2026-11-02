import AppKit
import UniformTypeIdentifiers

/// Files parked in the notch. They stay where they are on disk; the shelf keeps references.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        var name: String { url.lastPathComponent }
        var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    }

    @Published private(set) var items: [Item] = []
    /// Files dropped on the converter, waiting for a format choice.
    @Published var pendingConversion: [URL] = []

    private let storageKey = "shelfItems"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { Item(url: $0) }
    }

    func add(providers: [NSItemProvider]) {
        Self.loadURLs(from: providers) { urls in self.add(urls: urls) }
    }

    func add(urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) {
            items.append(Item(url: url))
        }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
        LiveActivityCenter.shared.show(.airDrop(count: urls.count), duration: 2.5)
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: storageKey)
    }

    static func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { completion(urls) }
        }
    }
}
