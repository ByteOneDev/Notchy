import AppKit
import Combine

/// Tracks the lock state and, when enabled, moves the notch windows into a SkyLight space that
/// sits above the lock screen (private API, the same trick other notch apps use).
@MainActor
final class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()

    @Published private(set) var isLocked = false
    /// True for a short moment after unlocking, to play the unlock animation.
    @Published private(set) var justUnlocked = false

    private var space: Int = 0
    private var attached = Set<Int>()
    private var cancellables = Set<AnyCancellable>()

    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int32, Int32) -> Int
    private typealias SpaceSetLevelFn = @convention(c) (Int32, Int, Int32) -> Int32
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsFn = @convention(c) (Int32, Int, CFArray, Int32) -> Int32
    private typealias RemoveWindowsFn = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private var connection: Int32 = 0
    private var addWindows: AddWindowsFn?
    private var removeWindows: RemoveWindowsFn?

    private init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenManager.shared.setLocked(true) }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LockScreenManager.shared.setLocked(false) }
        }
        setUpSpace()
    }

    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        if !locked {
            justUnlocked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.justUnlocked = false }
        }
        NotchManager.shared.controllers.values.forEach { $0.viewModel.close() }
    }

    private func setUpSpace() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else { return }
        func load<T>(_ name: String, as: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }
        guard let mainConnection = load("SLSMainConnectionID", as: MainConnectionFn.self),
              let spaceCreate = load("SLSSpaceCreate", as: SpaceCreateFn.self),
              let setLevel = load("SLSSpaceSetAbsoluteLevel", as: SpaceSetLevelFn.self),
              let showSpaces = load("SLSShowSpaces", as: ShowSpacesFn.self) else { return }
        addWindows = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsFn.self)
        removeWindows = load("SLSRemoveWindowsFromSpaces", as: RemoveWindowsFn.self)
        connection = mainConnection()
        space = spaceCreate(connection, 1, 0)
        // 400 is the level the system uses for notifications shown over the lock screen.
        _ = setLevel(connection, space, 400)
        _ = showSpaces(connection, [space] as CFArray)

        AppSettings.shared.$showOnLockScreen
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshAttachedWindows() }
            }
            .store(in: &cancellables)
    }

    private var panels: [Int: NSWindow] = [:]

    func attach(_ window: NSWindow) {
        panels[window.windowNumber] = window
        if AppSettings.shared.showOnLockScreen { moveToLockSpace(window) }
    }

    func detach(_ window: NSWindow) {
        panels[window.windowNumber] = nil
        attached.remove(window.windowNumber)
    }

    private func moveToLockSpace(_ window: NSWindow) {
        guard space != 0, let addWindows, window.windowNumber > 0 else { return }
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
        attached.insert(window.windowNumber)
    }

    private func refreshAttachedWindows() {
        if AppSettings.shared.showOnLockScreen {
            panels.values.forEach(moveToLockSpace)
        } else if let removeWindows, space != 0 {
            for number in attached {
                _ = removeWindows(connection, [number] as CFArray, [space] as CFArray)
                panels[number]?.orderFrontRegardless()
            }
            attached.removeAll()
            panels.values.forEach { $0.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle] }
        }
    }
}
