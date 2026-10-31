import SwiftUI
import UniformTypeIdentifiers

/// Root view hosted in the notch window. Renders the black notch-shaped
/// surface and morphs between the collapsed strip and the expanded nook.
struct NotchContainerView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var settings: NookSettings
    // Expanded pages observe their own services; the shell observes geometry only.
    let nowPlaying: NowPlayingController
    let powerMonitor: PowerSourceMonitor
    let timerService: TimerService
    let systemActivityMonitor: SystemActivityMonitor
    @State private var decorativeMotionReady = false
    /// The open surface's height and width, which follow `isExpanded` one after the
    /// other (`Design.openDownAnimation`, `openOutAnimation`): down, then out; in the
    /// clear look from the camera's outline, once its bubbles have tucked under it.
    @State private var isTall: Bool
    @State private var isWide: Bool
    /// The clear look's bubbles: out beside the camera, or tucked under it from the moment
    /// the Nook starts opening until it has closed back into the camera's outline.
    @State private var bubblesOut: Bool
    /// The bubbles are drawn: not while the Nook is open, once they've tucked away.
    @State private var bubblesShown: Bool
    /// Tells a late tuck or return from an earlier open or close to do nothing.
    @State private var stagingGeneration = 0
    @ObservedObject private var theme = ThemeStore.shared

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
        self.nowPlaying = viewModel.nowPlaying
        self.powerMonitor = viewModel.powerMonitor
        self.timerService = viewModel.timerService
        self.systemActivityMonitor = viewModel.systemActivityMonitor
        _isTall = State(initialValue: viewModel.state == .expanded)
        _isWide = State(initialValue: viewModel.state == .expanded)
        _bubblesOut = State(initialValue: viewModel.state != .expanded)
        _bubblesShown = State(initialValue: viewModel.state != .expanded)
    }

    private var isExpanded: Bool { viewModel.state == .expanded }
    /// The open Nook is a see-through pane (Glass themes); the closed notch stays solid.
    private var isGlass: Bool { isExpanded && theme.family.glassTint != nil }

    /// A file dragged near the closed notch: the notch swells into a target.
    private var isFileDragTarget: Bool { !isExpanded && viewModel.isDropTargeted }

    /// Open, the panel's size as far as it has dropped from the closed surface and widened.
    private var surfaceSize: CGSize {
        guard isStaged else { return closedSurfaceSize }
        let open = viewModel.expandedPanelSize, closed = drawsOnCamera ? cameraSurfaceSize : viewModel.collapsedSize
        return CGSize(width: isWide ? open.width : closed.width, height: isTall ? open.height : closed.height)
    }

    /// Open, or still dropping, widening, drawing in or rising.
    private var isStaged: Bool { isExpanded || isTall || isWide }

    /// The clear look draws only on the camera's outline: its bubbles sit beside it on
    /// nothing, so the panel grows from the camera (not the lanes) and closes back into
    /// it, and no fill ever shows where the bubbles are. A file swelling the notch is
    /// the exception, as the bubbles tuck away for it.
    private var drawsOnCamera: Bool {
#if DEBUG
        guard Self.stagesOpen, Self.clearOnCamera else { return false }
#endif
        return viewModel.geometry.isClear && !isFileDragTarget
    }

    /// The camera's outline at the closed height (the island grows for lanes).
    private var cameraSurfaceSize: CGSize { CGSize(width: viewModel.geometry.width, height: viewModel.collapsedSize.height) }

    /// Closed, the clear look's lanes beside the camera only catch the pointer: the
    /// surface (and its hover peek, which grows down) stays on the camera.
    private var catchesBesideCamera: Bool {
        drawsOnCamera && !isStaged && !viewModel.collapsedActivityKinds.isEmpty
    }

    /// The visible surface's width: the layout's, unless it's on the camera beside lanes.
    private var drawnWidth: CGFloat { catchesBesideCamera ? cameraSurfaceSize.width : surfaceSize.width }

    /// Cancels the closed surface's shift toward a longer lane, which the layout (and so
    /// the pointer's area) keeps, so the clear look's surface stays on the camera.
    private var drawnOffset: CGFloat { drawsOnCamera && !isExpanded ? -viewModel.collapsedContentOffset : 0 }

#if DEBUG
    /// Captures draw the open and close as they were before the staging, to compare.
    static var stagesOpen = true
    /// …and the clear look as it was before it stayed on the camera (the surface grew from
    /// the lanes, solid behind the bubbles, which faded where they sat).
    static var clearOnCamera = true
