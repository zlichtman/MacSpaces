import AppKit
import ApplicationServices
import ColorSync
import Combine


private final class DisplayStripState {
    var display: TapeDisplay
    var screen: NSScreen?
    var strip = Strip()
    let animator: WindowAnimator
    let scrollClock: FrameClocking
    var lastTargets: [WindowID: CGRect] = [:]
    var lastAttemptFrames: [WindowID: CGRect] = [:]
    init(display: TapeDisplay, screen: NSScreen?, animator: WindowAnimator, scrollClock: FrameClocking) {
        self.display = display
        self.screen = screen
        self.animator = animator
        self.scrollClock = scrollClock
    }
}

struct TapeDisplayChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let enabled: Bool
    let windowCount: Int
}

struct TapeWindowChoice: Identifiable, Equatable {
    let id: WindowID
    let name: String
    let managed: Bool
}

/// What the menu needs to know about the focused column to label and enable its items.
struct TapeFocusedColumn {
    let index: Int
    let columnCount: Int
    let windowCount: Int
    let tabbed: Bool
    /// nil when the width was set by dragging rather than a preset.
    let widthFraction: Double?
}

struct TapeTabGroup: Identifiable, Equatable {
    let id: WindowID
    let frame: CGRect
    let windows: [TapeWindowChoice]
    let active: WindowID?
}

@MainActor
final class TapeController: ObservableObject {
    let settings: TapeSettings
    let isPreview: Bool
    @Published private(set) var hasAccessibility = false
    @Published private(set) var isPaused = true
    @Published private(set) var isRestoring = false
    @Published private(set) var managedCount = 0
    @Published private(set) var displayName = "No Display"
    @Published private(set) var displayChoices: [TapeDisplayChoice] = []
    @Published private(set) var message: String?
    @Published private(set) var shortcutConflicts: [String] = []
    @Published private(set) var manageAllWindows = true
    @Published private(set) var managedWindowChoices: [TapeWindowChoice] = []
    @Published private(set) var tabGroups: [TapeTabGroup] = []
    /// LaunchServices answers each name lookup with a round trip; names are stable per process.
    private var appNames: [pid_t: String] = [:]
    var onStatusChange: (() -> Void)?

    private let server: WindowServer
    private let hotKeys = HotKeys()
    private let scrollInput = ScrollInput()
    private let firstAnimator: WindowAnimator
    private let firstScrollClock: FrameClocking
    private let animatorFactory: () -> WindowAnimator
    private let clockFactory: () -> FrameClocking
    private var states: [String: DisplayStripState] = [:]
    private var displays: [TapeDisplay] = []
    private var activeDisplay: String?
    private var scrollDisplay: String?
    private var scrollClockAvailable = true
    private var pendingScrollFrames: [WindowID: CGRect]?
    private var scrollIdle: DispatchWorkItem?
    private var originalFrames: [WindowID: CGRect] = [:]
    private var originalDisplays: [WindowID: String] = [:]
    private var originalOrigins: [WindowID: CGPoint] = [:]
    private var snapshots: [WindowID: WindowSnapshot] = [:]
    private var rememberedColumns: [WindowID: Column] = [:]
    /// The columns beside each window when it was last on a strip, so a hidden, minimized or
    /// other-desktop window returns to its slot instead of beside whichever column has focus.
    private var rememberedNeighbors: [WindowID: (left: [WindowID], right: [WindowID])] = [:]
    private var restorationSnapshots: [WindowID: WindowSnapshot] = [:]
    private var restorationOwners: [WindowID: String] = [:]
    private var owners: [WindowID: String] = [:]
    private var floating: Set<WindowID> = []
    private var selectedWindows: Set<WindowID> = []
    private var interactingWindow: WindowID?
    private var interactionDisplay: String?
    private var dragTick: TimeInterval?
    private var pendingTransfers: Set<WindowID> = []
    private var externalFocus: WindowID?
    private var scanPending: DispatchWorkItem?
    private var scanInFlight = false
    private var scanRequest = 0
    private var rescanNeeded = false
    private var stopping = false
    private var revision = 0
    private var focusIntent = FocusIntent()
    private let permissionCheck: () -> Bool
    private let log: (String) -> Void
    private let registerShortcuts: Bool
    private let displayOverride: [TapeDisplay]?
    private var appliedLayout: LayoutOptions
    private var appliedPolicy: AppPolicy
    private var appliedReduceMotion: Bool
    private var appliedDisabledDisplays: Set<String>
    private var appliedDisabledSpaces: Set<String>
    /// The Spaces each display shows, from the latest scan; nil without the private list.
    @Published private(set) var spaces: [SpaceDisplay]?
    private var screenToken: NSObjectProtocol?
    private var activationTokens: [NSObjectProtocol] = []
    private var appIsActive = NSApp?.isActive ?? false
    /// Which shortcuts Tape holds, so it can let go of them while `NookHotKeys` registers.
    private var heldShortcuts: ((TapeAction) -> Bool)?
    private var subscriptions: Set<AnyCancellable> = []

