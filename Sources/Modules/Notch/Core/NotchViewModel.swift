import SwiftUI
import Combine
import AppKit
import OSLog

enum NotchState {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case nook, music, calendar, notes, weather, tray, meetings, dictation
    case reminders, timers, clipboard, system, terminal, shortcuts, mirror, prompter, clock, wisp
    var id: String { rawValue }

    /// Pages the dock can show, in the order offered in Settings. Dictation and Clipboard are
    /// no longer pages of their own (`mergedInto`): their raw values stay so saved docks,
    /// shortcuts and App Intents still resolve.
    static let appPages: [NotchTab] = [.wisp, .music, .prompter, .meetings, .calendar, .reminders, .notes, .weather, .clock, .timers,
                                       .shortcuts, .system, .terminal, .mirror, .tray]
    /// A fresh install's dock (and Reset). Saved docks drop pages that no
    /// longer exist (Coding and Tsukumo were removed in 2.43, Messages in 3.21).
    static let defaultDock: [NotchTab] = [.music, .weather, .calendar, .clock, .system, .terminal, .tray, .mirror, .wisp,
                                          .prompter, .meetings]

    /// The page a retired page now lives in: Dictation is a mode of Studio, and the
    /// clipboard's history a place in Folio.
    var mergedInto: NotchTab? {
        switch self {
        case .dictation: return .prompter
        case .clipboard: return .tray
        default: return nil
        }
    }

    /// The dock's groups, as the Dock card shows them. Pages in a group sit side by side
    /// when added (`NookSettings.setDockApp`); a saved dock keeps its own order.
    static let groups: [(title: String, pages: [NotchTab])] = [
        ("Listen", [.music]),
        ("Talk", [.prompter, .meetings]),
        ("Plan", [.calendar, .reminders, .clock, .weather]),
        ("Focus", [.notes, .timers]),
        ("Work", [.terminal, .shortcuts, .system]),
        ("Files", [.tray]),
        ("Extras", [.mirror, .wisp]),
    ]

    /// The group a dock page belongs to.
    var group: (title: String, pages: [NotchTab])? {
        Self.groups.first { $0.pages.contains(self) }
    }
    /// The dock before it became configurable, kept for installs that never changed it.
    static let legacyDock: [NotchTab] = [.music, .calendar, .notes, .weather, .tray]

    var title: String {
        switch self {
        case .nook: return "Home"
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .weather: return "Weather"
        case .tray: return "Folio"
        case .reminders: return "Reminders"
        case .timers: return "Timers"
        case .clipboard: return "Clipboard"
        case .system: return "System"
        case .terminal: return "Terminal"
        case .shortcuts: return "Shortcuts"
        case .mirror: return "Mirror"
        case .prompter: return "Studio"
        case .meetings: return "Meetings"
        case .dictation: return "Dictation"
        case .clock: return "Clock"
        // Named for the on-device agent picked in Settings → Tsukumo → Agent.
        case .wisp: return WispCharacter.current.title
        }
    }

    var summary: String {
        switch self {
        case .nook: return "Your widgets."
        case .music: return "Full player with lyrics."
        case .calendar: return "Year progress, month grid and your day."
        case .notes: return "Your local notes."
        case .weather: return "Now, the next hours and the next days."
        case .tray: return "The Tray and your baskets, searchable down to the words in pictures and PDFs."
        case .reminders: return "Add, see and complete reminders."
        case .timers: return "As many countdowns as you need, each its own colour, with Do Not Disturb when you want it."
        case .clipboard: return "Search and reuse what you copied."
        case .system: return "Live stats, Overtime with your battery, and what the charger delivers."
        case .clock: return "A world map of your places and their times; click anywhere to add that place."
        case .terminal: return "A shell for quick commands, with your coding day beside it: agents, tokens, limits and GitHub."
        case .shortcuts: return "Search and run all your Shortcuts, with Mac quick actions."
        case .mirror: return "A larger camera preview; the camera runs only while it's open."
        case .prompter: return "Scripts read in your voices, a teleprompter, and dictation."
        case .meetings: return "Join a call and control its microphone and camera."
        case .dictation: return "Dictate, edit and paste into your app."
        case .wisp: return "Your on-device agent: reminders, notes, focus, timers and your day, or Claude and Codex through it."
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
        case .mirror: return "camera"
        case .prompter: return "waveform.and.mic"
        case .meetings: return "video.fill"
        case .dictation: return "mic.fill"
        case .clock: return "globe.americas.fill"
        case .wisp: return "face.smiling"
        }
    }
}

