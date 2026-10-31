import SwiftUI
import Combine
import AppKit

enum NotchState {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case nook, music, calendar, notes, weather, tray, meetings, dictation
    case reminders, timers, clipboard, system, terminal, shortcuts, mirror, prompter, clock, wisp
    var id: String { rawValue }

    /// Pages the dock can show, in the order offered in Settings.
    static let appPages: [NotchTab] = [.wisp, .music, .meetings, .dictation, .calendar, .reminders, .notes, .weather, .clock, .timers,
                                       .clipboard, .shortcuts, .system, .terminal, .prompter, .mirror, .tray]
    /// A fresh install's dock (and Reset). Saved docks drop pages that no
    /// longer exist (Coding and Tsukumo were removed in 2.43, Messages in 3.21).
    static let defaultDock: [NotchTab] = [.music, .weather, .calendar, .clock, .system, .terminal, .tray, .timers, .mirror, .meetings, .dictation]
    /// The dock before it became configurable, kept for installs that never changed it.
    static let legacyDock: [NotchTab] = [.music, .calendar, .notes, .weather, .tray]

    var title: String {
        switch self {
        case .nook: return "Home"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .weather: return "Weather"
        case .tray: return "Tray"
        case .reminders: return "Reminders"
        case .timers: return "Timers"
        case .clipboard: return "Clipboard"
        case .system: return "System"
        case .terminal: return "Terminal"
        case .shortcuts: return "Shortcuts"
        case .mirror: return "Mirror"
        case .prompter: return "Teleprompter"
        case .meetings: return "Meetings"
        case .dictation: return "Dictation"
        case .clock: return "Clock"
        case .wisp: return "Wisp"
        }
    }

    var summary: String {
        switch self {
        case .nook: return "Your widgets."
        case .music: return "Full player with lyrics."
        case .calendar: return "Year progress, month grid and your day."
        case .notes: return "Your local notes."
        case .weather: return "Now, the next hours and the next days."
        case .tray: return "Files waiting between apps."
        case .reminders: return "Add, see and complete reminders."
        case .timers: return "A countdown and focus sessions side by side."
        case .clipboard: return "Search and reuse what you copied."
        case .system: return "Live stats, Overtime with your battery, and what the charger delivers."
        case .clock: return "A world map of your places and their times; click anywhere to add that place."
        case .terminal: return "A shell for quick commands, with your coding day beside it: agents, tokens, limits and GitHub."
        case .shortcuts: return "Search and run all your Shortcuts, with Mac quick actions."
        case .mirror: return "A larger camera preview; the camera runs only while it's open."
        case .prompter: return "Your scripts, read just under the camera; hidden from screen sharing."
        case .meetings: return "Join a call and control its microphone and camera."
        case .dictation: return "Dictate, edit and paste into your app."
        case .wisp: return "An offline assistant: reminders, notes, focus, timers and your day, by typing or talking."
        }
    }
    var systemImage: String {
        switch self {
        case .nook: return "square.grid.2x2.fill"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .notes: return "note.text"
        case .weather: return "cloud.sun.fill"
        case .tray: return "tray.full.fill"
        case .reminders: return "checklist"
        case .timers: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .system: return "gauge.with.needle"
        case .terminal: return "apple.terminal"
        case .shortcuts: return "bolt.fill"
        case .mirror: return "web.camera"
        case .prompter: return "text.alignleft"
        case .meetings: return "video.fill"
        case .dictation: return "mic.fill"
        case .clock: return "globe.americas.fill"
        case .wisp: return "face.smiling"
        }
    }
}

/// The clear look's bubbles on each side of the camera, outermost first. A song is always a
/// pair, its cover left of the camera and its sound right of it, so a timer (or anything
/// else) beside it gets its own bubble outside the cover instead of taking the sound's place.
/// Without a song, the first activity is left of the camera and the second right of it.
struct ClearBubbles: Equatable {
    enum Slot: Hashable {
        case activity(CollapsedActivityKind)
        case sound
    }

    let left: [Slot]
    let right: [Slot]

    init(_ kinds: [CollapsedActivityKind]) {
        if kinds.contains(.music) {
            left = kinds.filter { $0 != .music }.prefix(1).map(Slot.activity) + [.activity(.music)]
            right = [.sound]
        } else {
            left = kinds.prefix(1).map(Slot.activity)
            right = kinds.dropFirst().prefix(1).map(Slot.activity)
        }
    }
}

