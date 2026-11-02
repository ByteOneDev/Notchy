import AppKit
import Combine
import Network

/// Downloads in progress in the Downloads folder. Browsers publish their progress for each
/// file (that is what draws the bars in the Finder); Notchy subscribes to it.
@MainActor
final class DownloadMonitor {
    static let shared = DownloadMonitor()

    private struct Download {
        let progress: Progress
        let name: String
        let observation: NSKeyValueObservation
    }

    private var subscriber: Any?
    private var downloads: [ObjectIdentifier: Download] = [:]
    private var order: [ObjectIdentifier] = []
    private var lastUpdate = Date.distantPast
    private var cancellables = Set<AnyCancellable>()

    func start() {
        AppSettings.shared.$downloadsActivity
            .sink { [weak self] on in on ? self?.subscribe() : self?.unsubscribe() }
            .store(in: &cancellables)
    }

    private func subscribe() {
        guard subscriber == nil else { return }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        subscriber = Progress.addSubscriber(forFileURL: folder) { progress in
            let id = ObjectIdentifier(progress)
            DispatchQueue.main.async { MainActor.assumeIsolated { DownloadMonitor.shared.added(progress, id: id) } }
            return { DispatchQueue.main.async { MainActor.assumeIsolated { DownloadMonitor.shared.removed(id) } } }
        }
    }

    private func unsubscribe() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        downloads.removeAll()
        order.removeAll()
        LiveActivityCenter.shared.dismiss(group: "download")
    }

    private func added(_ progress: Progress, id: ObjectIdentifier) {
        let url = progress.userInfo[.fileURLKey] as? URL ?? progress.fileURL
        guard let url else { return }
        // "film.mp4.crdownload" → "film.mp4"
        let partial = ["crdownload", "download", "part", "partial"]
        let name = partial.contains(url.pathExtension) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        let observation = progress.observe(\.fractionCompleted) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { DownloadMonitor.shared.update(force: false) } }
        }
        downloads[id] = Download(progress: progress, name: name, observation: observation)
        order.append(id)
        update(force: true)
    }

    private func removed(_ id: ObjectIdentifier) {
        guard let download = downloads.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        if download.progress.fractionCompleted >= 0.99 || download.progress.isFinished {
            LiveActivityCenter.shared.show(.download(name: download.name, progress: 1, count: downloads.count + 1), duration: 3)
        } else if downloads.isEmpty {
            LiveActivityCenter.shared.dismiss(group: "download")
        } else {
            update(force: true)
        }
    }

    /// Shows the latest download, a few times a second at most.
    private func update(force: Bool) {
        guard force || Date.now.timeIntervalSince(lastUpdate) > 0.25,
              let id = order.last, let download = downloads[id] else { return }
        lastUpdate = .now
        let fraction = download.progress.isIndeterminate ? 0 : download.progress.fractionCompleted
        LiveActivityCenter.shared.show(.download(name: download.name, progress: min(fraction, 0.99), count: downloads.count), duration: 60)
    }
}

/// Keyboard backlight level. Recent MacBooks change it from Control Center rather than with
/// keys, so the level itself is watched (CoreBrightness, private).
@MainActor
final class KeyboardBacklightMonitor {
    static let shared = KeyboardBacklightMonitor()

    private typealias LevelFunction = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private var read: LevelFunction?
    private var last: Float?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let selector = NSSelectorFromString("brightnessForKeyboard:")

    func start() {
        AppSettings.shared.$keyboardHUD
            .sink { [weak self] on in on ? self?.begin() : self?.stop() }
            .store(in: &cancellables)
    }

    private func begin() {
        guard timer == nil else { return }
        if client == nil {
            dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
            guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
            let client = type.init()
            guard let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber],
                  let id = ids.first, client.responds(to: selector) else { return }
            self.client = client
            keyboardID = id.uint64Value
            read = unsafeBitCast(client.method(for: selector), to: LevelFunction.self)
        }
        last = nil
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated { KeyboardBacklightMonitor.shared.poll() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let client, let read else { return }
        let level = read(client, selector, keyboardID)
        defer { last = level }
        guard let last, abs(level - last) > 0.01 else { return }
        // Ambient light also moves the level, slowly: only show what the user just did.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle < 2, !NotchManager.shared.isFullscreenActive else { return }
        LiveActivityCenter.shared.show(.keyboard(level: level))
    }
}

/// Wi-Fi joined or lost, VPN connected or disconnected.
@MainActor
final class NetworkChangeMonitor {
    static let shared = NetworkChangeMonitor()

    private let monitor = NWPathMonitor()
    private var wifi: Bool?
    private var vpn: Bool?
    private var work: DispatchWorkItem?

    func start() {
        monitor.pathUpdateHandler = { path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi)
            DispatchQueue.main.async { MainActor.assumeIsolated { NetworkChangeMonitor.shared.changed(wifi: wifi) } }
        }
        monitor.start(queue: DispatchQueue(label: "notchy.network"))
    }

    /// Waits for the network to settle: interfaces flap while connecting.
    private func changed(wifi: Bool) {
        work?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.settle(wifi: wifi) }
        }
        self.work = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func settle(wifi: Bool) {
        let vpn = Interfaces.vpnActive
        defer { self.wifi = wifi; self.vpn = vpn }
        guard AppSettings.shared.networkHUD else { return }
        if let previous = self.wifi, previous != wifi {
            LiveActivityCenter.shared.show(.network(name: wifi ? Interfaces.wifiName ?? "Wi-Fi" : "Wi-Fi", symbol: wifi ? "wifi" : "wifi.slash",
                                                    connected: wifi), duration: 2.5)
        }
        if let previous = self.vpn, previous != vpn {
            LiveActivityCenter.shared.show(.network(name: "VPN", symbol: vpn ? "lock.shield.fill" : "lock.open.fill", connected: vpn), duration: 2.5)
        }
    }
}