/// The bubbles on each side of the camera, outermost first. A song is always a
/// pair, its cover left of the camera and its sound right of it, so a timer (or anything
/// else) beside it gets its own bubble outside the cover instead of taking the sound's place.
/// Without a song, the first activity is left of the camera and the second right of it.
/// Timers with nothing else showing take both sides once there's more than one bubble of them.
struct ClearBubbles: Equatable {
    enum Slot: Hashable {
        case activity(CollapsedActivityKind)
        case sound
    }

    let left: [Slot]
    let right: [Slot]

    /// `timers` is how many timer bubbles there are to place.
    init(_ kinds: [CollapsedActivityKind], timers: Int = 1) {
        if kinds.contains(.music) {
            left = kinds.filter { $0 != .music }.prefix(1).map(Slot.activity) + [.activity(.music)]
            right = [.sound]
        } else if kinds == [.timer], timers > 1 {
            left = [.activity(.timer)]
            right = [.activity(.timer)]
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
    case spaces
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
                isPageEditing = false
                if isDictating { DictationModel.shared.stop() }
                Self.pendingFolioPlace = nil
                if selectedTab == .wisp { WispModel.shared.voice.stopListening(deliver: false) }
            }
            if state != oldValue { watchMissionControl(state == .expanded) }
            if state == .expanded { acknowledgeFinishedTimers() }
            // Shuffle changes the theme once the Nook has closed, so it's never seen changing.
            if oldValue == .expanded, state != .expanded, ThemeShuffle.isOn {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.state != .expanded else { return }
                    ThemeShuffle.next()
                }
            }
        }
    }
    /// While open, the Nook steps aside for Mission Control: it sits over the Spaces bar.
    private var missionControlWatch: Timer?
    private var missionControlCheckInFlight = false
    private var dockObserver: AnyCancellable?
    private var timerObservers: [AnyCancellable] = []
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
            // A dock click doesn't take focus from a field, so a torn-down page can't clear this itself.
            if oldValue != selectedTab { isPageEditing = false }
            let dictating = (oldValue == .prompter) != (selectedTab == .prompter) && StudioModel.shared.section == .dictate
            if oldValue == .prompter, dictating { DictationModel.shared.stop() }
            if oldValue == .wisp, selectedTab != .wisp { WispModel.shared.voice.stopListening(deliver: false) }
            if oldValue == .tray, selectedTab != .tray { Self.pendingFolioPlace = nil }
            if selectedTab == .prompter, dictating { DictationModel.shared.captureTarget() }
            updateAppPresentation()
            if selectedTab != .nook { selectedWidget = nil }
        }
    }
    /// Where the current page grew from (a Home tile's centre, as a fraction of the panel).
    @Published var pageAnchor: UnitPoint = .center
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
        if kind == .clipboard { Self.pendingFolioPlace = .clipboard }
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
        Self.fittedSize(widgets: settings.widgets.filter { $0 != .spaces || !AppServices.shared.spaces.isUnavailable }, tab: selectedTab,
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
        // Stats holds its whole wall and the name line.
        let stats = tab == .music && MusicStatsCaption.shared.line != nil ? MusicStatsCaptionBar.panelGrowth : 0
        return CGSize(width: width, height: baseHeight + stats - (geometry.isHardwareNotch ? 8 - cameraGap : 4) + dockHeight + dockGap
                      + geometry.topInset)
    }

    /// Content always starts below the physical camera; controls live in the dock.
    var expandedHeaderTopInset: CGFloat {
        geometry.isHardwareNotch ? geometry.cameraBottom + Self.cameraGap + 12 : 16
    }

    /// What takes clicks while open: the whole panel and dock.
    var expandedInteractiveSize: CGSize { expandedSize }

    var expandedPanelSize: CGSize {
        CGSize(width: expandedSize.width,
               height: expandedSize.height - Self.dockHeight - Self.dockGap)
    }

    private var collapseWorkItem: DispatchWorkItem?
    private var pageSwitchProtectionUntil = Date.distantPast
    private var fileDragOpenWorkItem: DispatchWorkItem?
    private var scrollAccumulator: CGFloat = 0
    private var songSwipe = SongSwipe()
    private static let swipeLog = Logger(subsystem: "dev.opensource.MacSpaces", category: "song-swipe")
    static let songNudgeDistance: CGFloat = 5
    /// How far the closed song's cover sits from its place during a swipe's nudge.
    @Published private(set) var songNudge: CGFloat = 0
    private(set) var isPointerInside = false
    private var openRequestID = UUID()
    /// The display this Nook sits on (set by `NotchManager`). Hover and scroll
    /// open only from the closed notch on it; without one, any hover counts.
    var screenFrame: NSRect?
    /// That display's Spaces identifier (`SpacesMonitor.identifier(of:)`, set with `screenFrame`).
    var displayIdentifier: String?
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
        // Removing the page you're on returns to Home, open or closed. Tray stays reachable,
        // because dropping a file on the notch always opens it.
        dockObserver = settings.$dockApps.sink { [weak self] pages in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectedTab != .nook, self.selectedTab != .tray, !pages.contains(self.selectedTab) else { return }
                withAnimation(Design.spring()) { self.selectedTab = .nook }
            }
        }
        // Any timer starting, ending or being hidden from the notch (its eye) moves the closed
        // row, whether or not the closed bubbles are on screen to notice. Next turn, so this
        // never reaches for the shared services while they're being made.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timerObservers = AppServices.shared.allTimers.map { timer in
                timer.$showsInNotch.map { _ in () }
                    .merge(with: timer.$isRunning.map { _ in () }, timer.$finishedAt.map { _ in () })
                    .dropFirst(3)
                    .sink { [weak self] in self?.timerRowChanged() }
            }
        }
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

    /// The activity bubbles, the agent bubble's size: the closed height.
    var closedBubbleSide: CGFloat { AgentPopoutLayout.bubbleSide(forHeight: geometry.closedHeight(showingActivities: true)) }


    private func collapsedLaneWidth(_ side: String) -> CGFloat {
        let kinds = collapsedActivityKinds
        guard !kinds.isEmpty else { return 0 }
        let maximum = max(0, (availableWidth - geometry.width - 32) / 2)
        let timers = Self.timerSides(kinds)
        let layout = ClearBubbles(kinds, timers: timers.left.count + timers.right.count)
        let slots = side == "left" ? layout.left : layout.right
        let items = side == "left" ? timers.left : timers.right
        let width = slots.reduce(CGFloat.zero) { total, slot in
            total + (slot == .activity(.timer) ? Self.timerLaneWidth(side: closedBubbleSide, items: items)
                                               : AgentPopoutLayout.laneWidth(bubbles: 1, side: closedBubbleSide))
        }
        return min(maximum, width)
    }

    var collapsedLeftLaneWidth: CGFloat { collapsedLaneWidth("left") }
    var collapsedRightLaneWidth: CGFloat { collapsedLaneWidth("right") }
    var collapsedActivityLaneWidth: CGFloat { max(collapsedLeftLaneWidth, collapsedRightLaneWidth) }
    /// Shift the fitted surface, keeping the physical camera centered on the display.
    var collapsedContentOffset: CGFloat { (collapsedRightLaneWidth - collapsedLeftLaneWidth) / 2 }

    /// Every running timer that shows beside the notch, soonest first.
    static var runningTimers: [TimerService] {
        AppServices.shared.allTimers.filter { $0.isRunning && $0.showsInNotch }.sorted { $0.remaining < $1.remaining }
    }

    /// The timer bubbles, nearest the camera first: the first finished timer as a
    /// pill with its name, any others as ticks, then running ones, then how many more.
    enum TimerItem: Identifiable, Equatable {
        case pill(TimerService), tick(TimerService), running(TimerService), more(Int)

        var id: String {
            switch self {
            case .pill(let timer): return "pill\(timer.slot)"
            case .tick(let timer): return "tick\(timer.slot)"
            case .running(let timer): return "running\(timer.slot)"
            case .more: return "more"
            }
        }

        static func == (a: TimerItem, b: TimerItem) -> Bool { a.id == b.id }
    }

    static func timerItems(limit: Int = TimerRow.maxBubbles) -> [TimerItem] {
        let done = finishedTimers, running = runningTimers
        let rest = Array(done.dropFirst())
        let row = TimerRow.split(running: running.count, done: rest.count, limit: limit)
        var items: [TimerItem] = done.first.map { [.pill($0)] } ?? []
        items += rest.map(TimerItem.tick) + running.prefix(row.shown).map(TimerItem.running)
        if row.more > 0 { items.append(.more(row.more)) }
        return items
    }

    /// The timer bubbles on each side of the camera, nearest it first. Beside a song they stay
    /// left of its cover, two and a count; with the notch to themselves they alternate, the
    /// soonest left and the next right; beside anything else they keep their one side.
    static func timerSides(_ kinds: [CollapsedActivityKind]) -> (left: [TimerItem], right: [TimerItem]) {
        if kinds.contains(.music) { return (timerItems(limit: TimerRow.besideSong), []) }
        let items = timerItems()
        if kinds == [.timer] { return TimerRow.alternate(items) }
        return kinds.first == .timer ? (items, []) : ([], items)
    }

    /// The room `items` take, each followed by `gap` on its camera side.
    static func timerLaneWidth(side: CGFloat, items: [TimerItem]) -> CGFloat {
        items.reduce(0) { width, item in
            if case .pill(let timer) = item {
                return width + TimerAlertPill.width(name: timer.name, side: side) + AgentPopoutLayout.gap
            }
            return width + AgentPopoutLayout.laneWidth(bubbles: 1, side: side)
        }
    }

    /// Timers came or went without the activity changing: the shell and the agent bubble follow.
    /// On the next run-loop turn: sending from inside the layout pass that noticed the change
    /// makes AppKit run out of passes and throw.
    func timerRowChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
            NotchManager.active?.closedLanesChanged()
        }
    }

    /// Timers showing their done state, in slot order.
    static var finishedTimers: [TimerService] {
        AppServices.shared.allTimers.filter { $0.finishedAt != nil }
    }

    /// The pointer reaching the notch or the Nook opening means it's been seen.
    private func acknowledgeFinishedTimers() {
        AppServices.shared.allTimers.forEach { $0.acknowledge() }
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
        if settings.showTimerLiveActivity && AppServices.shared.allTimers.contains(where: { ($0.isRunning && $0.showsInNotch) || $0.finishedAt != nil }) { kinds.append(.timer) }
        if settings.showMusicLiveActivity && nowPlaying.info.isPlaying { kinds.append(.music) }
        // After the song, so it never displaces it, or a timer or a notice: it shows in a
        // free lane, or for a moment in Keep Awake's.
        if settings.showSpacesLiveActivity, AppServices.shared.spaces.activity(on: displayIdentifier) != nil { kinds.append(.spaces) }
        // After the song: Keep Awake is a quiet, long-running state.
        if settings.showKeepAwakeLiveActivity && AppServices.shared.keepAwake.isActive { kinds.append(.keepAwake) }
        // The closed Nook remains a glanceable lane, not a compressed toolbar.
        return Array(kinds.prefix(2))
    }

    /// The closed notch, bubbles included, in screen coordinates.
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
        if peeks { acknowledgeFinishedTimers() }

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

    /// Studio is showing its dictation.
    var isDictating: Bool { selectedTab == .prompter && StudioModel.shared.section == .dictate }

    /// A retired page opens the page it now lives in, at its place there.
    static func resolve(_ tab: NotchTab) -> NotchTab {
        if tab == .dictation { StudioModel.shared.section = .dictate }
        if tab == .clipboard { pendingFolioPlace = .clipboard }
        return tab.mergedInto ?? tab
    }

    /// Where the next Folio page opens when something asked for a place (the Clipboard
    /// widget, the Clipboard App Intent); cleared once Folio closes. A Folio page already open
    /// hears of each request, since it isn't rebuilt for one.
    static var pendingFolioPlace: FolioPlace? {
        didSet {
            if let place = pendingFolioPlace { NotificationCenter.default.post(name: TrayPageView.placeRequested, object: place) }
        }
    }

    /// Where Folio opens: a place asked for, else Clipboard for a dock whose Clipboard page
    /// became Folio, else All Items.
    var folioStartPlace: FolioPlace {
        Self.pendingFolioPlace ?? (settings.folioOpensOnClipboard ? .clipboard : .all)
    }

    func expand(to requested: NotchTab? = nil) {
        openRequestID = UUID()
        collapseWorkItem?.cancel()
        let tab = requested.map(Self.resolve)
        if (tab ?? selectedTab) == .prompter, StudioModel.shared.section == .dictate { DictationModel.shared.captureTarget() }
        if let tab { selectedTab = tab }
        isHoveringCollapsed = false
        guard state != .expanded else { return }
        if Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" { AppServices.shared.prewarmDockPages() }
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

    /// Typing is over: the Nook closes as usual if the pointer is off it.
    func releasePageEditing() {
        isPageEditing = false
        if state == .expanded, !isPinned, !isPointerInside { scheduleCollapseCheck(after: 0.05) }
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
        expand(to: .tray)
        urls.forEach(shelf.add(url:))
    }

    // MARK: - Scroll / swipe gestures

    /// Two-finger scroll applies only to the closed trigger. Once expanded,
    /// scroll gestures belong exclusively to widgets and the Nook scroller.
    func handleScroll(deltaX: CGFloat, deltaY: CGFloat, momentum: Bool = false) {
        // Open on hover opens the Nook before a swipe can start, so a swipe counts open or
        // closed as long as the pointer is where the closed notch sits.
        guard isPointerOnClosedNotch() else { return }

        // Any loaded song, playing or paused, whatever else the closed notch is showing.
        if settings.swipeToChangeSongs, !nowPlaying.info.title.isEmpty,
           let action = songSwipe.add(deltaX: deltaX,
                                      deltaY: deltaY, momentum: momentum, at: ProcessInfo.processInfo.systemUptime) {
            changeSong(action)
        }

        guard state == .collapsed, settings.scrollGesturesEnabled else { return }

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

    /// The open Music panel: the same swipe, with the pointer on the song rather than the notch
    /// (over the notch, `handleScroll` already counts it).
    func handlePanelSwipe(deltaX: CGFloat, deltaY: CGFloat, momentum: Bool) {
        // On the Shelf look, scrolling sideways over the Music page moves the shelf.
        guard state == .expanded, settings.swipeToChangeSongs, !nowPlaying.info.title.isEmpty,
              !isPointerOnClosedNotch(),
              selectedTab != .music || WidgetOptions.shared.musicLook != .shelf else { return }
        if let action = songSwipe.add(deltaX: deltaX,
                                      deltaY: deltaY, momentum: momentum, at: ProcessInfo.processInfo.systemUptime) {
            changeSong(action)
        }
    }

    func scrollEnded() {
        scrollAccumulator = 0
        let travel = Double(songSwipe.travel)
        let milliseconds = Int(songSwipe.duration * 1000)
        if abs(travel) >= SongSwipe.stroke {
            Self.swipeLog.notice("Stroke \(travel, privacy: .public) points in \(milliseconds, privacy: .public) ms")
        }
        songSwipe.end()
    }

    /// The swipe follows the Mac's scroll direction (`SongSwipe.add`). Like scrolling to open, it does nothing over Mission Control.
    private func changeSong(_ action: SongSwipe.Action) {
        guard action != .returnStroke else {
            Self.swipeLog.notice("Swipe ignored: the hand returning")
            return
        }
        let capability: PlaybackCapability = action == .next ? .next : .previous
        Task { @MainActor [weak self] in
            let active = await MissionControl.isActive()
            guard let self, !active else { return }
            // A command still in flight would drop this one without a word, so wait for it.
            var waited = 0
            while self.nowPlaying.isSending, waited < 30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            guard self.nowPlaying.supports(capability), !self.nowPlaying.isSending else {
                Self.swipeLog.notice("Swipe \(String(describing: action), privacy: .public) dropped: sending \(self.nowPlaying.isSending, privacy: .public), supported \(self.nowPlaying.supports(capability), privacy: .public)")
                return
            }
            Self.swipeLog.notice("Swipe \(String(describing: action), privacy: .public) sent after \(waited * 100, privacy: .public) ms")
            if action == .next { self.nowPlaying.nextTrack() } else { self.nowPlaying.previousTrack() }
            self.nudgeCover(toward: action == .next ? -1 : 1)
        }
    }

    /// The cover steps left for next, right for previous, and back on the lane curve, so the swipe is felt.
    private func nudgeCover(toward direction: CGFloat) {
        guard !ThemeStore.shared.reduceMotion else { return }
        withAnimation(Design.laneAnimation(arriving: true)) { songNudge = direction * Self.songNudgeDistance }
        DispatchQueue.main.asyncAfter(deadline: .now() + Design.laneDuration / 2 * Design.demoTimeScale) { [weak self] in
            guard let self else { return }
            withAnimation(Design.laneAnimation(arriving: false)) { self.songNudge = 0 }
        }
    }

}