#endif

    /// The clear look's side bubbles tuck under the camera themselves (`bubblesOut`) before
    /// the panel widens, and come back out once it has closed into the camera, so they're
    /// already gone when they stop being drawn and not yet out when drawn again.
    private static var bubblesTransition: AnyTransition {
#if DEBUG
        guard stagesOpen else { return .opacity }
        guard clearOnCamera else {
            return .asymmetric(
                insertion: .opacity.animation(Design.timed(.easeOut(duration: 0.2).delay(Design.closeSettleDelay))),
                removal: .opacity.combined(with: .scale(scale: 0.8)).animation(Design.timed(.easeOut(duration: 0.1))))
        }
#endif
        return .identity
    }

    private var closedSurfaceSize: CGSize {
        let collapsed = viewModel.collapsedSize
        // Stays inside the drag-activation margin (+60 × +28) around the notch.
        if isFileDragTarget {
            return theme.reduceMotion ? collapsed
                : CGSize(width: collapsed.width + 56, height: collapsed.height + 22)
        }
        // A small hover peek below and beside the camera housing signals
        // that the notch is interactive before it opens.
        guard viewModel.isHoveringCollapsed, !theme.reduceMotion else { return collapsed }
        return CGSize(width: collapsed.width + 12, height: collapsed.height + 4)
    }

    /// The closed island floats below the top edge, centred on its cutout; a closed
    /// notch and every open Nook start at the edge (the panel inside hangs below the camera).
    private var surfaceTopPadding: CGFloat {
        isExpanded ? 0 : viewModel.geometry.closedTopPadding(surfaceHeight: surfaceSize.height)
    }

    /// The outline for this state, from the geometry: one path for every Mac.
    private var outline: NotchGeometry.Outline {
        viewModel.geometry.outline(expanded: isExpanded, surfaceHeight: surfaceSize.height)
    }
    private var surfaceShape: NotchShape { NotchShape(outline) }
    private var surfaceEdge: NotchEdgeShape { NotchEdgeShape(outline) }

    /// The clear look's closed surface only catches the pointer (or shows the notchless
    /// hint) and turns solid as the pointer reaches for it or a file arrives.
    /// Closing, it stays solid down to the camera's outline, until the bubbles come back.
    private var surfaceOpacity: Double {
        if isExpanded || isFileDragTarget || (viewModel.isHoveringCollapsed && !theme.reduceMotion) { return 1 }
        if viewModel.geometry.isClear && !bubblesOut { return 1 }
        return viewModel.geometry.closedSurfaceOpacity(showingActivities: !viewModel.collapsedActivityKinds.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: NotchViewModel.dockGap) {
                notchSurface
                if isExpanded {
                    NotchHeaderView(viewModel: viewModel)
                        .frame(width: viewModel.expandedSize.width - 16,
                               height: NotchViewModel.dockHeight)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onHover { viewModel.hoverChanged($0) }
            .offset(x: isExpanded ? 0 : viewModel.collapsedContentOffset)
            .overlay(alignment: .top) { ZStack(alignment: .top) {
                // The clear look's bubbles sit outside the (invisible) outline, placed on
                // the camera itself rather than on the surface, which shifts and resizes
                // as lanes come and go: each bubble moves only by its own transition. The
                // surface underneath takes their clicks and hovers.
                if bubblesShown && viewModel.geometry.isClear {
                    CollapsedNotchContent(viewModel: viewModel, bubblesTucked: !bubblesOut)
                        .padding(.top, viewModel.geometry.closedTopPadding(surfaceHeight: viewModel.closedBubbleSide))
                        .allowsHitTesting(false)
                        .transition(Self.bubblesTransition)
                }
            }
            .animation(isExpanded ? Design.openAnimation : Design.closeAnimation, value: isExpanded) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isExpanded) { open in
            stagingGeneration += 1
            let generation = stagingGeneration
#if DEBUG
            if !Self.stagesOpen {
                bubblesOut = !open; bubblesShown = !open
                withAnimation(open ? Design.openAnimation : Design.closeAnimation) { isTall = open; isWide = open }
                return
            }
            if !Self.clearOnCamera {
                bubblesOut = !open; bubblesShown = !open
                if open {
                    withAnimation(Design.openDownAnimation) { isTall = true }
                    withAnimation(Design.openOutAnimation()) { isWide = true }
                } else {
                    withAnimation(Design.closeInAnimation) { isWide = false }
                    withAnimation(Design.closeUpAnimation) { isTall = false }
                }
                return
            }
#endif
            if open {
                // The bubbles tuck under the camera while the panel drops from the camera's
                // outline (beside them, never over them), and it widens once they've gone.
                let bubbles = viewModel.geometry.isClear && !viewModel.collapsedActivityKinds.isEmpty
                // A turn later, outside the open's transaction; the bubbles animate it themselves.
                DispatchQueue.main.async {
                    guard stagingGeneration == generation else { return }
                    bubblesOut = false
                }
                withAnimation(Design.openDownAnimation) { isTall = true }
                withAnimation(Design.openOutAnimation(afterBubbles: bubbles)) { isWide = true }
                let tucked = (theme.reduceMotion ? 0.16 : Design.bubbleTuckDuration) * Design.demoTimeScale
                DispatchQueue.main.asyncAfter(deadline: .now() + tucked) {
                    guard stagingGeneration == generation else { return }
                    bubblesShown = false
                }
            } else {
                // The reverse: in, then up into the camera's outline, then the bubbles come out.
                bubblesShown = true
                withAnimation(Design.closeInAnimation) { isWide = false }
                withAnimation(Design.closeUpAnimation) { isTall = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + Design.closeSettle) {
                    guard stagingGeneration == generation else { return }
                    withAnimation(Design.laneAnimation(arriving: true)) { bubblesOut = true }
                }
            }
        }
        .task(id: isExpanded) {
            decorativeMotionReady = false
            guard isExpanded else { return }
            // The shell opens first. Timelines/shaders do not compete with its spring.
            do { try await Task.sleep(nanoseconds: 420_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { decorativeMotionReady = true }
        }
        .environment(\.colorScheme, theme.notch.colorScheme)
        .environment(\.mirrorPresentationOwnerID, viewModel.cameraPresentationID)
        .tint(theme.notch.accent)
        .foregroundStyle(theme.nookForeground)
    }

    private var notchSurface: some View {
        ZStack(alignment: .top) {
            if catchesBesideCamera {
                // Invisible, not clear: the pointer is caught over the bubbles too.
                surfaceShape.fill(Color.black.opacity(NotchGeometry.clearHitOpacity))
            }
            NookBackdrop(shape: surfaceShape, allowsGlass: isExpanded)
                .overlay {
                    if !isGlass {
                        // A plain gradient, clipped below with everything else. Filling the
                        // animating shape with it made Core Graphics redraw the gradient
                        // on the main thread every frame of opening and closing (~36 ms each).
                        LinearGradient(colors: [theme.notch.surfaceSecondary, .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .overlay {
                    if theme.family == .custom, isExpanded, theme.customStyle == .twoTone || theme.customStyle == .image {
                        CustomBackdropLayer().transition(.opacity)
                    }
                }
                .overlay {
                    if let motif = theme.activeMotif {
                        ThemeMotifView(motif: motif, accent: theme.notch.accent, ink: theme.nookForeground,
                                       animated: isExpanded && decorativeMotionReady && !theme.reduceMotion)
                            .opacity(isExpanded ? 1 : 0)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if isExpanded && viewModel.selectedTab == .music {
                        MusicArtworkAmbience(nowPlaying: nowPlaying, lyricsService: viewModel.teleprompter,
                                             animated: decorativeMotionReady && !theme.reduceMotion)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    let edgeWidth: CGFloat = isExpanded ? 1 : 2
                    surfaceEdge
                        .stroke(
                            Color.white.opacity(
                                isGlass
                                    ? (theme.notch.colorScheme == .dark ? 0.24 : 0.6)
                                    : isExpanded ? 0.10 : 0.07
                            ),
                            style: StrokeStyle(
                                lineWidth: edgeWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .padding(edgeWidth / 2)
                }
                .clipShape(surfaceShape)
                .opacity(surfaceOpacity)
                .padding(.top, isExpanded ? viewModel.geometry.expandedPanelTopPadding : 0)
                .overlay(alignment: .bottom) {
                    if isFileDragTarget {
                        FileDropTargetLabel(accent: theme.notch.accent)
                            .padding(.bottom, 5)
                            .transition(.nookDepth(blur: 3, scale: 0.9, anchor: .bottom))
                    }
                }
                .overlay(alignment: .top) {
                    if isExpanded {
                        // Content settles in from the camera as the surface
                        // opens, instead of fading in place over the morph.
                        expandedContent
                            .transition(.nookDepth(blur: 0))
                    } else if !viewModel.geometry.isClear {
                        CollapsedNotchContent(viewModel: viewModel)
                            .transition(.opacity)
                    }
                }
                .clipShape(surfaceShape)
                .frame(width: drawnWidth)
                .offset(x: drawnOffset)
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
        .overlay {
            // Accent rim and glow while a file hovers over the closed notch.
            NotchEdgeShape(viewModel.geometry.outline(expanded: false, surfaceHeight: surfaceSize.height))
                .stroke(theme.notch.accent.opacity(isFileDragTarget ? 0.9 : 0), lineWidth: 1.5)
                .shadow(color: theme.notch.accent.opacity(isFileDragTarget ? 0.55 : 0), radius: 12)
                .allowsHitTesting(false)
        }
        // A shadow would show through a Glass pane and darken it.
        .shadow(color: theme.notch.shadow.opacity(isExpanded && !isGlass ? 1 : 0), radius: 22, y: 8)
        .padding(.top, surfaceTopPadding)
        .background {
            if !isExpanded {
                ScrollWheelCatcher(
                    onScroll: { deltaX, deltaY in
                        viewModel.handleScroll(deltaX: deltaX, deltaY: deltaY)
                    },
                    onEnded: { viewModel.scrollEnded() }
                )
            }
        }
        .onTapGesture {
            if !isExpanded { viewModel.expand() }
        }
        .onDrop(of: [UTType.fileURL], delegate: NotchDropDelegate(viewModel: viewModel))
        .animation(isExpanded ? Design.openAnimation : Design.closeAnimation, value: isExpanded)
        .animation(Design.hoverAnimation, value: viewModel.isHoveringCollapsed)
        .animation(Design.dropAnimation, value: isFileDragTarget)
        .environment(\.colorScheme, theme.notch.colorScheme)
        .tint(theme.notch.accent)
        .foregroundStyle(theme.nookForeground)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        // Keep only physical camera clearance above the content. Navigation
        // lives below the panel, so no extra header padding is needed.
        let topInset = viewModel.expandedHeaderTopInset
        let horizontalInset: CGFloat = 20
        let bottomInset: CGFloat = 12

        return VStack(spacing: 8) {
            Group {
                switch viewModel.selectedTab {
                case .nook:
                    NookDashboardView(viewModel: viewModel)
                        .transition(.nookDepth(blur: 0, scale: 0.98, anchor: .center))
                case .music:
                    MusicPage {
                        MediaPlayerView(nowPlaying: nowPlaying, largeArtwork: true,
                                        lyricsService: viewModel.teleprompter)
                    }
                case .calendar:
                    CalendarAppView(service: AppServices.shared.calendar)
                case .notes:
                    NotesAppView(service: AppServices.shared.notes)
                case .weather:
                    WeatherAppView(service: AppServices.shared.weather)
                case .tray:
                    TrayPageView(tray: viewModel.shelf, isDropTargeted: $viewModel.isDropTargeted)
                        .transition(.nookDepth(blur: 0, scale: 0.98, anchor: .center))
                case .reminders:
                    RemindersAppView(service: AppServices.shared.calendar,
                                     onEditingChanged: { viewModel.isPageEditing = $0 })
                case .timers:
                    TimersAppView(service: timerService)
                case .clipboard:
                    ClipboardAppView(monitor: AppServices.shared.clipboard,
                                     onEditingChanged: { viewModel.isPageEditing = $0 })
                case .system:
                    SystemAppView(stats: AppServices.shared.systemStats, power: powerMonitor,
                                  bluetooth: viewModel.bluetoothMonitor, keepAwake: AppServices.shared.keepAwake,
                                  onDetailsChanged: { viewModel.isDeviceDetailsPresented = $0 })
                case .terminal:
                    TerminalPage(shell: AppServices.shared.quickShell,
                                 onEditingChanged: { viewModel.isPageEditing = $0 })
                case .shortcuts:
                    ShortcutsAppView(service: AppServices.shared.shortcuts,
                                     onEditingChanged: { viewModel.isPageEditing = $0 })
                case .prompter:
                    PrompterPage(prompter: .shared, onEditingChanged: { viewModel.isPageEditing = $0 })
                case .mirror:
                    MirrorAppView()
                case .clock:
                    ClockPage(onEditingChanged: { viewModel.isPageEditing = $0 })
                case .meetings:
                    MeetingControlsView(model: .shared)
                case .dictation:
                    DictationView(model: .shared, onEditingChanged: { viewModel.isPageEditing = $0 })
                case .wisp:
                    WispPage(model: .shared, onEditingChanged: { viewModel.isPageEditing = $0 })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A page opened from a Home tile grows out of that tile; going back fades.
            .id(viewModel.selectedTab)
            .transition(viewModel.selectedTab == .nook || viewModel.pageAnchor == .center ? .opacity
                        : .asymmetric(insertion: .scale(scale: 0.4, anchor: viewModel.pageAnchor).combined(with: .opacity),
                                      removal: .opacity))
        }
        .frame(
            width: max(0, viewModel.expandedSize.width - 2 * horizontalInset),
            height: max(0, viewModel.expandedPanelSize.height - topInset - bottomInset)
        )
        .padding(.top, topInset)
        .colorScheme(theme.notch.colorScheme)
    }
}

/// Expands the shelf when a drag hovers over the collapsed notch.
private struct NotchDropDelegate: DropDelegate {
    let viewModel: NotchViewModel

    /// With drag-to-open off, the closed notch ignores file drags entirely.
    func validateDrop(info: DropInfo) -> Bool {
        viewModel.state == .expanded || viewModel.settings.openTrayOnFileDrag
    }

    func dropEntered(info: DropInfo) {
        viewModel.fileDragEntered()
    }

    func dropExited(info: DropInfo) {
        viewModel.fileDragExited()
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.isDropTargeted = false
        Haptics.drop()
        viewModel.expand(to: .tray)
        return viewModel.shelf.handleDrop(providers: info.itemProviders(for: [.fileURL]))
    }
}

/// "Drop to Tray" under the camera while a file hovers over the closed notch;
/// the arrow bobs so the notch reads as something that will catch the file.
private struct FileDropTargetLabel: View {
    let accent: Color
    @ObservedObject private var theme = ThemeStore.shared
    @State private var bob = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
                .offset(y: bob && !theme.reduceMotion ? 1.5 : -1.5)
            Text("Drop to Tray")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(accent)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bob = true }
        }
        .accessibilityLabel("Drop files to add them to the Tray")
    }
}

/// The widest closed-notch lane's content, reported up to size both lanes.
private struct LaneWidthKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

/// One closed activity that slides out from under the camera and back under it, driven
/// by its own state rather than a transition: a view being removed keeps the place it
/// had, so a transition left the bubble fading where it sat while its lane shrank (and
/// leaves the solid lane's content where the black edge sweeps over it). The old
/// activity stays drawn until it has tucked away; a new one then comes out. Tucked, it
/// carries `tucked` points of padding on `edge` (positive pushes it in from the outer
/// edge, negative pulls it past the camera-side edge), which `CameraEdgeMask` hides.
/// Arriving and leaving use `Design.laneAnimation`; Reduce Motion fades in place.
private struct TuckedActivity<Key: Hashable, Content: View>: View {
    let key: Key?
    let edge: Edge.Set
    let tucked: CGFloat
    /// Held under the camera while the Nook opens and is open, whatever the activity:
    /// tucking on `Design.bubbleTuckAnimation` (quicker than leaving), coming back out on
    /// the arrival's curve.
    var held = false
    @ViewBuilder let content: (Key) -> Content
    @ObservedObject private var theme = ThemeStore.shared
    @State private var shown: Key?
    @State private var out = false
    @State private var generation = 0

    var body: some View {
        ZStack {
            if let shown {
                let isOut = out && !held
                content(shown)
                    .padding(edge, isOut || theme.reduceMotion ? 0 : tucked)
                    .opacity(isOut || !theme.reduceMotion ? 1 : 0)
                    .animation(held ? Design.bubbleTuckAnimation : Design.laneAnimation(arriving: true), value: held)
            }
        }
        .onAppear { shown = key; out = key != nil }
        .onChange(of: key) { update(to: $0) }
    }

    private func update(to key: Key?) {
        generation += 1
        let current = generation
        func comeOut() {
            DispatchQueue.main.async {
                guard generation == current else { return }
                withAnimation(Design.laneAnimation(arriving: true)) { out = true }
            }
        }
        if shown == nil || shown == key {
            if shown == nil { withoutAnimation { shown = key; out = false } }
            if key != nil { comeOut() }
            return
        }
        withAnimation(Design.laneAnimation(arriving: false)) { out = false }
        let leaving = (theme.reduceMotion ? 0.16 : Design.laneDuration) * Design.demoTimeScale
        DispatchQueue.main.asyncAfter(deadline: .now() + leaving) {
            guard generation == current else { return }
            withoutAnimation { shown = key }
            if key != nil { comeOut() }
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }
}

/// Hides whatever crosses a lane's camera-side edge: an activity tucking back under the
/// camera disappears there, as under the hardware, on an island's capsule and a notchless
/// pill too. The outer side and above and below are left open.
private struct CameraEdgeMask: ViewModifier {
    let outer: HorizontalEdge

    func body(content: Content) -> some View {
        content.mask {
            Rectangle()
                .padding(outer == .leading ? .leading : .trailing, -400)
                .padding(.vertical, -20)
        }
    }
}

/// Keep Awake's cup, the symbol its widget uses while on.
private struct KeepAwakeCup: View {
    let size: CGFloat
    let tint: Color
    var body: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
    }
}

/// Keep Awake's time left ticks only when its label changes: on each second under an
/// hour, on each minute over it, and not at all once it has run out.
struct KeepAwakeCountdown: TimelineSchedule {
    let end: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator {
            guard let current = next else { return nil }
            let remaining = end.timeIntervalSince(current)
            if remaining <= 0 {
                next = nil
            } else {
                let step: TimeInterval = remaining > 3600 ? 60 : 1
                // The label shows whole steps rounded up, so it changes as `remaining`
                // reaches the step below.
                var boundary = end.addingTimeInterval(-(ceil(remaining / step) - 1) * step)
                if boundary <= current { boundary = boundary.addingTimeInterval(step) }
                next = boundary
            }
            return current
        }
    }

    /// "42:07" under an hour (seconds), "1h 05m" over it (minutes, rounded up).
    static func label(until end: Date, at date: Date) -> String {
        let remaining = max(0, end.timeIntervalSince(date))
        if remaining > 3600 {
            let minutes = Int(ceil(remaining / 60))
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        let seconds = Int(ceil(remaining))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct FittedLane: ViewModifier {
    let outerEdge: Edge.Set
    let side: String

    func body(content: Content) -> some View {
        content.fixedSize()
            .padding(outerEdge, 10)
            .padding(outerEdge == .leading ? .trailing : .leading, 4)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: LaneWidthKey.self, value: [side: proxy.size.height > 0 ? proxy.size.width : 0])
                }
            }
    }
}

/// Live subscriptions stop at the closed lanes, instead of invalidating the opening shell.
private struct CollapsedNotchContent: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var settings: NookSettings
    // Observed here so collapsed-state live activities refresh with the data.
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject var powerMonitor: PowerSourceMonitor
    @ObservedObject var timerService: TimerService
    @ObservedObject var systemActivityMonitor: SystemActivityMonitor
    @ObservedObject private var pasteQueue = PasteQueueState.shared
    @ObservedObject private var meetings = MeetingCountdown.shared
    @ObservedObject private var screenshots = ScreenshotWatcher.shared
    @ObservedObject private var secondTimer = AppServices.shared.extraTimers[0]
    @ObservedObject private var thirdTimer = AppServices.shared.extraTimers[1]
    @ObservedObject private var keepAwake = AppServices.shared.keepAwake

    /// Every running timer, soonest first ("9:49  14:38  24:39").
    private var timerLabel: String { NotchViewModel.timerLabel }
    private var runningTimers: [TimerService] { NotchViewModel.runningTimers }
    @ObservedObject private var theme = ThemeStore.shared
    private var isFileDragTarget: Bool { viewModel.isDropTargeted }
    /// The clear look's bubbles held under the camera while the Nook opens, is open and closes.
    let bubblesTucked: Bool
    init(viewModel: NotchViewModel, bubblesTucked: Bool = false) {
        self.viewModel = viewModel
        self.bubblesTucked = bubblesTucked
        self.settings = viewModel.settings
        self.nowPlaying = viewModel.nowPlaying
        self.powerMonitor = viewModel.powerMonitor
        self.timerService = viewModel.timerService
        self.systemActivityMonitor = viewModel.systemActivityMonitor
    }
    // MARK: - Collapsed

    /// Lanes on the black in the solid look, bubbles in the clear look. The window stays
    /// centered; only the compact surface shifts to fit its sides.
    var body: some View {
        Group {
            if viewModel.geometry.isClear { bubbles } else { lanes }
        }
        // A song pausing or starting (or a timer ending) adds or removes a bubble without
        // a measured lane changing, so the agent bubble is told directly to move with it.
        .onChange(of: viewModel.collapsedActivityKinds) { kinds in
            // The shell's surface and offset follow on the same curve.
            withAnimation(viewModel.laneAnimation(to: kinds)) { viewModel.shownActivities = kinds }
            DispatchQueue.main.async { NotchManager.active?.closedLanesChanged() }
        }
        .onAppear {
            let kinds = viewModel.collapsedActivityKinds
            if viewModel.shownActivities != kinds { viewModel.shownActivities = kinds }
        }
    }

    /// The clear look: each activity its own bubble, the agent bubble's size and spacing,
    /// laid out by `ClearBubbles` (a song keeps its cover left of the camera and its sound
    /// right of it; a timer or anything else sits outside the cover). Each bubble has a fixed
    /// slot one bubble wide (and the gap), so it never rides a lane that resizes; it arrives
    /// and leaves by sliding exactly its slot's width out from and back under its inner edge.
    private var bubbles: some View {
        let layout = ClearBubbles(isFileDragTarget ? [] : viewModel.collapsedActivityKinds)
        let side = viewModel.closedBubbleSide
        let slot = AgentPopoutLayout.laneWidth(bubbles: 1, side: side)
        return HStack(spacing: 0) {
            // Outside the song's cover: a timer or other activity beside the song.
            if layout.left.count > 1 { bubbleSlot(layout.left[0], side: side, width: slot, outer: .leading) }
            bubbleSlot(layout.left.last, side: side, width: slot, outer: .leading)
            Color.clear.frame(width: viewModel.geometry.width)
            bubbleSlot(layout.right.first, side: side, width: slot, outer: .trailing)
        }
        // This sits on the camera's centre: a side with more bubbles shifts the row so the
        // camera stays between them.
        .offset(x: CGFloat(layout.right.count - layout.left.count) * slot / 2)
        .frame(height: side, alignment: .top)
        // `gap` below the top edge, as they sit `gap` from the camera.
        .padding(.top, AgentPopoutLayout.gap)
    }

    private func bubbleSlot(_ content: ClearBubbles.Slot?, side: CGFloat, width: CGFloat, outer: HorizontalEdge) -> some View {
        let alignment: Alignment = outer == .leading ? .leading : .trailing
        return ZStack(alignment: alignment) {
            // Pushed in from the outer edge by its slot's width, it sits just past the
            // camera's edge: under it.
            TuckedActivity(key: content, edge: outer == .leading ? .leading : .trailing, tucked: width,
                           held: bubblesTucked) { content in
                switch content {
                case .activity(let kind): bubble(kind, side: side)
                case .sound: soundBubble(side: side)
                }
            }
        }
        .frame(width: width, height: side, alignment: alignment)
        .modifier(CameraEdgeMask(outer: outer))
    }

    /// A song alone is a pair: its sound beside its cover, in a black squircle shaped like
    /// the cover's, the bars in the cover's own colour (`SoundBubbleBars`).
    private func soundBubble(side: CGFloat) -> some View {
        NotchBubble(side: side, ring: .clear, squircle: true) {
            SoundBubbleBars(playing: nowPlaying.info.isPlaying)
                .scaleEffect(side * 0.55 / 26)
        }
        .accessibilityHidden(true)
    }

    /// Independently fitted lanes keep activities close to the physical camera.
    private var lanes: some View {
        let activities = isFileDragTarget ? [] : viewModel.collapsedActivityKinds

        // Each side fits its own content; the surface offset keeps the camera centered.
        return HStack(spacing: 0) {
            // Against the camera; pulled past its edge by the lane's width, it rides the
            // black edge in and out.
            // Keyed by the activity alone, so one that stays (a timer when the song beside it
            // stops) changes layout in place instead of tucking away and back.
            let paired = activities.count > 1
            TuckedActivity(key: paired ? stackedLeftActivity(in: activities) : activities.first,
                           edge: .trailing, tucked: -laneSlide("left")) { kind in
                Group { if paired { pairedActivity(kind) } else { leftActivity(kind) } }
                    // Its paired and single layouts swap at once while the lane re-fits on
                    // the curve: no crossfade of the two over the moving edge.
                    .transition(.identity)
                    .modifier(FittedLane(outerEdge: .leading, side: "left"))
            }
            .frame(width: viewModel.collapsedLeftLaneWidth, alignment: .trailing)
            .modifier(CameraEdgeMask(outer: .leading))

            Color.clear.frame(width: viewModel.geometry.width)

            TuckedActivity(key: paired ? stackedRightActivity(in: activities) : activities.first,
                           edge: .leading, tucked: -laneSlide("right")) { kind in
                Group { if paired { pairedActivity(kind) } else { rightActivity(kind) } }
                    // Its paired and single layouts swap at once while the lane re-fits on
                    // the curve: no crossfade of the two over the moving edge.
                    .transition(.identity)
                    .modifier(FittedLane(outerEdge: .trailing, side: "right"))
            }
            .frame(width: viewModel.collapsedRightLaneWidth, alignment: .leading)
            .modifier(CameraEdgeMask(outer: .trailing))
        }
        .frame(width: viewModel.collapsedSize.width, height: viewModel.collapsedSize.height)
        .animation(viewModel.laneAnimation(to: activities), value: activities)
        .onPreferenceChange(LaneWidthKey.self) { width in
            // Empty lanes measure nothing; keeping the last width lets the next activity
            // arrive from the camera at once, on the arrival's curve, instead of popping
            // wide a frame later. A lane re-fitting its content moves on the same curve.
            var fitted = viewModel.measuredActivityLanes
            for (side, value) in width where value > 0 { fitted[side] = ceil(value) }
            guard viewModel.measuredActivityLanes != fitted else { return }
            withAnimation(Design.laneAnimation(arriving: true)) { viewModel.measuredActivityLanes = fitted }
        }
    }

    /// How far a solid lane's content travels to tuck under the camera: its lane's width,
    /// so it rides the black edge drawing in (or out) beside it.
    private func laneSlide(_ side: String) -> CGFloat {
        viewModel.measuredActivityLanes[side] ?? NotchViewModel.minimumLane
    }

    /// One activity as a bubble: the song's artwork with its progress, a timer's
    /// countdown in minutes, otherwise the activity's own symbol or picture.
    @ViewBuilder
    private func bubble(_ activity: CollapsedActivityKind, side: CGFloat) -> some View {
        let accent = theme.notch.accent
        let glyph = side * 0.4
        switch activity {
        case .music:
            let info = nowPlaying.info
            // A squircle, like the album cover it holds, filled by it: no outline, so it
            // sits with the agent bubble's black dot (the Music page shows the progress).
            NotchBubble(side: side, ring: .clear, squircle: true) {
                if let artwork = info.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: side - 4, height: side - 4)
                        .clipShape(RoundedRectangle(cornerRadius: NotchBubble<EmptyView>.squircleRadius(side - 4), style: .continuous))
                } else {
                    Image(systemName: "music.note").font(.system(size: glyph, weight: .semibold)).foregroundStyle(accent)
                }
            }
            .accessibilityLabel(info.title.isEmpty ? "Music playing" : "Playing \(info.title)")
        case .timer:
            let timer = runningTimers.first ?? timerService
            // The countdown stays as a thin arc in the timer's colour, with no track.
            NotchBubble(side: side, ring: timer.tint, progress: timer.total > 0 ? timer.remaining / timer.total : nil,
                        ringWidth: 1.5, track: false) {
                Text("\(Int((timer.remaining / 60).rounded(.up)))")
                    .font(.system(size: side * 0.36, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(timer.tint)
            }
            .accessibilityLabel("Timer, \(timerLabel) left")
        case .keepAwake:
            // The cup; with a limit, a thin arc of the time left, like a timer's.
            if let end = keepAwake.expiresAt, let total = keepAwake.duration, total > 0 {
                TimelineView(KeepAwakeCountdown(end: end)) { context in
                    NotchBubble(side: side, ring: accent, progress: max(0, end.timeIntervalSince(context.date)) / total,
                                ringWidth: 1.5, track: false) {
                        KeepAwakeCup(size: glyph, tint: accent)
                    }
                    .accessibilityLabel("Keep Awake, \(KeepAwakeCountdown.label(until: end, at: context.date)) left")
                }
            } else {
                NotchBubble(side: side, ring: .clear) { KeepAwakeCup(size: glyph, tint: accent) }
                    .accessibilityLabel("Keep Awake on")
            }
        case .screenshot:
            NotchBubble(side: side, ring: .clear) {
                if let image = screenshots.recentImage {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: side - 7, height: side - 7).clipShape(Circle())
                } else {
                    Image(systemName: "camera.viewfinder").font(.system(size: glyph, weight: .semibold)).foregroundStyle(accent)
                }
            }
            .accessibilityLabel("New screenshot, in Tray")
        case .meeting:
            NotchBubble(side: side, ring: .clear) {
                Image(systemName: "video.fill").font(.system(size: glyph, weight: .semibold)).foregroundStyle(accent)
            }
            .accessibilityLabel(meetings.meeting.map { "\($0.title), \(MeetingCountdown.label(for: $0, at: Date()))" } ?? "Meeting")
        case .pasteQueue:
            // A count only: clip contents never show in the closed Nook.
            NotchBubble(side: side, ring: .clear) {
                Text("\(pasteQueue.remaining)")
                    .font(.system(size: side * 0.38, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(accent)
            }
            .accessibilityLabel("\(pasteQueue.remaining) clips left to paste")
        case .power:
            NotchBubble(side: side, ring: .clear) {
                PowerActivityGaugeView(monitor: powerMonitor).scaleEffect(0.75)
            }
        case .system:
            if let current = systemActivityMonitor.currentActivity {
                NotchBubble(side: side, ring: .clear) {
                    NotchActivityGlyphView(systemImage: current.systemImage, tint: systemActivityColor(current))
                }
            }
        }
    }

    private func stackedLeftActivity(
        in activities: [CollapsedActivityKind]
    ) -> CollapsedActivityKind? {
        if activities.contains(.timer) {
            return .timer
        }
        // Music is the strongest right-side treatment (artwork + waveform).
        // Put any companion on the left so both activities remain visible.
        if activities.contains(.music) {
            return activities.first { $0 != .music } ?? .music
        }
        return activities.first
    }

    private func stackedRightActivity(
        in activities: [CollapsedActivityKind]
    ) -> CollapsedActivityKind? {
        if activities.contains(.music) {
            return .music
        }
        let left = stackedLeftActivity(in: activities)
        return activities.first { $0 != left }
    }

    @ViewBuilder
    private func pairedActivity(_ activity: CollapsedActivityKind) -> some View {
        switch activity {
        case .power:
            HStack(spacing: 5) {
                PowerActivityGaugeView(monitor: powerMonitor)
                PowerActivityLevelView(monitor: powerMonitor)
            }
        default:
            HStack(spacing: 5) {
                leftActivity(activity)
                rightActivity(activity)
            }
        }
    }

    @ViewBuilder
    private func leftActivity(_ activity: CollapsedActivityKind) -> some View {
        switch activity {
        case .screenshot:
            if let image = screenshots.recentImage {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 30, height: 20).clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("New screenshot")
            } else {
                Image(systemName: "camera.viewfinder").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.notch.accent)
            }
        case .meeting:
            Image(systemName: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.notch.accent)
        case .pasteQueue:
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.notch.accent)
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(runningTimers.first?.tint ?? .orange)
        case .keepAwake:
            KeepAwakeCup(size: 11, tint: theme.notch.accent)
                .accessibilityLabel(keepAwake.expiresAt == nil ? "Keep Awake on" : "Keep Awake")
        case .music:
            MusicActivityArtworkView(nowPlaying: viewModel.nowPlaying)
        case .power:
            PowerActivityGaugeView(monitor: viewModel.powerMonitor)
        case .system:
            if let activity = systemActivityMonitor.currentActivity {
                NotchActivityGlyphView(
                    systemImage: activity.systemImage,
                    tint: systemActivityColor(activity)
                )
            }
        }
    }

    @ViewBuilder
    private func rightActivity(_ activity: CollapsedActivityKind) -> some View {
        switch activity {
        case .screenshot:
            Text("In Tray").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(theme.notch.accent)
        case .meeting:
            if let meeting = meetings.meeting {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(MeetingCountdown.label(for: meeting, at: context.date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(theme.notch.accent)
                }
                .accessibilityLabel("\(meeting.title), \(MeetingCountdown.label(for: meeting, at: Date()))")
            }
        case .pasteQueue:
            // A count only: clip contents never show in the closed Nook.
            Text("\(pasteQueue.remaining)")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(theme.notch.accent)
                .accessibilityLabel("\(pasteQueue.remaining) clips left to paste")
        case .timer:
            // Each time in its timer's colour, so they're told apart at a glance.
            HStack(spacing: 6) {
                if runningTimers.isEmpty {
                    Text(timerLabel).foregroundStyle(.orange)
                } else {
                    ForEach(runningTimers, id: \.slot) { timer in
                        Text(timer.remainingText).foregroundStyle(timer.tint)
                            .lineLimit(1).fixedSize()
                    }
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        case .keepAwake:
            // The time left, once a second, or once a minute while over an hour; with no
            // limit, nothing (the cup alone).
            if let end = keepAwake.expiresAt {
                TimelineView(KeepAwakeCountdown(end: end)) { context in
                    Text(KeepAwakeCountdown.label(until: end, at: context.date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(theme.notch.accent)
                        .lineLimit(1).fixedSize()
                        .accessibilityLabel("\(KeepAwakeCountdown.label(until: end, at: context.date)) left")
                }
            }
        case .music:
            AudioSpectrumView(isPlaying: nowPlaying.info.isPlaying)
        case .power:
            PowerActivityLevelView(monitor: powerMonitor)
        case .system:
            if let activity = systemActivityMonitor.currentActivity {
                SystemActivityValueView(
                    activity: activity,
                    tint: systemActivityColor(activity)
                )
            }
        }
    }

    private func systemActivityColor(_ activity: SystemLiveActivity) -> Color {
        switch activity.kind {
        case .microphone:
            return activity.label == "Muted" ? .red : .green
        case .focus:
            return .purple
        }
    }

}

/// The sound bubble's bars in the playing cover's strongest colour (`ArtworkWashStore.tint`),
/// or the theme's accents for a cover without one. Its own view, so a new cover redraws only it.
private struct SoundBubbleBars: View {
    let playing: Bool
    @ObservedObject private var wash = ArtworkWashStore.shared

    var body: some View {
        AudioSpectrumView(isPlaying: playing, tint: wash.tint)
    }
}
