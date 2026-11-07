import AppKit
import CoreGraphics

/// Why a click on a desktop couldn't move there, and where to fix it.
enum SpaceJumpProblem: Equatable {
    case accessibility, shortcuts

    var message: String {
        switch self {
        case .accessibility: return "Allow Accessibility to switch desktops"
        case .shortcuts: return "Turn on Move left and right a space in Keyboard Shortcuts"
        }
    }

    var button: String {
        switch self {
        case .accessibility: return "Open Accessibility"
        case .shortcuts: return "Open Keyboard Settings"
        }
    }

    var settingsURL: URL? {
        switch self {
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .shortcuts: return URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        }
    }
}

/// Which desktop each display is on, and what the user named them. `NSWorkspace`'s public
/// notification says when to look; the list itself is read on a worker once a change has
/// settled. Runs only while the activity setting is on or the widget shows (`AppServices`).
@MainActor
final class SpacesMonitor: ObservableObject {
    /// After the last change notification, so the activity arrives once the swipe has landed.
    static let settleDelay: TimeInterval = 0.45
    /// How long the closed notch shows a change.
    static let activityDuration: TimeInterval = 2
    /// Between steps of a jump: macOS keeps up, cutting each slide short.
    static let jumpStepDelay: TimeInterval = 0.15

    /// True while macOS lacks the symbols or answers in a shape we don't know: the widget,
    /// its gallery card and the setting all hide, and nothing else changes. A later good
    /// read brings them back (the list can come back empty while displays reconfigure).
    @Published private(set) var isUnavailable = ManagedSpaces.symbols == nil
    @Published private(set) var displays: [SpaceDisplay] = []
    /// The latest change per display, kept after it stops showing so its words stay drawn
    /// while the activity slides away.
    @Published private(set) var recent: [SpaceChange] = []
    @Published private(set) var isShowingChange = false
    @Published private(set) var names: [String: String]

    private static let readQueue = DispatchQueue(label: "dev.opensource.MacSpaces.spaces", qos: .utility)
    private var observers: [NSObjectProtocol] = []
    private var settleWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var generation = 0
    private var readInFlight = false
    private var readAgain = false
    private var hasBaseline = false
    private var isJumping = false
#if DEBUG
    private var previewing = false
#endif

    init() {
        names = UserDefaults.standard.dictionary(forKey: WidgetOptions.Keys.spaceNames) as? [String: String] ?? [:]
    }

    func start() {
        guard observers.isEmpty, ManagedSpaces.symbols != nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.spaceChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        })
        refresh()
    }

    func stop() {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers = []
        generation += 1
        readInFlight = false
        readAgain = false
        hasBaseline = false
        settleWork?.cancel()
        settleWork = nil
        hideWork?.cancel()
        hideWork = nil
        isShowingChange = false
        // `displays` stays, so a widget opening shows the last reading until the next one lands.
    }

    /// Reads the list now: on start, and as the widget appears (a desktop added or removed in
    /// Mission Control posts nothing).
    func refresh() {
        guard !observers.isEmpty else { return }
#if DEBUG
        if previewing { return }
#endif
        guard !readInFlight else { readAgain = true; return }
        readInFlight = true
        let requested = generation
        Self.readQueue.async {
            let next = ManagedSpaces.read()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == requested else { return }
                self.readInFlight = false
                self.apply(next)
                if self.readAgain { self.readAgain = false; self.refresh() }
            }
        }
    }

    /// Each notification in a run of swipes restarts the wait.
    private func spaceChanged() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func apply(_ next: [SpaceDisplay]?) {
        guard let next else {
            isUnavailable = true
            displays = []
            isShowingChange = false
            hasBaseline = false
            return
        }
        if isUnavailable { isUnavailable = false }
        let changes = hasBaseline ? SpaceLayout.changes(from: displays, to: next) : []
        hasBaseline = true
        if displays != next { displays = next }
        guard !changes.isEmpty else { return }
        recent = changes
        isShowingChange = true
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isShowingChange = false }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activityDuration, execute: work)
    }

    // MARK: - Moving

    /// Goes to a desktop by pressing the user's own Mission Control shortcut: macOS has no
    /// public way to switch, and a private one leaves the Dock out of step. Posting keys needs
    /// Accessibility, asked for here, from the click. A second click during a jump is ignored.
    func jump(to desktop: SpaceDesktop, on identifier: String?, problem: @escaping @MainActor (SpaceJumpProblem) -> Void) {
        guard !isJumping else { return }
        guard AXIsProcessTrusted() else {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            problem(.accessibility)
            return
        }
        isJumping = true
        Self.readQueue.async {
            // Fresh: desktops added or moved in Mission Control post nothing.
            let list = ManagedSpaces.read()
            let domain = "com.apple.symbolichotkeys" as CFString
            CFPreferencesAppSynchronize(domain)
            let shortcuts = SpaceLayout.shortcuts(from: CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let display = SpaceLayout.display(in: list ?? [], matching: identifier)
                let plan = display.map {
                    SpaceLayout.jump(on: $0, to: desktop, displayCount: list?.count ?? 1, shortcuts: shortcuts)
                } ?? .nothing
                switch plan {
                case .nothing:
                    self.isJumping = false
                case .noShortcut:
                    self.isJumping = false
                    problem(.shortcuts)
                case let .press(shortcut, times):
                    for step in 0..<times {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.jumpStepDelay * Double(step)) {
                            Self.press(shortcut)
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.jumpStepDelay * Double(times) + Self.settleDelay) { [weak self] in
                        self?.isJumping = false
                    }
                }
            }
        }
    }

    private static func press(_ shortcut: SpaceShortcut) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.key, keyDown: down)
            event?.flags = CGEventFlags(rawValue: shortcut.flags)
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - For a display

    func display(on identifier: String?) -> SpaceDisplay? {
        SpaceLayout.display(in: displays, matching: identifier)
    }

    /// The change to show on this display right now.
    func activity(on identifier: String?) -> SpaceDesktop? {
        isShowingChange ? lastChange(on: identifier) : nil
    }

    /// The last change here, still drawn while it slides away.
    func lastChange(on identifier: String?) -> SpaceDesktop? {
        guard let display = display(on: identifier) else { return nil }
        return recent.first { $0.display == display.identifier }?.desktop
    }

    /// "2 · Writing" for the last change here.
    func activityLabel(on identifier: String?) -> String? {
        lastChange(on: identifier).map { SpaceLayout.label(number: $0.number, name: names[$0.uuid]) }
    }

    /// An empty name forgets the desktop's name.
    func setName(_ name: String, for uuid: String) {
        let cleaned = SpaceLayout.cleaned(name: name)
        guard names[uuid] ?? "" != cleaned else { return }
        names[uuid] = cleaned.isEmpty ? nil : cleaned
        UserDefaults.standard.set(names, forKey: WidgetOptions.Keys.spaceNames)
    }

    /// The identifier `CGSCopyManagedDisplaySpaces` uses for a screen.
    static func identifier(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

#if DEBUG
    /// Synthetic desktops for the harness: `changed` shows as the activity until the next call.
    func setPreview(displays: [SpaceDisplay], names: [String: String], changed: Bool, unavailable: Bool = false) {
        previewing = true
        isUnavailable = unavailable
        self.displays = displays
        self.names = names
        recent = displays.compactMap { display in
            display.current.map { SpaceChange(display: display.identifier, desktop: $0) }
        }
        isShowingChange = changed
    }
#endif
}