    init(
        settings: TapeSettings = TapeSettings(), server: WindowServer = AXWindowServer(),
        previewOnly: Bool = false,
        animator: WindowAnimator = Animator(), permissionCheck: @escaping () -> Bool = AXIsProcessTrusted,
        registerShortcuts: Bool = true, geometry: ScreenGeometry? = nil,
        scrollClock: FrameClocking = FrameClock(),
        log: @escaping (String) -> Void = TapeLog.shared.write, displays: [TapeDisplay]? = nil,
        animatorFactory: @escaping () -> WindowAnimator = { Animator() },
        clockFactory: @escaping () -> FrameClocking = { FrameClock() }
    ) {
        self.isPreview = previewOnly
        self.settings = settings
        self.server = server
        firstAnimator = animator
        firstScrollClock = scrollClock
        self.animatorFactory = animatorFactory
        self.clockFactory = clockFactory
        self.permissionCheck = permissionCheck
        self.log = log
        self.registerShortcuts = registerShortcuts
        displayOverride =
            displays ?? geometry.map { [TapeDisplay(id: "preview", name: "Display", geometry: $0)] }
        appliedLayout = settings.layout
        appliedPolicy = settings.appPolicy
        appliedReduceMotion = settings.reduceMotion
        appliedDisabledDisplays = settings.disabledDisplays
        appliedDisabledSpaces = settings.disabledSpaces
        hasAccessibility = permissionCheck()
        updateScreens()
        server.onChange = { [weak self] in self?.scheduleScan() }
        server.onWindowRemoved = { [weak self] in self?.removeWindow($0) }
        server.onWindowInteraction = { [weak self] id, frame, kind, finished in
            self?.interact(with: id, frame: frame, kind: kind, finished: finished)
        }
        server.onFocusChange = { [weak self] id in self?.followFocus(id) }
        server.onDesktopChange = { [weak self] in
            guard let self else { return }
            self.cancelMotion()
            self.revision += 1
            self.focusIntent = FocusIntent()
            self.publish([], to: \.tabGroups)
            self.pendingTransfers.removeAll()
            self.clearTargets()
            self.scheduleScan(immediately: true)
        }
        server.onStall = { [weak self] in
            guard let self, !self.stopping else { return }
            self.scanInFlight = false
            if self.isRestoring {
                self.isRestoring = false
                self.message =
                    "An app did not accept its restored frame. Tape is paused. Resume after the app responds."
                self.onStatusChange?()
                return
            }
            self.message =
                "An app stopped responding. Tape paused and restarted its window worker. Resume to try again."
            self.pause()
        }
        hotKeys.onAction = { [weak self] in self?.perform($0) }
        scrollInput.onScroll = { [weak self] delta, point in self?.scroll(by: delta, at: point) }
        // Tape's own Settings keep ordinary scrolling.
        for (name, active) in [(NSApplication.didBecomeActiveNotification, true), (NSApplication.didResignActiveNotification, false)] {
            activationTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.appIsActive = active
                    self?.updateScrollTargets()
                }
            })
        }
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }.store(in: &subscriptions)
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cancelMotion()
                self.revision += 1
                self.pendingTransfers.removeAll()
                self.updateScreens()
                self.clearTargets()
                self.scheduleScan()
            }
        }
    }

    private var activeState: DisplayStripState? { activeDisplay.flatMap { states[$0] } }
    private var isScrolling: Bool { scrollDisplay != nil }
    private var isAnimating: Bool { states.values.contains { $0.animator.isAnimating } }
    private func isEnabled(_ id: String) -> Bool { !settings.disabledDisplays.contains(id) }
    /// Whether the desktop showing on a display is on. Separate from `isEnabled`, which decides
    /// what restoration and `applySettings` still own: a window arranged on a desktop since turned
    /// off goes back like any other.
    private func isDesktopOn(_ id: String) -> Bool {
        !SpaceLayout.isShowingDisabled(on: id, in: spaces, disabled: settings.disabledSpaces)
    }
    /// Displays that can't take a window right now.
    private var unavailableDisplays: Set<String> {
        settings.disabledDisplays.union(displays.map(\.id).filter { !isDesktopOn($0) })
    }
    /// The focused display shows a desktop Tape is off on.
    var isOffOnThisDesktop: Bool { activeDisplay.map { !isDesktopOn($0) } ?? false }
    var canArrange: Bool {
        !isPaused && !isRestoring && !isPreview && activeDisplay.map(isEnabled) == true
            && activeState?.strip.columns.isEmpty == false
    }
    var focusedDisplayID: String? { activeDisplay }
    var canSendToDisplay: Bool {
        canArrange
            && activeDisplay.flatMap {
                DisplayLayout.next(after: $0, in: displays, excluding: unavailableDisplays)
            } != nil
    }
    func canReceiveWindows(_ id: String) -> Bool { !unavailableDisplays.contains(id) }
    var displaySummary: String {
        let enabled = displayChoices.filter(\.enabled).count
        if enabled == 0 { return "No displays enabled" }
        return enabled == 1
            ? "\(windowCountText) on \(displayChoices.first(where: \.enabled)?.name ?? displayName)"
            : "\(windowCountText) across \(enabled) displays"
    }
    var windowCountText: String { managedCount == 1 ? "1 window" : "\(managedCount) windows" }
    var focusedColumn: TapeFocusedColumn? {
        guard canArrange, let strip = activeState?.strip, let index = strip.focusedIndex else { return nil }
        let column = strip.columns[index]
        return TapeFocusedColumn(
            index: index, columnCount: strip.columns.count, windowCount: column.windows.count,
            tabbed: column.mode == .tabbed, widthFraction: strip.displayedFraction(of: index))
    }
    /// The window Float / Tile acts on: nil when there is none, true when Tape leaves it alone.
    var focusedWindowFloats: Bool? {
        guard !isPaused, !isRestoring, !isPreview,
            let id = externalFocus ?? activeState?.strip.focusedWindow, snapshots[id]?.isTileable == true,
            settings.appPolicy.manages(snapshots[id]?.bundleIdentifier), owners[id].map(isEnabled) == true,
            owners[id].map(isDesktopOn) == true
        else { return nil }
        return !managesWindow(id)
    }

    func checkPermission() {
        hasAccessibility = permissionCheck()
        if !hasAccessibility, !isPaused {
            message = "Accessibility access was removed. Enable it to resume Tape."
            pause()
        }
        onStatusChange?()
    }
    /// From the switch: macOS's own prompt, which opens its settings if the owner agrees.
    func askForAccessibility() {
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openAccessibilitySettings()
    }
    func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }
    func resume() {
        checkPermission()
        guard hasAccessibility, !isRestoring, !stopping, !isPreview, isPaused else { return }
        isPaused = false
        revision += 1
        scanRequest += 1
        clearTargets()
        scanInFlight = false
        rescanNeeded = false
        message = nil
        server.start()
        if registerShortcuts {
            heldShortcuts = { _ in true }
            shortcutConflicts = hotKeys.register()
            if !scrollInput.start() {
                message =
                    "Trackpad scrolling could not start. Check Accessibility access, then pause and resume Tape. Keyboard navigation still works."
            }
        }
        scheduleScan(immediately: true)
        log("Tape resumed.")
        onStatusChange?()
    }
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        revision += 1
        scanRequest += 1
        clearTargets()
        scanInFlight = false
        rescanNeeded = false
        isRestoring = true
        scanPending?.cancel()
        scrollInput.stop()
        // Paused Tape ignores arrangement shortcuts; give them back to other apps.
        if registerShortcuts {
            heldShortcuts = { $0 == .togglePause }
            _ = hotKeys.register { $0 == .togglePause }
        }
        cancelMotion()
        pendingTransfers.removeAll()
        focusIntent = FocusIntent()
        updateScrollTargets()
        server.stop()
        server.restore(frames: restorationFrames()) { [weak self] in
            guard let self else { return }
            self.isRestoring = false
            self.originalFrames.removeAll()
            self.originalDisplays.removeAll()
            self.originalOrigins.removeAll()
            self.restorationSnapshots.removeAll()
            self.restorationOwners.removeAll()
            self.onStatusChange?()
        }
        log("Tape paused; restoring windows.")
        onStatusChange?()
    }
    /// While MacSpaces registers its own shortcuts, which win. A combination this then fails to
    /// get shows on the Keyboard card.
    func releaseShortcuts() {
        if registerShortcuts { hotKeys.unregister() }
    }
    func restoreShortcuts() {
        guard registerShortcuts, !stopping, let heldShortcuts else { return }
        let conflicts = hotKeys.register(including: heldShortcuts)
        if !isPaused { shortcutConflicts = conflicts }
    }
    /// False when another app or MacSpaces itself holds the action's shortcut.
    func hasShortcut(_ action: TapeAction) -> Bool {
        !shortcutConflicts.contains { $0.hasSuffix(": " + action.label) }
    }
    func shutdown(completion: @escaping () -> Void) {
        stopping = true
        scanPending?.cancel()
        scrollInput.stop()
        cancelMotion()
        hotKeys.unregister()
        server.stop()
        var replied = false
        let finish = {
            guard !replied else { return }
            replied = true
            completion()
        }
        server.restore(frames: restorationFrames(), completion: finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { finish() }
    }

    func perform(_ action: TapeAction) {
        guard !stopping else { return }
        if action == .togglePause {
            if isPaused { resume() } else { pause() }
            return
        }
        guard !isPaused, !isRestoring, let state = activeState, isEnabled(state.display.id),
            isDesktopOn(state.display.id)
        else { return }
        interruptScrolling()
        revision += 1
        switch action {
        case .strip(let key):
            state.strip.perform(key.action)
            if settings.sharedWidths, [.nextWidth, .wider, .narrower].contains(key), let index = state.strip.focusedIndex {
                state.strip.setWidths(state.strip.columns[index].width)
            }
            if key.changesFocus, let id = state.strip.focusedWindow {
                externalFocus = id
                focusIntent.request(id, now: ProcessInfo.processInfo.systemUptime)
                server.focus(id, activate: true)
            }
            relayout(state, reveal: true)
        case .center: relayout(state, reveal: true, forceCenter: true)
        case .toggleFloat: toggleFloat()
        case .nextDisplay:
            if let next = DisplayLayout.next(
                after: state.display.id, in: displays, excluding: unavailableDisplays)
            {
                sendWindow(to: next)
            }
        case .togglePause: break
        }
        refreshStatus()
    }
    var windowChoices: [(id: WindowID, name: String, selected: Bool)] {
        displays.filter { isEnabled($0.id) }.flatMap { display -> [(id: WindowID, name: String, selected: Bool)] in
            guard let state = states[display.id] else {
                return [(id: WindowID, name: String, selected: Bool)]()
            }
            return state.strip.columns.enumerated().flatMap { index, column -> [(id: WindowID, name: String, selected: Bool)] in
                let prefix = displays.count > 1 ? display.name + " · " : ""
                return column.windows.compactMap { id in
                    guard let window = snapshots[id] else { return nil }
                    return (id: id, name: "\(prefix)\(index + 1). \(windowName(window))",
                            selected: activeDisplay == display.id && state.strip.focusedWindow == id)
                }
            }
        }
    }
    func chooseWindow(_ id: WindowID) {
        guard
            let display = displays.first(where: {
                states[$0.id]?.strip.columns.contains(where: { $0.windows.contains(id) }) == true
            }),
            isEnabled(display.id), let state = states[display.id], !isPaused, !isRestoring
        else { return }
        activeDisplay = display.id
        interruptScrolling()
        revision += 1
        state.strip.select(id)
        externalFocus = id
        focusIntent.request(id, now: ProcessInfo.processInfo.systemUptime)
        server.focus(id, activate: true)
        relayout(state, reveal: true)
        refreshStatus()
    }
    func setWidth(_ fraction: Double) {
        guard canArrange, let state = activeState else { return }
        interruptScrolling()
        revision += 1
        if settings.sharedWidths {
            guard fraction.isFinite else { return }
            state.strip.setWidths(.fraction(min(max(fraction, 0.2), 1)))
        } else { state.strip.perform(.setWidth(fraction)) }
        relayout(state, reveal: true)
        refreshStatus()
    }
    func setAllWidths(_ fraction: Double) {
        guard canArrange, fraction.isFinite, let state = activeState else { return }
        interruptScrolling()
        revision += 1
        state.strip.setWidths(.fraction(min(max(fraction, 0.2), 1)))
        relayout(state, reveal: true)
        refreshStatus()
    }

    /// Give every column on the focused display the focused column's width.
    func matchAllWidths() {
        guard canArrange, let state = activeState, let index = state.strip.focusedIndex else { return }
        interruptScrolling()
        revision += 1
        let width = state.strip.displayedFraction(of: index).map(ColumnWidth.fraction) ?? state.strip.columns[index].width
        state.strip.setWidths(width)
        relayout(state, reveal: true)
        refreshStatus()
    }

    func setManageAllWindows(_ enabled: Bool) {
        guard manageAllWindows != enabled else { return }
        manageAllWindows = enabled
        if !enabled, let id = externalFocus ?? activeState?.strip.focusedWindow {
            selectedWindows.insert(id)
        }
        reconcileWindowSelection()
    }
    func setWindowManaged(_ id: WindowID, _ enabled: Bool) {
        guard snapshots[id]?.isTileable == true else { return }
        if enabled { floating.remove(id); selectedWindows.insert(id) }
        else {
            floating.insert(id); selectedWindows.remove(id)
            // Tiling it again later joins it beside the focused column, not its old slot.
            rememberedNeighbors.removeValue(forKey: id)
        }
        reconcileWindowSelection()
    }
    private func managesWindow(_ id: WindowID) -> Bool {
        !floating.contains(id) && (manageAllWindows || selectedWindows.contains(id))
    }
    private func reconcileWindowSelection() {
        cancelMotion()
        revision += 1
        pendingTransfers.removeAll()
        clearTargets()
        var frames: [WindowID: CGRect] = [:]
        for state in states.values {
            for id in state.strip.columns.flatMap(\.windows) where !managesWindow(id) {
                state.strip.remove(id)
                if let original = originalFrames.removeValue(forKey: id) {
                    frames[id] = restored(original, id: id, on: state.display.geometry)
                }
                originalDisplays.removeValue(forKey: id)
                originalOrigins.removeValue(forKey: id)
            }
        }
        if !isPaused {
            if !frames.isEmpty { server.apply(frames: frames); updateSnapshots(frames) }
            consume(Array(snapshots.values), focused: externalFocus)
            reconcileAfterWrites()
        }
        refreshStatus()
    }

    func reorderTab(_ id: WindowID, before other: WindowID) {
        guard !isPaused, let state = states.values.first(where: { $0.strip.columns.contains { $0.windows.contains(id) && $0.windows.contains(other) } }) else { return }
        revision += 1
        state.strip.reorderTab(id, before: other)
        relayout(state, reveal: false)
        refreshStatus()
    }
    func moveTab(_ id: WindowID, to target: Int) {
        guard !isPaused, let state = states.values.first(where: { $0.strip.columns.contains { $0.windows.contains(id) } }) else { return }
        revision += 1
        state.strip.moveTab(id, to: target)
        relayout(state, reveal: false)
        refreshStatus()
    }
    func setDisplayEnabled(_ id: String, _ enabled: Bool) {
        if enabled { settings.disabledDisplays.remove(id) } else { settings.disabledDisplays.insert(id) }
    }
    func sendWindow(to destination: String) {
        guard canArrange, let source = activeState, let target = states[destination], source !== target,
            canReceiveWindows(destination), let id = source.strip.focusedWindow,
            let index = source.strip.columns.firstIndex(where: { $0.windows.contains(id) })
        else { return }
        interruptScrolling()
        revision += 1
        let column = source.strip.columns[index]
        for window in column.windows {
            source.strip.remove(window)
            owners[window] = destination
            pendingTransfers.insert(window)
        }
        let position = target.strip.focusedIndex.map { $0 + 1 } ?? target.strip.columns.count
        target.strip.columns.insert(column, at: position)
        target.strip.focusedWindow = id
        activeDisplay = destination
        externalFocus = id
        focusIntent.request(id, now: ProcessInfo.processInfo.systemUptime)
        server.focus(id, activate: true)
        relayout(source, reveal: true)
        relayout(target, reveal: true)
        let session = scanRequest
        server.settle { [weak self] in
            guard let self, session == self.scanRequest else { return }
            column.windows.forEach { self.pendingTransfers.remove($0) }
            self.scheduleScan()
        }
        refreshStatus()
    }

    /// Browse the display under the pointer; do not change the keyboard's focused display.
    func scroll(by delta: Double, at point: CGPoint? = nil) {
        guard !isPaused, !isRestoring, !isPreview, delta.isFinite else { return }
        let targetID = scrollDisplay ?? point.flatMap { DisplayLayout.at($0, in: displays) } ?? activeDisplay
        guard let targetID, let state = states[targetID], isEnabled(targetID), isDesktopOn(targetID),
            !state.strip.columns.isEmpty
        else { return }
        let geometry = state.display.geometry
        if !isScrolling {
            scrollDisplay = targetID
            if state.animator.isAnimating {
                var unscrolled = state.strip
                unscrolled.scrollOffset = 0
                let rects = StripLayout.columnRects(for: unscrolled, screen: geometry, options: settings.layout)
                for (column, logical) in zip(state.strip.columns, rects) {
                    guard let id = column.windows.first, let current = state.animator.current[id],
                        current.minX >= geometry.frame.minX, current.maxX <= geometry.frame.maxX,
                        abs(current.width - logical.width) < 1
                    else { continue }
                    state.strip.scrollOffset = logical.minX - current.minX
                    break
                }
            }
            updateSnapshots(state.animator.current)
            state.animator.cancel()
            scanPending?.cancel()
            scrollClockAvailable = state.scrollClock.start(screen: state.screen) { [weak self] in
                self?.flushScroll()
            }
        }
        revision += 1
        state.strip.scrollOffset = StripLayout.scrolledOffset(
            for: state.strip, by: delta, screen: geometry, options: settings.layout)
        let frames = StripLayout.frames(for: state.strip, screen: geometry, options: settings.layout).mapValues {
            StripLayout.parked($0, on: geometry)
        }
        if frames != state.lastTargets {
            pendingScrollFrames = frames
            state.lastTargets = frames
        }
        if !scrollClockAvailable { flushScroll() }
        scrollIdle?.cancel()
        let idle = DispatchWorkItem { [weak self] in
            self?.stopScrolling(flush: true)
            self?.reconcileAfterWrites()
        }
        scrollIdle = idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: idle)
    }
    private func updateSnapshots(_ frames: [WindowID: CGRect]) {
        for (id, frame) in frames {
            guard let window = snapshots[id] else { continue }
            snapshots[id] = WindowSnapshot(
                id: id, frame: frame, processID: window.processID, isTileable: window.isTileable,
                bundleIdentifier: window.bundleIdentifier, title: window.title)
        }
    }
    private func flushScroll() {
        guard let frames = pendingScrollFrames else { return }
        pendingScrollFrames = nil
        server.apply(frames: frames)
        updateSnapshots(frames)
        refreshTabGroups()
    }
    /// A keyboard or menu action ends browsing; leftover momentum must not pull the strip back.
    private func interruptScrolling() {
        scrollInput.suppressCurrentGesture()
        stopScrolling(flush: true)
    }
    private func stopScrolling(flush: Bool) {
        scrollIdle?.cancel()
        scrollIdle = nil
        if flush { flushScroll() }
        pendingScrollFrames = nil
        if let id = scrollDisplay { states[id]?.scrollClock.stop() }
        scrollDisplay = nil
    }
    private func cancelMotion() {
        if let owner = interactionDisplay { states[owner]?.scrollClock.stop() }
        dragTick = nil
        interactingWindow = nil
        interactionDisplay = nil
        stopScrolling(flush: false)
        server.cancelPendingWrites()
        for state in states.values {
            if state.animator.isAnimating { updateSnapshots(state.animator.current) }
            state.animator.cancel()
        }
    }
    private func clearTargets() {
        states.values.forEach {
            $0.lastTargets.removeAll()
            $0.lastAttemptFrames.removeAll()
        }
    }
    private func followFocus(_ id: WindowID) {
        guard !isPaused, !stopping, !isScrolling else { return }
        let ids = Set(states.values.flatMap { $0.strip.columns.flatMap(\.windows) })
        guard
            let resolved = focusIntent.resolve(
                observed: id, available: ids, now: ProcessInfo.processInfo.systemUptime),
            let display = displays.first(where: {
                states[$0.id]?.strip.columns.contains(where: { $0.windows.contains(resolved) }) == true
            }),
            let state = states[display.id]
        else {
            externalFocus = id
            refreshTabGroups()
            scheduleScan(immediately: true)
            return
        }
        externalFocus = resolved
        guard activeDisplay != display.id || state.strip.focusedWindow != resolved else { return }
        revision += 1
        activeDisplay = display.id
        externalFocus = resolved
        state.strip.select(resolved)
        relayout(state, reveal: true)
        refreshStatus()
    }
    private func applySettings() {
        guard
            appliedLayout != settings.layout || appliedPolicy != settings.appPolicy
                || appliedReduceMotion != settings.reduceMotion
                || appliedDisabledDisplays != settings.disabledDisplays
                || appliedDisabledSpaces != settings.disabledSpaces
        else { return }
        let layoutChanged = appliedLayout != settings.layout || appliedReduceMotion != settings.reduceMotion
            || appliedDisabledSpaces != settings.disabledSpaces
        let displayChanges = appliedDisabledDisplays.symmetricDifference(settings.disabledDisplays)
        appliedLayout = settings.layout
        appliedPolicy = settings.appPolicy
        appliedReduceMotion = settings.reduceMotion
        appliedDisabledDisplays = settings.disabledDisplays
        appliedDisabledSpaces = settings.disabledSpaces
        guard !isPaused, !stopping else {
            refreshStatus()
            return
        }
        cancelMotion()
        revision += 1
        pendingTransfers.removeAll()
        if layoutChanged {
            clearTargets()
        } else {
            for id in displayChanges {
                states[id]?.lastTargets.removeAll()
                states[id]?.lastAttemptFrames.removeAll()
            }
        }
        var restored: [WindowID: CGRect] = [:]
        for state in states.values {
            for id in state.strip.columns.flatMap(\.windows) {
                guard let snapshot = snapshots[id] else { continue }
                if !isEnabled(state.display.id) || !settings.appPolicy.manages(snapshot.bundleIdentifier) {
                    state.strip.remove(id)
                    if let original = originalFrames.removeValue(forKey: id) {
                        restored[id] = self.restored(original, id: id, on: state.display.geometry)
                    }
                    originalDisplays.removeValue(forKey: id)
                    originalOrigins.removeValue(forKey: id)
                }
            }
        }
        if !restored.isEmpty { server.apply(frames: restored) }
        for state in states.values { relayout(state, reveal: false) }
        scheduleScan(immediately: true)
        refreshStatus()
    }
    private func toggleFloat() {
        guard let state = activeState, let id = externalFocus ?? state.strip.focusedWindow,
            let snapshot = snapshots[id]
        else { return }
        guard snapshot.isTileable else { return }
        setWindowManaged(id, !managesWindow(id))
    }
    private func scheduleScan(immediately: Bool = false) {
        guard !isPaused, !stopping else { return }
        scanPending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.scan() }
        scanPending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.08), execute: item)
    }
    private func scan() {
        guard !isPaused, !stopping else { return }
        guard displays.contains(where: { isEnabled($0.id) }) else {
            refreshStatus()
            return
        }
        if scanInFlight || isAnimating || isScrolling || interactingWindow != nil || !pendingTransfers.isEmpty {
            rescanNeeded = true
            return
        }
        let scanRevision = revision
        scanRequest += 1
        let request = scanRequest
        scanInFlight = true
        server.scan(policy: settings.appPolicy) { [weak self] windows, focused, spaces in
            guard let self, request == self.scanRequest else { return }
            self.scanInFlight = false
            guard !self.isPaused, !self.stopping else { return }
            guard scanRevision == self.revision else {
                self.scheduleScan()
                return
            }
            self.publish(spaces, to: \.spaces)
            self.consume(windows, focused: focused)
            if self.rescanNeeded {
                self.rescanNeeded = false
                self.scheduleScan()
            }
        }
    }
    private func consume(_ windows: [WindowSnapshot], focused: WindowID?) {
        // A repeated window would trap the dictionaries below and leave windows parked off-screen.
        var seen: Set<WindowID> = []
        let windows = windows.filter { seen.insert($0.id).inserted }
        snapshots = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        for window in windows { restorationSnapshots[window.id] = window }
        let previousOwners = owners
        owners = Dictionary(
            uniqueKeysWithValues: windows.compactMap { window in
                DisplayLayout.owner(of: window.frame, in: displays, previous: previousOwners[window.id]).map {
                    (window.id, $0)
                }
            })
        restorationOwners.merge(owners) { _, current in current }
        let eligible = windows.filter {
            $0.isTileable && managesWindow($0.id) && settings.appPolicy.manages($0.bundleIdentifier)
                && owners[$0.id].map(isEnabled) == true && owners[$0.id].map(isDesktopOn) == true
        }
        let ids = Set(eligible.map(\.id))
        let focused = focusIntent.resolve(
            observed: focused, available: ids, now: ProcessInfo.processInfo.systemUptime)
        externalFocus = focused ?? externalFocus
        if let focused, let owner = owners[focused] { activeDisplay = owner }
        var retained = rememberedColumns
        for state in states.values {
            let columns = state.strip.columns
            for (index, column) in columns.enumerated() {
                let left = index > 0 ? columns[index - 1].windows : []
                let right = index + 1 < columns.count ? columns[index + 1].windows : []
                for id in column.windows {
                    retained[id] = column
                    rememberedNeighbors[id] = (left, right)
                }
            }
        }
        rememberedColumns = retained
        for display in displays {
            guard let state = states[display.id] else { continue }
            let local = eligible.filter { owners[$0.id] == display.id }
            let localIDs = Set(local.map(\.id))
            let previousFocus = state.strip.focusedWindow
            let previousIDs = Set(state.strip.columns.flatMap(\.windows))
            for id in state.strip.columns.flatMap(\.windows) where !localIDs.contains(id) {
                state.strip.remove(id)
            }
            let sorted = local.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
            for window in sorted where originalFrames[window.id] == nil {
                originalFrames[window.id] = window.frame
                originalDisplays[window.id] = display.id
                originalOrigins[window.id] = display.geometry.frame.origin
            }
            insert(sorted.map(\.id).filter { id in !state.strip.columns.contains { $0.windows.contains(id) } },
                   into: state, retained: retained)
            let content = StripLayout.contentRect(screen: state.display.geometry, options: settings.layout)
            for index in state.strip.columns.indices {
                for id in state.strip.columns[index].windows {
                    guard let actual = snapshots[id]?.frame, let requested = state.lastTargets[id] else { continue }
                    if actual.width > requested.width + 3 {
                        state.strip.columns[index].minimumWidth = max(state.strip.columns[index].minimumWidth, min(actual.width, content.width))
                    }
                    if state.strip.columns[index].mode == .stacked, actual.height > requested.height + 3 {
                        state.strip.columns[index].minimumHeights[id] = min(actual.height, content.height)
                    }
                }
            }
            // Apps that cannot fit together get their own columns rather than overlap.
            let priorSelection = state.strip.focusedWindow
            let tooTall = state.strip.columns.filter { column in
                column.mode == .stacked && column.windows.count > 1 &&
                    column.windows.reduce(0.0, { $0 + (column.minimumHeights[$1] ?? 1) }) + max(0, settings.gap) * Double(column.windows.count - 1) > content.height
            }.flatMap { $0.windows.dropFirst() }
            for id in tooTall { state.strip.select(id); state.strip.perform(.detach) }
            if let priorSelection { state.strip.select(priorSelection) }
            let localFocus = focused.flatMap { localIDs.contains($0) ? $0 : nil }
            if let localFocus { state.strip.select(localFocus) }
            if state.strip.focusedWindow == nil {
                state.strip.focusedWindow = state.strip.columns.first?.windows.first
            }
            let reveal =
                (localFocus.map { $0 != previousFocus } ?? false)
                || (previousFocus != nil && previousFocus != state.strip.focusedWindow)
                || state.strip.columns.count == 1
            if !reveal && previousIDs != localIDs {
                state.strip.scrollOffset = StripLayout.constrainedOffset(
                    for: state.strip, screen: state.display.geometry, options: settings.layout)
            }
            relayout(state, reveal: reveal)
        }
        restoreWindowsOnOffDesktops(windows)
        refreshStatus()
    }
    /// A desktop turned off while it shows, or since Tape was last on it, gets its windows back
    /// once a scan can see them there. Tape keeps no map of which window is on which desktop: a
    /// desktop turned off from elsewhere stays as it was until it's next visited.
    private func restoreWindowsOnOffDesktops(_ windows: [WindowSnapshot]) {
        var frames: [WindowID: CGRect] = [:]
        for window in windows where window.isTileable && originalFrames[window.id] != nil {
            guard let owner = owners[window.id], !isDesktopOn(owner), let state = states[owner],
                let original = originalFrames[window.id]
            else { continue }
            frames[window.id] = restored(original, id: window.id, on: state.display.geometry)
            originalFrames.removeValue(forKey: window.id)
            originalDisplays.removeValue(forKey: window.id)
            originalOrigins.removeValue(forKey: window.id)
        }
        guard !frames.isEmpty else { return }
        server.apply(frames: frames)
        updateSnapshots(frames)
    }
    /// Returning windows rejoin their group or the slot beside a remembered neighbor; each placement
    /// can anchor the next. Windows without either open right of the focused column, left to right.
    private func insert(_ ids: [WindowID], into state: DisplayStripState, retained: [WindowID: Column]) {
        func group(of id: WindowID) -> Int? {
            retained[id].flatMap { column in state.strip.columns.firstIndex { $0.id == column.id } }
        }
        func slot(of id: WindowID) -> Int? {
            guard let neighbors = rememberedNeighbors[id] else { return nil }
            if let left = state.strip.columns.firstIndex(where: { $0.windows.contains(where: neighbors.left.contains) }) {
                return left + 1
            }
            return state.strip.columns.firstIndex { $0.windows.contains(where: neighbors.right.contains) }
        }
        func column(for id: WindowID) -> Column {
            var column = retained[id] ?? Column(window: id)
            column.windows = [id]
            column.activeWindow = id
            return column
        }
        var pending = ids
        var lastNew: WindowID?
        while !pending.isEmpty {
            if let k = pending.firstIndex(where: { group(of: $0) != nil }), let index = group(of: pending[k]) {
                let id = pending.remove(at: k)
                let slot = retained[id]?.windows.firstIndex(of: id) ?? state.strip.columns[index].windows.count
                state.strip.columns[index].windows.insert(id, at: min(slot, state.strip.columns[index].windows.count))
            } else if let k = pending.firstIndex(where: { slot(of: $0) != nil }), let index = slot(of: pending[k]) {
                let id = pending.remove(at: k)
                state.strip.columns.insert(column(for: id), at: index)
            } else {
                let id = pending.removeFirst()
                let after = lastNew.flatMap { last in state.strip.columns.firstIndex { $0.windows.contains(last) } }
                    ?? state.strip.focusedIndex
                state.strip.columns.insert(column(for: id), at: after.map { $0 + 1 } ?? state.strip.columns.count)
                lastNew = id
            }
        }
    }
    private func relayout(_ state: DisplayStripState, reveal: Bool, forceCenter: Bool = false) {
        guard !isPaused, !stopping, isEnabled(state.display.id), isDesktopOn(state.display.id) else { return }
        guard interactingWindow == nil else { return }
        let geometry = state.display.geometry
        if reveal {
            state.strip.scrollOffset = StripLayout.revealedOffset(
                for: state.strip, screen: geometry, options: settings.layout, forceCenter: forceCenter)
        }
        let targets = StripLayout.frames(for: state.strip, screen: geometry, options: settings.layout).mapValues {
            StripLayout.parked($0, on: geometry)
        }
        var initial = snapshots.mapValues(\.frame)
        if state.animator.isAnimating {
            initial.merge(state.animator.current) { _, current in current }
            if targets == state.lastTargets { return }
        }
        let unchanged = targets.allSatisfy { id, frame in initial[id].map { Self.close($0, frame) } ?? false }
        guard !unchanged || state.animator.isAnimating else { raiseActiveTabs(state); return }
        if !state.animator.isAnimating, targets == state.lastTargets,
            targets.keys.allSatisfy({ id in
                guard let observed = initial[id], let attempted = state.lastAttemptFrames[id] else {
                    return false
                }
                return Self.close(observed, attempted)
            })
        {
            return
        }
        state.lastAttemptFrames = initial
        state.lastTargets = targets
        state.animator.animate(
            to: targets, from: initial, screen: state.screen, geometry: geometry,
            reduceMotion: settings.reduceMotion,
            write: { [weak self] frames in
                guard let self else { return }
                self.server.apply(frames: frames)
                self.updateSnapshots(frames)
                if !self.tabGroups.isEmpty { self.refreshTabGroups() }
            },
            completion: { [weak self, weak state] in
                guard let self, let state, !self.isPaused, self.states[state.display.id] === state else {
                    return
                }
                self.raiseActiveTabs(state)
                if !geometry.neighbors.isEmpty, let focused = state.strip.focusedWindow,
                    self.externalFocus == focused
                {
                    self.server.focus(focused, activate: false)
                }
                self.reconcileAfterWrites()
            })
    }
    private func reconcileAfterWrites() {
        let session = scanRequest
        server.settle { [weak self] in
            guard let self, !self.isPaused, !self.stopping, session == self.scanRequest else { return }
            self.scheduleScan()
        }
    }
    private func restored(_ frame: CGRect, id: WindowID, on geometry: ScreenGeometry) -> CGRect {
        DisplayLayout.restored(
            frame, originalOrigin: originalOrigins[id] ?? geometry.frame.origin, on: geometry)
    }
    private func restorationFrames() -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        for (id, original) in originalFrames {
            guard let snapshot = snapshots[id] ?? restorationSnapshots[id], snapshot.isTileable,
                settings.appPolicy.manages(snapshot.bundleIdentifier),
                let current = owners[id] ?? restorationOwners[id] ?? originalDisplays[id], isEnabled(current)
            else { continue }
            let originalID = originalDisplays[id].flatMap { states[$0] != nil && isEnabled($0) ? $0 : nil }
            let destination = originalID ?? owners[id] ?? DisplayLayout.owner(of: original, in: displays)
            if let destination, let state = states[destination] {
                result[id] = restored(original, id: id, on: state.display.geometry)
            }
        }
        return result
    }
    /// Where a new trackpad gesture may start; read by the scroll tap on its own thread.
    private func updateScrollTargets() {
        let live = !isPaused && !isRestoring && !isPreview && !appIsActive
        scrollInput.targets = live ? displays.filter { isEnabled($0.id) && isDesktopOn($0.id) && states[$0.id]?.strip.columns.isEmpty == false }.map(\.geometry.frame) : []
    }
    var scrollTargets: [CGRect] { scrollInput.targets }
    /// Each assignment to a published property re-renders observers (Settings, onboarding), so
    /// publish only what changed. Status refreshes run for every drag and scan update.
    private func publish<Value: Equatable>(_ value: Value, to keyPath: ReferenceWritableKeyPath<TapeController, Value>) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
    private func refreshStatus() {
        let live = Set(snapshots.values.map(\.processID))
        appNames = appNames.filter { live.contains($0.key) }
        publish(snapshots.values.filter { window in
            window.isTileable && settings.appPolicy.manages(window.bundleIdentifier) && owners[window.id].map(isEnabled) == true
                && owners[window.id].map(isDesktopOn) == true
        }.sorted { (owners[$0.id] ?? "", $0.frame.minX, $0.frame.minY, $0.id.rawValue.uuidString) < (owners[$1.id] ?? "", $1.frame.minX, $1.frame.minY, $1.id.rawValue.uuidString) }.map {
            TapeWindowChoice(id: $0.id, name: windowName($0), managed: managesWindow($0.id))
        }, to: \.managedWindowChoices)
        refreshTabGroups()
        publish(states.values.filter { isEnabled($0.display.id) }.reduce(0) { $0 + $1.strip.columns.reduce(0) { $0 + $1.windows.count } }, to: \.managedCount)
        publish(activeState?.display.name ?? "No Display", to: \.displayName)
        publish(displays.map { display in
            TapeDisplayChoice(
                id: display.id, name: display.name, enabled: isEnabled(display.id),
                windowCount: states[display.id]?.strip.columns.reduce(0) { $0 + $1.windows.count } ?? 0)
        }, to: \.displayChoices)
        updateScrollTargets()
        onStatusChange?()
    }
    private func refreshTabGroups() {
        let outsideStrip = externalFocus.map { id in !states.values.contains { $0.strip.columns.contains { $0.windows.contains(id) } } } ?? false
        publish(isPaused || outsideStrip ? [] : displays.flatMap { display -> [TapeTabGroup] in
            guard isEnabled(display.id), let state = states[display.id] else { return [] }
            let rects = StripLayout.columnRects(for: state.strip, screen: display.geometry, options: settings.layout)
            return zip(state.strip.columns, rects).compactMap { column, logical in
                let body = column.activeWindow.flatMap { snapshots[$0]?.frame }
                let rect = body.map { CGRect(x: $0.minX, y: $0.minY - StripLayout.tabBarHeight, width: $0.width, height: StripLayout.tabBarHeight) } ?? logical
                guard column.mode == .tabbed, column.windows.count > 1, let id = column.windows.first,
                      rect.minX >= display.geometry.visibleFrame.minX, rect.maxX <= display.geometry.visibleFrame.maxX else { return nil }
                return TapeTabGroup(id: id, frame: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: StripLayout.tabBarHeight),
                                    windows: column.windows.compactMap { id in snapshots[id].map { TapeWindowChoice(id: id, name: windowName($0), managed: true) } }, active: column.activeWindow)
            }
        }, to: \.tabGroups)
    }
    private func windowName(_ window: WindowSnapshot) -> String {
        let app: String
        if let cached = appNames[window.processID] { app = cached } else {
            app = NSRunningApplication(processIdentifier: window.processID)?.localizedName ?? "Window"
            appNames[window.processID] = app
        }
        guard let title = window.title, !title.isEmpty else { return app }
        return app + " · " + title
    }
    private func raiseActiveTabs(_ state: DisplayStripState) {
        let active = state.strip.columns.filter { $0.mode == .tabbed && $0.windows.count > 1 }.compactMap(\.activeWindow)
        guard !active.isEmpty else { return }
        server.settle { [weak self, weak state] in
            guard let self, let state, !self.isPaused, self.states[state.display.id] === state else { return }
            let current = active.filter { id in state.strip.columns.contains(where: { $0.mode == .tabbed && $0.activeWindow == id }) }
            self.server.raise(current, preservingFocus: self.externalFocus == state.strip.focusedWindow ? self.externalFocus : nil)
        }
    }

    private func removeWindow(_ id: WindowID) {
        guard !isPaused, !stopping else { return }
        // Close notifications bypass discovery and can retarget an in-flight animation.
        stopScrolling(flush: true)
        revision += 1
        server.cancelPendingWrites()
        let state = owners[id].flatMap { states[$0] }
        let wasFocused = state?.strip.focusedWindow == id
        state?.strip.remove(id)
        snapshots.removeValue(forKey: id)
        owners.removeValue(forKey: id)
        originalFrames.removeValue(forKey: id)
        originalDisplays.removeValue(forKey: id)
        originalOrigins.removeValue(forKey: id)
        selectedWindows.remove(id)
        rememberedColumns.removeValue(forKey: id)
        rememberedNeighbors.removeValue(forKey: id)
        restorationSnapshots.removeValue(forKey: id)
        restorationOwners.removeValue(forKey: id)
        floating.remove(id)
        pendingTransfers.remove(id)
        if interactingWindow == id {
            // The edge-browsing clock belongs to the drag; stop it before forgetting its display.
            if let owner = interactionDisplay { states[owner]?.scrollClock.stop() }
            interactingWindow = nil; interactionDisplay = nil; dragTick = nil
        }
        if externalFocus == id { externalFocus = state?.strip.focusedWindow; focusIntent = FocusIntent() }
        if let state {
            state.strip.scrollOffset = StripLayout.constrainedOffset(for: state.strip, screen: state.display.geometry, options: settings.layout)
            relayout(state, reveal: wasFocused)
        }
        refreshStatus()
        scheduleScan()
    }

    private func interact(with id: WindowID, frame: CGRect, kind: WindowInteraction, finished: Bool) {
        guard !isPaused, !stopping, !isRestoring, managesWindow(id), let owner = owners[id], let state = states[owner],
              let index = state.strip.columns.firstIndex(where: { $0.windows.contains(id) }),
              frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite, frame.minY.isFinite,
              frame.width > 0, frame.height > 0 else { return }
        if interactingWindow != id, snapshots[id].map({ Self.close($0.frame, frame) }) == true { return }
        if interactingWindow != id {
            cancelMotion()
            interactingWindow = id
            interactionDisplay = owner
            revision += 1
            if kind == .move {
                dragTick = ProcessInfo.processInfo.systemUptime
                _ = state.scrollClock.start(screen: state.screen) { [weak self] in self?.scrollDraggedColumn() }
            }
        }
        updateSnapshots([id: frame])
        if kind == .resize {
            let width = ColumnWidth.points(frame.width)
            if settings.sharedWidths { state.strip.setWidths(width) }
            else { state.strip.columns[index].width = width; state.strip.columns[index].automaticWidth = false }
            // An app's minimum size is learned only after our own attempted resize.
            state.strip.columns[index].minimumWidth = min(state.strip.columns[index].minimumWidth, frame.width)
            if state.strip.columns[index].mode == .stacked, state.strip.columns[index].windows.count > 1,
               let requested = state.lastTargets[id], abs(frame.height - requested.height) > 3 {
                let weight = state.strip.columns[index].heightWeights[id] ?? 1
                state.strip.columns[index].heightWeights[id] = min(8, max(0.25, weight * frame.height / max(1, requested.height)))
            }
        }
        if finished {
            state.scrollClock.stop()
            dragTick = nil
            interactingWindow = nil
            interactionDisplay = nil
            if kind == .move {
                if let destination = DisplayLayout.owner(of: frame, in: displays, previous: owner), destination != owner {
                    if canReceiveWindows(destination) {
                        activeDisplay = owner
                        state.strip.select(id)
                        sendWindow(to: destination)
                    } else {
                        consume(Array(snapshots.values), focused: id)
                    }
                    return
                }
                let rects = StripLayout.columnRects(for: state.strip, screen: state.display.geometry, options: settings.layout)
                if let target = rects.indices.min(by: { abs(rects[$0].midX - frame.midX) < abs(rects[$1].midX - frame.midX) }) {
                    state.strip.reorder(id, to: target)
                }
            }
            clearTargets()
            relayout(state, reveal: true)
            reconcileAfterWrites()
        } else if kind == .resize {
            let frames = StripLayout.frames(for: state.strip, screen: state.display.geometry, options: settings.layout).mapValues { StripLayout.parked($0, on: state.display.geometry) }
            state.lastTargets = frames
            let companions = frames.filter { $0.key != id }
            server.apply(frames: companions)
            updateSnapshots(companions)
        }
        refreshStatus()
    }
    private func scrollDraggedColumn() {
        guard let id = interactingWindow, let owner = interactionDisplay, let state = states[owner],
              let pointer = server.pointerPosition else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.05, max(0, now - (dragTick ?? now)))
        dragTick = now
        let content = StripLayout.contentRect(screen: state.display.geometry, options: settings.layout)
        guard pointer.y >= content.minY, pointer.y <= content.maxY else { return }
        let direction: Double = pointer.x <= content.minX + 36 ? -1 : pointer.x >= content.maxX - 36 ? 1 : 0
        let offset = StripLayout.scrolledOffset(for: state.strip, by: direction * 650 * elapsed, screen: state.display.geometry, options: settings.layout)
        guard offset != state.strip.scrollOffset else { return }
        state.strip.scrollOffset = offset
        let frames = StripLayout.frames(for: state.strip, screen: state.display.geometry, options: settings.layout)
            .filter { $0.key != id }.mapValues { StripLayout.parked($0, on: state.display.geometry) }
        server.apply(frames: frames)
        updateSnapshots(frames)
        refreshTabGroups()
    }
    /// Also used by deterministic tests to simulate connecting and removing displays.
    func updateDisplays(_ next: [TapeDisplay], screens: [String: NSScreen] = [:]) {
        cancelMotion()
        pendingTransfers.removeAll()
        revision += 1
        // Mirrored displays share one drawable desktop; never create competing strips.
        var frames: [CGRect] = []
        let next = next.filter { display in
            guard display.geometry.frame.width > 0, display.geometry.frame.height > 0,
                !frames.contains(display.geometry.frame)
            else { return false }
            frames.append(display.geometry.frame)
            return true
        }
        let old = states
        var connected: [String: DisplayStripState] = [:]
        for (index, display) in next.enumerated() {
            var display = display
            display.geometry = DisplayLayout.geometry(for: display, in: next)
            let state =
                old[display.id]
                ?? DisplayStripState(
                    display: display, screen: screens[display.id],
                    animator: index == 0 && old.isEmpty ? firstAnimator : animatorFactory(),
                    scrollClock: index == 0 && old.isEmpty ? firstScrollClock : clockFactory())
            state.display = display
            state.screen = screens[display.id]
            state.lastTargets.removeAll()
            state.lastAttemptFrames.removeAll()
            connected[display.id] = state
        }
        // Carry stranded columns to the nearest remaining enabled display without changing widths.
        let enabled = next.filter { isEnabled($0.id) }
        for state in old.values where connected[state.display.id] == nil {
            for column in state.strip.columns {
                guard let id = column.windows.first, let frame = snapshots[id]?.frame,
                    let owner = DisplayLayout.owner(of: frame, in: enabled), let target = connected[owner]
                else { continue }
                target.strip.columns.append(column)
                for window in column.windows { owners[window] = owner }
                if target.strip.focusedWindow == nil { target.strip.focusedWindow = id }
            }
        }
        states = connected
        displays = next
        if activeDisplay.flatMap({ states[$0] }) == nil {
            activeDisplay = next.first(where: { isEnabled($0.id) })?.id ?? next.first?.id
        }
        refreshStatus()
        if !isPaused { scheduleScan(immediately: true) }
    }
    private func updateScreens() {
        if let displayOverride {
            updateDisplays(displayOverride)
            return
        }
        let screens = NSScreen.screens
        guard let primary = screens.first else {
            updateDisplays([])
            return
        }
        func rect(_ frame: CGRect) -> CGRect {
            CGRect(
                x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        }
        var objects: [String: NSScreen] = [:]
        let descriptors = screens.map { screen -> TapeDisplay in
            let number =
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                ?? CGMainDisplayID()
            let id: String
            if let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() {
                id = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
            } else {
                id = "display-\(number)"
            }
            objects[id] = screen
            return TapeDisplay(
                id: id, name: screen.localizedName,
                geometry: ScreenGeometry(frame: rect(screen.frame), visibleFrame: rect(screen.visibleFrame)))
        }
        updateDisplays(descriptors, screens: objects)
    }
    private static func close(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1 && abs(lhs.minY - rhs.minY) < 1 && abs(lhs.width - rhs.width) < 1
            && abs(lhs.height - rhs.height) < 1
    }
    deinit {
        if let screenToken { NotificationCenter.default.removeObserver(screenToken) }
        activationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
