import SwiftUI
import Combine
import AppKit

enum NotchState {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable {
    case nook
    case tray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nook: return "Nook"
        case .tray: return "Tray"
        }
    }

    var systemImage: String {
        switch self {
        case .nook: return "rectangle.3.group.fill"
        case .tray: return "tray.full.fill"
        }
    }
}

enum CollapsedActivityKind: Hashable {
    case timer
    case music
    case bluetooth
    case power
    case system
}

/// Per-screen state machine driving the collapse/expand behaviour of the notch UI.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .collapsed
    @Published var selectedTab: NotchTab = .nook
    @Published var isDropTargeted = false

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

    /// Fits short profiles around their widgets while treating the user's
    /// width setting as a ceiling for larger, horizontally scrollable layouts.
    var expandedSize: CGSize {
        let maximumWidth = max(420, availableWidth - 48)
        let showsTeleprompter = settings.showTeleprompterBar && selectedTab == .nook
        if settings.widgets.isEmpty {
            return CGSize(
                width: min(maximumWidth, max(440, geometry.width + 220)),
                height: showsTeleprompter ? 216 : 170
            )
        }
        let userMaximum = min(max(CGFloat(settings.expandedWidth), 480), maximumWidth)
        let layoutItems = settings.widgets.nookLayoutItems()
        let widgetWidths = layoutItems.reduce(CGFloat.zero) {
            $0 + $1.width
        }
        let spacing = CGFloat(max(0, layoutItems.count - 1)) * 10
        let fittedWidth = max(480, widgetWidths + spacing + 40)
        let width = settings.fitWidthToProfile
            ? min(userMaximum, fittedWidth)
            : userMaximum
        let baseHeight = min(max(CGFloat(settings.expandedHeight), 210), 420)
        let height = baseHeight + (showsTeleprompter ? 46 : 0)
        return CGSize(width: width, height: height)
    }

    private var collapseWorkItem: DispatchWorkItem?
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

        let dynamicLabel: String?
        if activities.contains(.bluetooth) {
            dynamicLabel = bluetoothMonitor.activityLabel
        } else if activities.contains(.system) {
            dynamicLabel = systemActivityMonitor.currentActivity?.label
        } else if activities.contains(.power) {
            dynamicLabel = powerMonitor.activityLabel
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

    var collapsedActivityKinds: [CollapsedActivityKind] {
        var kinds: [CollapsedActivityKind] = []
        // Short-lived system/device feedback takes the first lane so a volume
        // or brightness change is never hidden behind persistent media/timer
        // activities. The highest-value persistent activity fills lane two.
        if systemActivityMonitor.justChangedRecently { kinds.append(.system) }
        if settings.showPowerLiveActivity && powerMonitor.justChangedRecently { kinds.append(.power) }
        if settings.showBluetoothLiveActivity && bluetoothMonitor.justChangedRecently { kinds.append(.bluetooth) }
        if settings.showTimerLiveActivity && timerService.isRunning { kinds.append(.timer) }
        if settings.showMusicLiveActivity && nowPlaying.info.isPlaying { kinds.append(.music) }
        // The closed Nook remains a glanceable lane, not a compressed toolbar.
        return Array(kinds.prefix(2))
    }

    func hoverChanged(_ hovering: Bool) {
        collapseWorkItem?.cancel()
        isPointerInside = hovering

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

    private func scheduleExpand(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.expand() }
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
                  !self.isDropTargeted else {
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
        // Opening is a direct pointer response. A short ease-out reaches the
        // final geometry in one pass; a spring made the large surface appear
        // to keep rolling out after its content was already interactive.
        withAnimation(.easeOut(duration: 0.18)) {
            state = .expanded
        }
    }

    func collapse() {
        collapseWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            state = .collapsed
        }
    }

    func toggle() {
        state == .collapsed ? expand() : collapse()
    }

    /// A Finder drag reached the invisible landing zone below the notch.
    /// Open Tray before the pointer reaches macOS's top-edge window gesture.
    func fileDragEntered() {
        collapseWorkItem?.cancel()
        isDropTargeted = true
        if state == .collapsed || selectedTab != .tray {
            expand(to: .tray)
        }
    }

    func fileDragExited() {
        isDropTargeted = false
        hoverChanged(false)
    }

    func acceptFileDrop(_ urls: [URL]) {
        collapseWorkItem?.cancel()
        isDropTargeted = false
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
                expand()
            }
        }
    }

    func scrollEnded() {
        scrollAccumulator = 0
    }

}
