import AppKit
import Combine

/// Do Not Disturb while any running, unpaused timer has its moon on. macOS lets apps change
/// Focus only through Shortcuts, so this runs two Shortcuts the user makes once, found by name.
@MainActor
final class TimerFocus: ObservableObject {
    static let shared = TimerFocus()
    static let onShortcut = "MacSpaces Focus On"
    static let offShortcut = "MacSpaces Focus Off"
    /// A focus session from Wisp.
    static let sessionSeconds: TimeInterval = 25 * 60
    private static let turnedOnKey = "focus.dndTurnedOn"

    private var silencing = FocusSilencing(turnedOn: UserDefaults.standard.bool(forKey: TimerFocus.turnedOnKey))
    private let runner = ShortcutsService()
    private var observers: [AnyCancellable] = []
    /// Debug captures don't read the real Shortcuts list or change Focus.
    private let isRealApp = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"

    var problem: String? { runner.errorText }

    private var isActive: Bool {
        AppServices.shared.allTimers.contains { $0.isRunning && !$0.isPaused && $0.focus }
    }

    /// Whether both Shortcuts exist (read from the Shortcuts list).
    private var shortcutsReady: Bool {
        let names = AppServices.shared.shortcuts.names
        return names.contains(Self.onShortcut) && names.contains(Self.offShortcut)
    }

    /// Whether a moon can light: both Shortcuts exist. Debug captures never read the list.
    var isSetUp: Bool { !isRealApp || shortcutsReady }
    /// What turns the tapped moon on, held until the Shortcuts list has been read.
    private var pendingMoon: (() -> Void)?

    private init() {
        guard isRealApp else { return }
        for timer in AppServices.shared.allTimers {
            observers.append(timer.$focus.map { _ in () }
                .merge(with: timer.$isRunning.map { _ in () }, timer.$isPaused.map { _ in () })
                .sink { [weak self] in DispatchQueue.main.async { self?.update() } })
        }
        // The Shortcuts list loads after a timer can start, so try again once it's in.
        observers.append(AppServices.shared.shortcuts.$names.sink { [weak self] _ in
            DispatchQueue.main.async {
                // The moons light or go out with the Shortcuts.
                self?.objectWillChange.send()
                self?.update()
            }
        })
        observers.append(runner.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        })
        update()
    }

    private func update() {
        let active = isActive
        if active { AppServices.shared.shortcuts.startIfNeeded() }
        guard let action = silencing.session(active: active, silencing: true, shortcutsReady: active && shortcutsReady) else { return }
        // Saved as soon as On runs, and cleared only once Off has worked, so a failed Off or a
        // quit while it runs still leaves Off owed at the next launch.
        if action == .on { UserDefaults.standard.set(true, forKey: Self.turnedOnKey) }
        runner.run(action == .on ? Self.onShortcut : Self.offShortcut, enqueue: true) { [weak self] succeeded in
            guard let self, action == .off else { return }
            if !succeeded { self.silencing.offFailed() }
            UserDefaults.standard.set(self.silencing.turnedOn, forKey: Self.turnedOnKey)
        }
    }

    /// A page with a moon switched on is showing: reads the Shortcuts list so it can light.
    func checkSetup() {
        guard isRealApp else { return }
        AppServices.shared.shortcuts.startIfNeeded()
    }

    /// A moon was tapped on. `turnOn` runs only when both Shortcuts exist; without them the
    /// one-time setup is shown and the moon stays off.
    func turnMoonOn(_ turnOn: @escaping () -> Void) {
        guard isRealApp else { turnOn(); return }
        pendingMoon = turnOn
        AppServices.shared.shortcuts.refresh { [weak self] in
            guard let self, let turnOn = self.pendingMoon else { return }
            self.pendingMoon = nil
            guard !self.shortcutsReady else { turnOn(); return }
            let alert = NSAlert()
            alert.messageText = "One-time setup"
            alert.informativeText = """
            macOS only lets apps turn on Focus through Shortcuts. Make two shortcuts in the Shortcuts app, then you're done:

            1. "\(Self.onShortcut)": add the Set Focus action, set to turn Do Not Disturb (or any Focus) On.
            2. "\(Self.offShortcut)": the same action, set to Off.

            Then turn the moon on again. MacSpaces runs them when a timer with the moon on starts and stops.
            """
            alert.addButton(withTitle: "Open Shortcuts")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "shortcuts://create-shortcut") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Quitting: if MacSpaces isn't reopened, nothing else would turn Focus back off. A timer
    /// restored by a relaunch turns it on again. Waits a few seconds for the result: Off stays
    /// owed, for the next launch, unless the shortcut is seen to work.
    static func releaseFocusForQuit() {
        guard UserDefaults.standard.bool(forKey: turnedOnKey) else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", offShortcut]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in ended.signal() }
        guard (try? task.run()) != nil, ended.wait(timeout: .now() + 4) == .success, task.terminationStatus == 0 else { return }
        UserDefaults.standard.set(false, forKey: turnedOnKey)
    }

    // MARK: - From the old Focus timer

    /// Keys of the Focus timer this replaced. A session running as MacSpaces updates carries on
    /// as a timer, once; everything else about it is let go.
    private static let oldKeys = ["focus.phaseRest", "focus.remaining", "focus.deadline", "focus.completed", "focus.day",
                                  "focus.dnd", "focus.autoNext"]

    static func migrateOldSession(defaults: UserDefaults = .standard) {
        defer { oldKeys.forEach(defaults.removeObject) }
        guard let deadline = defaults.object(forKey: "focus.deadline") as? Date, deadline > Date() else { return }
        let isBreak = defaults.bool(forKey: "focus.phaseRest")
        AppServices.shared.startTimer(seconds: deadline.timeIntervalSinceNow, name: isBreak ? "Break" : "Focus",
                                      focus: !isBreak && defaults.bool(forKey: "focus.dnd"))
    }
}
