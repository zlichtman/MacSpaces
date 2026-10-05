import SwiftUI
import Combine
import AppKit

enum NotchState {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable, Codable {
    case nook, music, calendar, notes, weather, tray
    case reminders, timers, clipboard, system, terminal, shortcuts, mirror, prompter
    var id: String { rawValue }

    /// Pages the dock can show, in the order offered in Settings.
    static let appPages: [NotchTab] = [.music, .calendar, .reminders, .notes, .weather, .timers,
                                       .clipboard, .shortcuts, .system, .terminal, .prompter, .mirror, .tray]
    /// A fresh install's dock (and Reset). Saved docks drop pages that no
    /// longer exist (Coding and Tsukumo were removed in 2.43).
    static let defaultDock: [NotchTab] = [.music, .weather, .calendar, .system, .terminal, .tray, .timers, .mirror]
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
        case .system: return "System stats, the low-battery agent alert and Keep Awake."
        case .terminal: return "A shell for quick commands, with your coding day beside it: agents, tokens, limits and GitHub."
        case .shortcuts: return "Search and run all your Shortcuts, with Mac quick actions."
        case .mirror: return "A larger camera preview; the camera runs only while it's open."
        case .prompter: return "Your scripts, read just under the camera; hidden from screen sharing."
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
        case .system: return "gauge.with.dots.needle.33percent"
        case .terminal: return "apple.terminal"
        case .shortcuts: return "bolt.fill"
        case .mirror: return "web.camera"
        case .prompter: return "text.alignleft"
        }
    }
}

enum CollapsedActivityKind: Hashable {
    case message
    case pasteQueue
    case meeting
    case agent
    case screenshot
    case timer
    case music
    case power
    case system
}