enum CollapsedActivityKind: Hashable {
    case pasteQueue
    case meeting
    case screenshot
    case timer
    case keepAwake
    case music
    case power
    case system
}

/// Per-screen state machine driving the collapse/expand behaviour of the notch UI.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .collapsed {
        willSet {
            if state == .expanded, newValue != .expanded, displaysCamera(selectedTab) {
                CameraController.shared.endPresentation(owner: presentationID)
            }
        }
        didSet {
            updateAppPresentation()
            if state != .expanded {
                selectedWidget = nil
                if selectedTab == .dictation { DictationModel.shared.stop(); isPageEditing = false }
                if selectedTab == .wisp { WispModel.shared.voice.stopListening(deliver: false); isPageEditing = false }
            }
            if state != oldValue { watchMissionControl(state == .expanded) }
        }
    }
    /// While open, the Nook steps aside for Mission Control: it sits over the Spaces bar.
    private var missionControlWatch: Timer?
    private var missionControlCheckInFlight = false
    @Published var selectedTab: NotchTab = .nook {
        willSet {
            if state == .expanded, newValue != selectedTab, displaysCamera(selectedTab) {
                if displaysCamera(newValue) { CameraController.shared.hidePresentation(owner: presentationID) }
                else { CameraController.shared.endPresentation(owner: presentationID) }
            }
        }
        didSet {
            if oldValue != selectedTab, state == .expanded {
                pageSwitchProtectionUntil = Date().addingTimeInterval(0.6)
            }
            if oldValue == .dictation, selectedTab != .dictation { DictationModel.shared.stop(); isPageEditing = false }
            if selectedTab == .dictation, oldValue != .dictation { DictationModel.shared.captureTarget() }
            updateAppPresentation()
            if selectedTab != .nook { selectedWidget = nil }
        }
    }
    /// Where the current page grew from (a Home tile's centre, as a fraction of the panel).
    @Published var pageAnchor: UnitPoint = .center
    /// The widest closed-notch lane content as drawn (padding included), measured by
    /// the view: lanes fit it instead of a fixed width, so there's no empty notch.
    @Published var measuredActivityLanes: [String: CGFloat] = [:]
    var measuredLaneContent: CGFloat { measuredActivityLanes.values.max() ?? 0 }
    /// The closed activities as last drawn (`CollapsedNotchContent` sets it, animated,
    /// once they change), so the shell, which doesn't observe the services behind them,
    /// moves its lanes with them, and each change knows whether it's an arrival.
    @Published var shownActivities: [CollapsedActivityKind] = []

    /// The motion for the closed row becoming `kinds`: fewer activities than shown is
    /// leaving, anything else arriving.
    func laneAnimation(to kinds: [CollapsedActivityKind]) -> Animation {
        Design.laneAnimation(arriving: kinds.count >= shownActivities.count)
    }

    /// Opens a widget's full page, zooming out from its tile.
    func openPage(for kind: NookWidgetKind, from anchor: UnitPoint) {
        guard let page = kind.page else { return }
        if kind == .pomodoro || kind == .timer { UserDefaults.standard.set(kind == .pomodoro, forKey: "timers.pageFocus") }
        selectedWidget = nil
        pageAnchor = anchor
        withAnimation(Design.spring()) { selectedTab = page }
    }

    /// The Home widget picked with a click; Delete removes it.
    @Published var selectedWidget: NookWidgetKind?
    /// The widget most recently removed with Delete, its profile and position, so Undo can restore it.
    @Published private(set) var recentlyRemoved: (kind: NookWidgetKind, index: Int, profileID: UUID)?
    private var undoExpiry: DispatchWorkItem?
    @Published var isDropTargeted = false
    @Published var isPinned = false
    /// The pointer rests on the closed notch; it grows slightly to show it is
    /// about to open, before the hover delay elapses.
    @Published private(set) var isHoveringCollapsed = false
    /// A text field on an app page has focus; typing must not close the Nook.
    var isPageEditing = false
    var isDeviceDetailsPresented = false

    private let presentationID = UUID()
    var cameraPresentationID: UUID { presentationID }
    private func displaysCamera(_ tab: NotchTab) -> Bool {
        tab == .mirror || (tab == .nook && settings.widgets.contains(.mirror))
    }
    private func updateAppPresentation() {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        AppServices.shared.setAppPresentation(id: presentationID, tab: state == .expanded ? selectedTab : nil)
    }
    func endAppPresentation() {
        if displaysCamera(selectedTab) { CameraController.shared.endPresentation(owner: presentationID) }
        openRequestID = UUID()
        collapseWorkItem?.cancel()
        fileDragOpenWorkItem?.cancel()
        missionControlWatch?.invalidate(); missionControlWatch = nil
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        AppServices.shared.setAppPresentation(id: presentationID, tab: nil)
    }

    let geometry: NotchGeometry
    let settings: NookSettings
    let shelf: ShelfStore
    let nowPlaying: NowPlayingController
    let powerMonitor: PowerSourceMonitor
    let timerService: TimerService
    let bluetoothMonitor: BluetoothMonitor
    let systemActivityMonitor: SystemActivityMonitor
    let teleprompter: TeleprompterService

    private let availableWidth: CGFloat

    static let standardPageWidth: CGFloat = 620
    static let standardPageHeight: CGFloat = 346
    static let dockHeight: CGFloat = 38
    static let dockGap: CGFloat = 10
    static let cameraGap = NotchGeometry.cameraGap

    /// Content determines size; saved manual dimensions never distort the Nook.
    var expandedSize: CGSize {
        Self.fittedSize(widgets: settings.widgets, tab: selectedTab,
                        geometry: geometry, availableWidth: availableWidth,
                        sizes: settings.widgetSizes)
    }

    static func fittedSize(widgets: [NookWidgetKind], tab: NotchTab,
                           geometry: NotchGeometry, availableWidth: CGFloat,
                           sizes: [NookWidgetKind: NookWidgetSize] = [:]) -> CGSize {
        let maximumWidth = max(1, min(Design.nookMaximumWidth, availableWidth - 48))
        let headerMinimum = standardPageWidth
        let items = widgets.nookLayoutItems(sizes: sizes)
        let contentWidth = items.reduce(CGFloat.zero) { $0 + $1.width }
            + CGFloat(max(0, items.count - 1)) * 10 + 40
        let width = min(maximumWidth, tab == .nook ? max(headerMinimum, contentWidth) : standardPageWidth)
        let baseHeight = tab == .nook ? (widgets.isEmpty ? 170 : Design.nookHeight) : standardPageHeight
        // An island sits `topInset` below the top edge; its panel is that much lower.
        return CGSize(width: width, height: baseHeight - (geometry.isHardwareNotch ? 8 - cameraGap : 4) + dockHeight + dockGap
                      + geometry.topInset)
    }

    /// Content always starts below the physical camera; controls live in the dock.
    var expandedHeaderTopInset: CGFloat {
        geometry.isHardwareNotch ? geometry.cameraBottom + Self.cameraGap + 12 : 16
    }

    var expandedPanelSize: CGSize {
        CGSize(width: expandedSize.width,
               height: expandedSize.height - Self.dockHeight - Self.dockGap)
    }

    private var collapseWorkItem: DispatchWorkItem?
    private var pageSwitchProtectionUntil = Date.distantPast
    private var fileDragOpenWorkItem: DispatchWorkItem?
    private var scrollAccumulator: CGFloat = 0
    private(set) var isPointerInside = false
    private var openRequestID = UUID()
    /// The display this Nook sits on (set by `NotchManager`). Hover and scroll
    /// open only from the closed notch on it; without one, any hover counts.
    var screenFrame: NSRect?
    /// Where the pointer is, in screen coordinates; the Debug checks replace it.
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }

    init(geometry: NotchGeometry,
         availableWidth: CGFloat,
         settings: NookSettings,
         shelf: ShelfStore,
         nowPlaying: NowPlayingController,
         powerMonitor: PowerSourceMonitor,
         timerService: TimerService,
         bluetoothMonitor: BluetoothMonitor,
         systemActivityMonitor: SystemActivityMonitor,
         teleprompter: TeleprompterService) {
        self.geometry = geometry
        self.availableWidth = availableWidth
        self.settings = settings
        self.shelf = shelf
        self.nowPlaying = nowPlaying
        self.powerMonitor = powerMonitor
        self.timerService = timerService
        self.bluetoothMonitor = bluetoothMonitor
        self.systemActivityMonitor = systemActivityMonitor
        self.teleprompter = teleprompter
    }

    var collapsedSize: CGSize {
        CGSize(width: geometry.width + collapsedLeftLaneWidth + collapsedRightLaneWidth,
               height: geometry.closedHeight(showingActivities: !collapsedActivityKinds.isEmpty))
    }

    /// The window's clickable area while closed, measured from its top edge: an
    /// island's capsule sits below the top edge, and the strip above it counts.
    var collapsedInteractiveSize: CGSize {
        let size = collapsedSize
        return CGSize(width: size.width, height: size.height + geometry.closedTopPadding(surfaceHeight: size.height))
    }

    /// The clear look's activity bubbles, the agent bubble's size: the closed height.
    var closedBubbleSide: CGFloat { AgentPopoutLayout.bubbleSide(forHeight: geometry.closedHeight(showingActivities: true)) }

    static let minimumLane: CGFloat = 36

    private func collapsedLaneWidth(_ side: String) -> CGFloat {
        let kinds = collapsedActivityKinds
        guard !kinds.isEmpty else { return 0 }
        let maximum = max(0, (availableWidth - geometry.width - 32) / 2)
        if geometry.isClear {
            let layout = ClearBubbles(kinds)
            let count = side == "left" ? layout.left.count : layout.right.count
            return min(maximum, AgentPopoutLayout.laneWidth(bubbles: count, side: closedBubbleSide))
        }
        // Keep Awake with no limit is the cup alone: nothing right of the camera.
        if side == "right", kinds == [.keepAwake], AppServices.shared.keepAwake.expiresAt == nil { return 0 }
        return min(maximum, max(0, measuredActivityLanes[side] ?? Self.minimumLane))
    }

    var collapsedLeftLaneWidth: CGFloat { collapsedLaneWidth("left") }
    var collapsedRightLaneWidth: CGFloat { collapsedLaneWidth("right") }
    var collapsedActivityLaneWidth: CGFloat { max(collapsedLeftLaneWidth, collapsedRightLaneWidth) }
    /// Shift the fitted surface, keeping the physical camera centered on the display.
    var collapsedContentOffset: CGFloat { (collapsedRightLaneWidth - collapsedLeftLaneWidth) / 2 }

    /// Every running timer, soonest first, for the closed notch.
    static var runningTimers: [TimerService] {
        AppServices.shared.allTimers.filter(\.isRunning).sorted { $0.remaining < $1.remaining }
    }

    static var timerLabel: String {
        let timers = runningTimers
        return timers.isEmpty ? AppServices.shared.timerService.remainingText : timers.map(\.remainingText).joined(separator: "  ")
    }

    var collapsedActivityKinds: [CollapsedActivityKind] {
        var kinds: [CollapsedActivityKind] = []
        // Short-lived system/device feedback takes the first lane so a volume
        // or brightness change is never hidden behind persistent media/timer
        // activities. The highest-value persistent activity fills lane two.
        if settings.showPowerLiveActivity && powerMonitor.justChangedRecently { kinds.append(.power) }
        if systemActivityMonitor.justChangedRecently { kinds.append(.system) }
        if settings.showScreenshotLiveActivity && ScreenshotWatcher.shared.recent != nil { kinds.append(.screenshot) }
        if settings.showMeetingLiveActivity, MeetingCountdown.shared.meeting != nil { kinds.append(.meeting) }
        if settings.showPasteQueueLiveActivity && PasteQueueState.shared.remaining > 0 { kinds.append(.pasteQueue) }
        if settings.showTimerLiveActivity && AppServices.shared.allTimers.contains(where: \.isRunning) { kinds.append(.timer) }
        if settings.showMusicLiveActivity && nowPlaying.info.isPlaying { kinds.append(.music) }
        // After the song: Keep Awake is a quiet, long-running state.
        if settings.showKeepAwakeLiveActivity && AppServices.shared.keepAwake.isActive { kinds.append(.keepAwake) }
        // The closed Nook remains a glanceable lane, not a compressed toolbar.
        return Array(kinds.prefix(2))
    }

    /// The closed notch, lanes included, in screen coordinates.
    var closedNotchFrame: NSRect? {
        guard let screenFrame else { return nil }
        return geometry.closedFrame(size: collapsedSize, offset: collapsedContentOffset, on: screenFrame)
    }

    /// The pointer is on the closed notch, with room for its hover peek.
    func isPointerOnClosedNotch() -> Bool {
        guard let screenFrame else { return true }
        // The agent pop-out sits just beside the notch; pointing at it isn't pointing at the notch.
        if AgentPopout.shared.frame?.contains(pointerLocation()) == true { return false }
        return geometry.closedHoverFrame(size: collapsedSize, offset: collapsedContentOffset, on: screenFrame)
            .contains(pointerLocation())
    }

    func hoverChanged(_ hovering: Bool) {
        collapseWorkItem?.cancel()
        openRequestID = UUID()
        isPointerInside = hovering
        // SwiftUI can report hover where the open panel was while it closes, and
        // keeps it until the pointer moves; only the closed notch itself counts.
        let onNotch = state != .collapsed || isPointerOnClosedNotch()
        let peeks = hovering && state == .collapsed && onNotch
        if isHoveringCollapsed != peeks { isHoveringCollapsed = peeks }

        if hovering {
            guard state == .collapsed else { return }
            guard onNotch else { awaitPointerOnNotch(); return }
            if settings.expandOnHover {
                if Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" { AppServices.shared.prewarmDockPages() }
                scheduleExpand(after: settings.hoverDelay)
            }
        } else {
            guard state == .expanded else { return }
            scheduleCollapseCheck(after: 0.32)
        }
    }

    /// Mission Control has no notification, so an open Nook checks a few times a
    /// second (one window-list read each) and closes when it appears.
    private func watchMissionControl(_ watching: Bool) {
        missionControlWatch?.invalidate()
        missionControlWatch = nil
        guard watching, Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .expanded, !self.missionControlCheckInFlight else { return }
                self.missionControlCheckInFlight = true
                let request = self.openRequestID
                let active = await MissionControl.isActive()
                self.missionControlCheckInFlight = false
                guard active, self.state == .expanded, self.openRequestID == request else { return }
                self.collapse()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        missionControlWatch = timer
    }

    private func scheduleExpand(after delay: TimeInterval) {
        // Mission Control's Spaces bar sits under the notch; reaching for it shouldn't open the Nook.
        let request = openRequestID
        let missionControl = Task { await MissionControl.isActive() }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                let active = await missionControl.value
                guard let self, !active, self.openRequestID == request,
                      self.isPointerInside, self.state == .collapsed else { return }
                // The pointer slid off the notch without SwiftUI ending the hover.
                guard self.isPointerOnClosedNotch() else { self.hoverChanged(true); return }
                self.expand()
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// A hover that began off the closed notch waits, while it lasts, for the
    /// pointer to reach the notch, then peeks and opens as usual.
    private func awaitPointerOnNotch() {
        let request = openRequestID
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.openRequestID == request,
                  self.isPointerInside, self.state == .collapsed else { return }
            if self.isPointerOnClosedNotch() { self.hoverChanged(true) } else { self.awaitPointerOnNotch() }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// SwiftUI popovers live in separate windows. Keep the Nook open while the
    /// pointer is interacting with one, then resume normal hover collapse.
    private func scheduleCollapseCheck(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInside, !self.isPinned else { return }
            let remainingProtection = self.pageSwitchProtectionUntil.timeIntervalSinceNow
            if remainingProtection > 0 {
                self.scheduleCollapseCheck(after: remainingProtection)
                return
            }
            // Leaving the window is expected while rearranging a card or
            // dragging a file. Keep polling until that interaction ends.
            guard !self.settings.isInteractiveReorderActive,
                  NSApp.modalWindow == nil, !self.isDropTargeted, !self.isPageEditing, !self.isDeviceDetailsPresented else {
                self.scheduleCollapseCheck(after: 0.14)
                return
            }
            // Heuristic: AppKit has no public "is a popover open?" query, so
            // match the private window class name (e.g. _NSPopoverWindow).
            // Brittle across OS releases, but a miss only affects collapse
            // timing, never correctness.
            let hasOpenPopover = NSApp.windows.contains { window in
                window.isVisible &&
                    (String(describing: type(of: window)).localizedCaseInsensitiveContains("popover") || String(describing: type(of: window)).localizedCaseInsensitiveContains("preview"))
            }
            if hasOpenPopover {
                self.scheduleCollapseCheck(after: 0.35)
            } else {
                self.collapse()
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func expand(to tab: NotchTab? = nil) {
        openRequestID = UUID()
        collapseWorkItem?.cancel()
        if tab == .dictation || (tab == nil && selectedTab == .dictation) { DictationModel.shared.captureTarget() }
        if let tab { selectedTab = tab }
        isHoveringCollapsed = false
        guard state != .expanded else { return }
        if Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" { AppServices.shared.prewarmDockPages() }
        Haptics.tap()
        // Opening is a direct pointer response. The spring is damped enough to
        // settle in one pass, so the surface never keeps rolling out after
        // its content is already interactive.
        withAnimation(Design.openAnimation) {
            state = .expanded
        }
    }

    /// Removes the selected Home widget. Its size stays in the profile, so Undo puts it back as it was.
    func removeSelectedWidget() {
        guard let kind = selectedWidget, let index = settings.widgets.firstIndex(of: kind) else { return }
        withAnimation(Design.spring()) { settings.setEnabled(false, for: kind) }
        selectedWidget = nil
        recentlyRemoved = (kind, index, settings.activeProfileID)
        undoExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in self?.recentlyRemoved = nil }
        undoExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: expiry)
    }

    /// Restores the widget into the profile it came from, showing that profile if another is active.
    func undoRemoveWidget() {
        defer { recentlyRemoved = nil; undoExpiry?.cancel() }
        guard let removed = recentlyRemoved,
              settings.profiles.contains(where: { $0.id == removed.profileID }) else { return }
        withAnimation(Design.spring()) {
            settings.activeProfileID = removed.profileID
            guard !settings.widgets.contains(removed.kind) else { return }
            var widgets = settings.widgets
            widgets.insert(removed.kind, at: min(removed.index, widgets.count))
            settings.widgets = widgets
        }
    }

    func togglePin() {
        isPinned.toggle()
        if !isPinned && !isPointerInside { scheduleCollapseCheck(after: 0.32) }
    }

    func collapse() {
        openRequestID = UUID()
        isPinned = false
        collapseWorkItem?.cancel()
        isHoveringCollapsed = false
        withAnimation(Design.closeAnimation) {
            state = .collapsed
        }
    }

    func toggle() {
        state == .collapsed ? expand() : collapse()
    }

    /// A Finder drag reached the small landing zone around the notch. The
    /// Tray opens only if the drag pauses there, so files dragged along the
    /// top of the screen do not pop the Nook open on the way past.
    func fileDragEntered() {
        collapseWorkItem?.cancel()
        fileDragOpenWorkItem?.cancel()
        isDropTargeted = true
        if state == .expanded {
            if selectedTab != .tray { expand(to: .tray) }
            return
        }
        guard settings.openTrayOnFileDrag else { return }
        Haptics.tap()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isDropTargeted else { return }
            self.expand(to: .tray)
        }
        fileDragOpenWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func fileDragExited() {
        fileDragOpenWorkItem?.cancel()
        fileDragOpenWorkItem = nil
        isDropTargeted = false
        hoverChanged(false)
    }

    func acceptFileDrop(_ urls: [URL]) {
        collapseWorkItem?.cancel()
        fileDragOpenWorkItem?.cancel()
        isDropTargeted = false
        Haptics.drop()
        expand(to: .tray)
        urls.forEach(shelf.add(url:))
    }

    // MARK: - Scroll / swipe gestures

    /// Two-finger scroll applies only to the closed trigger. Once expanded,
    /// scroll gestures belong exclusively to widgets and the Nook scroller.
    func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard settings.scrollGesturesEnabled, state == .collapsed, isPointerOnClosedNotch() else { return }

        // Trackpads report "scroll down" as positive deltaY (natural scrolling).
        if abs(deltaY) > abs(deltaX) {
            scrollAccumulator += deltaY
            if scrollAccumulator > 34 {
                scrollAccumulator = 0
                let request = openRequestID
                Task { @MainActor [weak self] in
                    let active = await MissionControl.isActive()
                    guard let self, !active, self.openRequestID == request,
                          self.state == .collapsed else { return }
                    self.expand()
                }
            }
        }
    }

    func scrollEnded() {
        scrollAccumulator = 0
    }

}
