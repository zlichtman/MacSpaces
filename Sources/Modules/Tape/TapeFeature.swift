import AppKit
import Combine

/// Tape inside MacSpaces, off for everyone until its switch is turned on. While it's off there is
/// no controller, no status item and no observer: nothing runs and nothing is asked for.
@MainActor
final class TapeFeature: ObservableObject {
    static let shared = TapeFeature()
    /// The separate Tape app: its settings are copied once, and it's offered a Quit button.
    nonisolated static let separateAppIdentifier = "dev.opensource.Tape"

    @Published private(set) var isOn: Bool
    @Published private(set) var controller: TapeController?
    /// Off was chosen and windows are still going back; the switch waits for them.
    @Published private(set) var isTurningOff = false
    /// The separate Tape app is running, so this one holds off: two would move the same windows.
    @Published private(set) var separateAppRunning = false

    private var overlays: TabOverlayManager?
    private var statusItem: TapeStatusItem?
    private var permissionTimer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var stopWaiters: [() -> Void] = []

    /// Debug harnesses never start Tape: they run under their own bundle identifiers.
    private static var isRealApp: Bool { Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" }

    private init() {
        isOn = Self.isRealApp && UserDefaults.standard.bool(forKey: WidgetOptions.Keys.tapeEnabled)
    }

    /// Stored on from an earlier run. Never asks for Accessibility: without it, Tape waits.
    func startAtLaunch() {
        if isOn { start(asking: false) }
    }

    /// The Settings switch and the menu's Turn Off Tape.
    func setOn(_ on: Bool) {
        guard Self.isRealApp, !isTurningOff, on != isOn else { return }
        isOn = on
        UserDefaults.standard.set(on, forKey: WidgetOptions.Keys.tapeEnabled)
        // The desktops card reads SpacesMonitor, which runs while Tape is on.
        AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
        if on { start(asking: true) } else { stop {} }
    }

    /// Before MacSpaces quits: windows go back first, at most `TapeController.shutdown`'s 9 s.
    /// The stored switch stays, so Tape comes back with MacSpaces.
    var needsStopBeforeQuit: Bool { controller != nil }
    func stopForQuit(completion: @escaping () -> Void) { stop(completion: completion) }

    private func start(asking: Bool) {
        guard controller == nil else { return }
        TapeSettings.importOnce(into: .standard) {
            UserDefaults.standard.persistentDomain(forName: Self.separateAppIdentifier)
        }
        let controller = TapeController(settings: TapeSettings())
        self.controller = controller
        overlays = TabOverlayManager(controller: controller)
        statusItem = TapeStatusItem(feature: self, controller: controller)
        observe()
        if asking, !controller.hasAccessibility { controller.askForAccessibility() }
        startWhenReady()
    }

    /// Runs Tape unless the separate app is running or Accessibility is missing, each of which
    /// comes back here when it clears.
    private func startWhenReady(separateAppEnded: Bool = false) {
        guard let controller, !isTurningOff else { return }
        // The list can still name an app that has just ended.
        separateAppRunning = !separateAppEnded && NSRunningApplication.runningApplications(withBundleIdentifier: Self.separateAppIdentifier)
            .contains { !$0.isTerminated }
        guard !separateAppRunning else { return }
        controller.checkPermission()
        guard controller.hasAccessibility else { waitForAccessibility(); return }
        stopWaitingForAccessibility()
        controller.resume()
    }

    /// Nothing tells an app that System Settings granted Accessibility, and MacSpaces may not
    /// come back to the front, so it looks every two seconds until then.
    private func waitForAccessibility() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let controller = self.controller else { return }
                controller.checkPermission()
                guard controller.hasAccessibility else { return }
                self.startWhenReady()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func stopWaitingForAccessibility() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, launched) in [(NSWorkspace.didLaunchApplicationNotification, true), (NSWorkspace.didTerminateApplicationNotification, false)] {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.separateAppIdentifier else { return }
                Task { @MainActor [weak self] in self?.separateApp(launched: launched) }
            }
            observers.append((workspace, token))
        }
        let token = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.controller?.checkPermission() }
        }
        observers.append((NotificationCenter.default, token))
    }

    private func separateApp(launched: Bool) {
        if launched {
            separateAppRunning = true
            controller?.pause()
        } else {
            startWhenReady(separateAppEnded: true)
        }
    }

    /// Only from the Quit Tape button.
    func quitSeparateApp() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.separateAppIdentifier).forEach { $0.terminate() }
    }

    /// The menu's Start Tape. What's missing is explained on the page.
    func startFromMenu() {
        if separateAppRunning || controller?.hasAccessibility != true { openPage() } else { controller?.perform(.togglePause) }
    }

    func openPage(card: String? = nil) {
        SettingsNavigationModel.shared.open(.tape, card: card)
        SettingsWindowController.shared.show()
    }

    // MARK: - Stopping

    private func stop(completion: @escaping () -> Void) {
        guard let controller else { completion(); return }
        stopWaiters.append(completion)
        guard !isTurningOff else { return }
        isTurningOff = true
        stopWaitingForAccessibility()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        overlays = nil
        statusItem?.remove()
        statusItem = nil
        controller.shutdown { [weak self] in self?.finishStopping() }
    }

    private func finishStopping() {
        guard isTurningOff else { return }
        controller = nil
        isTurningOff = false
        separateAppRunning = false
        let waiters = stopWaiters
        stopWaiters = []
        waiters.forEach { $0() }
    }

    // MARK: - Shortcuts

    /// MacSpaces' own shortcuts win over Tape's: `NookHotKeys` has Tape let go while it registers,
    /// and what Tape then can't have shows as unavailable on its Keyboard card.
    func releaseShortcuts() { controller?.releaseShortcuts() }
    func restoreShortcuts() { controller?.restoreShortcuts() }
}