/// Per-screen state machine driving the collapse/expand behaviour of the notch UI.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .collapsed {
        didSet {
            updateAppPresentation()
            if state != .expanded { selectedWidget = nil }
            if state != oldValue { watchMissionControl(state == .expanded) }
        }
    }
    /// While open, the Nook steps aside for Mission Control: it sits over the Spaces bar.
    private var missionControlWatch: Timer?
    @Published var selectedTab: NotchTab = .nook {
        didSet {
            updateAppPresentation()
            if selectedTab != .nook { selectedWidget = nil }
        }
    }
    /// Where the current page grew from (a Home tile's centre, as a fraction of the panel).
    @Published var pageAnchor: UnitPoint = .center

    /// Opens a widget's full page, zooming out from its tile.
    func openPage(for kind: NookWidgetKind, from anchor: UnitPoint) {
        guard let page = kind.page else { return }
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
    /// The pointer rests on the closed notch; it grows slightly to show it is
    /// about to open, before the hover delay elapses.
    @Published private(set) var isHoveringCollapsed = false
    var isQuickReplyEditing = false
    /// A text field on an app page has focus; typing must not close the Nook.
    var isPageEditing = false
    var isWeatherDetailsPresented = false
    var isDeviceDetailsPresented = false

    private let presentationID = UUID()
    private func updateAppPresentation() {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        AppServices.shared.setAppPresentation(id: presentationID, tab: state == .expanded ? selectedTab : nil)
    }
    func endAppPresentation() {
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

    static let dockHeight: CGFloat = 38
    static let dockGap: CGFloat = 10
    /// Space between the camera housing and the open panel, so the panel
    /// reads as hanging below the notch rather than fused to it.
    static let cameraGap: CGFloat = 6

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
        let headerMinimum: CGFloat = 480
        let tiles = widgets.filter { !$0.isQuickBar }
        let items = tiles.nookLayoutItems(sizes: sizes)
        let contentWidth = items.reduce(CGFloat.zero) { $0 + $1.width }
            + CGFloat(max(0, items.count - 1)) * 10 + 40
        // Both tabs share the profile width; switching to Tray must not expand the Nook.
        let pageWidth: CGFloat = tab == .music ? 572 : 620
        let width = min(maximumWidth, tab == .nook || tab == .tray ? max(headerMinimum, contentWidth) : pageWidth)
        let baseHeight: CGFloat
        switch tab {
        case .music: baseHeight = 336
        case .weather, .calendar, .reminders, .clipboard, .terminal, .shortcuts, .mirror, .prompter: baseHeight = 346
        case .system: baseHeight = 300
        // Timer cards are compact; a taller page only added empty space.
        case .timers: baseHeight = 236
        default: baseHeight = tiles.isEmpty && tab == .nook ? 170 : Design.nookHeight
        }
        return CGSize(width: width, height: baseHeight - (geometry.isHardwareNotch ? 8 - cameraGap : 4) + dockHeight + dockGap + (tab == .nook ? CGFloat(widgets.filter(\.isQuickBar).count) * 46 : 0))
    }

    /// Content always starts below the physical camera; controls live in the dock.
    var expandedHeaderTopInset: CGFloat {
        geometry.isHardwareNotch ? geometry.height + Self.cameraGap + 12 : 16
    }

    var expandedPanelSize: CGSize {
        CGSize(width: expandedSize.width,
               height: expandedSize.height - Self.dockHeight - Self.dockGap)
    }

    private var collapseWorkItem: DispatchWorkItem?
    private var fileDragOpenWorkItem: DispatchWorkItem?
    private var scrollAccumulator: CGFloat = 0
    private var isPointerInside = false

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
        // At rest, match the detected hardware notch exactly. Side space only
        // exists while an actual live activity needs it.
        CGSize(width: geometry.width + 2 * collapsedActivityLaneWidth,
               height: geometry.height)
    }

    var collapsedActivityLaneWidth: CGFloat {
        let activities = collapsedActivityKinds
        guard !activities.isEmpty else { return 0 }

        let baseWidth: CGFloat = geometry.isHardwareNotch ? 58 : 52
        // A complete icon/value pair needs more usable pixels than a split
        // single activity. Expand the side lanes instead of pushing controls
        // underneath the physical camera cutout.
        let hasStackedPair = activities.count > 1
        // MediaRemote resolves asynchronously at launch. When another live
        // activity is already present, reserve the paired width immediately
        // so a playing track does not grow the boundary one frame later.
        let isAwaitingPotentialMusicPair =
            !nowPlaying.hasCompletedInitialRefresh
            && settings.showMusicLiveActivity
            && activities.contains { $0 != .music }

        let standardWidth =
            baseWidth + (hasStackedPair || isAwaitingPotentialMusicPair ? 26 : 0)

        // Power cards never extend beyond the display.
        let maximumLane = max(0, (availableWidth - geometry.width - 32) / 2)
        // Power is a gauge and a percentage: the standard lane, never a wide card.
        if activities.contains(.power) { return min(maximumLane, standardWidth) }

        let dynamicLabel: String?
        if activities.contains(.system) {
            dynamicLabel = systemActivityMonitor.currentActivity?.label
        } else if activities.contains(.power) {
            dynamicLabel = powerMonitor.activityLabel
        } else if activities.contains(.timer), AppServices.shared.allTimers.filter(\.isRunning).count > 1 {
            // Several times side by side, at the activity's 11pt rounded size, 6pt apart.
            let base = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11) } ?? base
            let times = Self.runningTimers.map(\.remainingText)
            let width = ceil(times.reduce(0) { $0 + ($1 as NSString).size(withAttributes: [.font: font]).width })
                + CGFloat(max(0, times.count - 1)) * 6 + 4
            return min(max(0, (availableWidth - geometry.width - 32) / 2), max(standardWidth, width + 40))
        } else if activities.contains(.agent), let label = AgentActivityMonitor.shared.notchLabel {
            // What the agent is doing ("Editing Notch.swift"), at its 10pt size, up to a sensible width.
            let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let width = ceil((label as NSString).size(withAttributes: [.font: font]).width)
            // Sharing the notch with another activity, the icon sits beside the words in one lane.
            let icon: CGFloat = hasStackedPair ? 24 : 0
            return min(max(0, (availableWidth - geometry.width - 32) / 2), max(standardWidth, min(200, width + icon + 30)))
        } else {
            dynamicLabel = nil
        }

        guard let dynamicLabel else {
            return standardWidth
        }

        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let labelWidth = ceil(
            (dynamicLabel as NSString).size(withAttributes: [.font: font]).width
        )
        // Include the icon when paired plus an optical inset that keeps the
        // final characters clear of the Nook's rounded outer corner.
        let activityChrome: CGFloat = hasStackedPair ? 60 : 34
        let dynamicWidth = min(150, labelWidth + activityChrome)
        return max(standardWidth, dynamicWidth)
    }

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
        if settings.widgets.contains(.notifications) && MessageActivityState.shared.count > 0 { kinds.append(.message) }
        if ScreenshotWatcher.shared.recent != nil { kinds.append(.screenshot) }
        // An agent waiting for you outranks everything persistent.
        if let agent = AgentActivityMonitor.shared.headline, agent.state == .needsYou { kinds.append(.agent) }
        if settings.showMeetingLiveActivity, MeetingCountdown.shared.meeting != nil { kinds.append(.meeting) }
        if let agent = AgentActivityMonitor.shared.headline, agent.state != .needsYou { kinds.append(.agent) }
        if PasteQueueState.shared.remaining > 0 { kinds.append(.pasteQueue) }
        if settings.showTimerLiveActivity && AppServices.shared.allTimers.contains(where: \.isRunning) { kinds.append(.timer) }
        if settings.showMusicLiveActivity && nowPlaying.info.isPlaying { kinds.append(.music) }
        // The closed Nook remains a glanceable lane, not a compressed toolbar.
        return Array(kinds.prefix(2))
    }

    func hoverChanged(_ hovering: Bool) {
        collapseWorkItem?.cancel()
        isPointerInside = hovering
        let peeks = hovering && state == .collapsed
        if isHoveringCollapsed != peeks { isHoveringCollapsed = peeks }

        if hovering {
            guard state == .collapsed else { return }
            if settings.expandOnHover {
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
                guard let self, self.state == .expanded, MissionControl.isActive else { return }
                self.collapse()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        missionControlWatch = timer
    }

    private func scheduleExpand(after delay: TimeInterval) {
        // Mission Control's Spaces bar sits under the notch; reaching for it shouldn't open the Nook.
        let work = DispatchWorkItem { [weak self] in
            guard !MissionControl.isActive else { return }
            self?.expand()
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// SwiftUI popovers live in separate windows. Keep the Nook open while the
    /// pointer is interacting with one, then resume normal hover collapse.
    private func scheduleCollapseCheck(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInside else { return }
            // Leaving the window is expected while rearranging a card or
            // dragging a file. Keep polling until that interaction ends.
            guard !self.settings.isInteractiveReorderActive,
                  !self.isDropTargeted, !self.isQuickReplyEditing, !self.isPageEditing, !(self.isWeatherDetailsPresented || self.isDeviceDetailsPresented) else {
                self.scheduleCollapseCheck(after: 0.14)
                return
            }
            // Heuristic: AppKit has no public "is a popover open?" query, so
            // match the private window class name (e.g. _NSPopoverWindow).
            // Brittle across OS releases, but a miss only affects collapse
            // timing, never correctness.
            let hasOpenPopover = NSApp.windows.contains { window in
                window.isVisible &&
                    String(describing: type(of: window)).localizedCaseInsensitiveContains("popover")
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
        collapseWorkItem?.cancel()
        if let tab { selectedTab = tab }
        isHoveringCollapsed = false
        guard state != .expanded else { return }
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

    func collapse() {
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
        guard settings.scrollGesturesEnabled, state == .collapsed else { return }

        // Trackpads report "scroll down" as positive deltaY (natural scrolling).
        if abs(deltaY) > abs(deltaX) {
            scrollAccumulator += deltaY
            if scrollAccumulator > 34 {
                scrollAccumulator = 0
                if !MissionControl.isActive { expand() }
            }
        }
    }

    func scrollEnded() {
        scrollAccumulator = 0
    }

}
