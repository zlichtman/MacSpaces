import SwiftUI
import UniformTypeIdentifiers

/// Root view hosted in the notch window. Renders the black notch-shaped
/// surface and morphs between the collapsed strip and the expanded nook.
struct NotchContainerView: View {
    @ObservedObject var viewModel: NotchViewModel
    /// Stats grows the panel while its name line shows.
    @ObservedObject private var statsCaption = MusicStatsCaption.shared
    @ObservedObject var settings: NookSettings
    // Expanded pages observe their own services; the shell observes geometry only.
    let nowPlaying: NowPlayingController
    let powerMonitor: PowerSourceMonitor
    let timerService: TimerService
    let systemActivityMonitor: SystemActivityMonitor
    @State private var decorativeMotionReady = false
    /// The open surface's height and width, which follow `isExpanded` one after the
    /// other (`Design.openDownAnimation`, `openOutAnimation`): down, then out, from
    /// the camera's outline, once the bubbles have tucked under it.
    @State private var isTall: Bool
    @State private var isWide: Bool
    /// The bubbles: out beside the camera, or tucked under it from the moment
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

    /// The Nook draws only on the camera's outline: its bubbles sit beside it on nothing, so
    /// the panel grows from the camera and closes back into it, and no fill ever shows where
    /// the bubbles are. A file swelling the notch is
    /// the exception, as the bubbles tuck away for it.
    private var drawsOnCamera: Bool {
#if DEBUG
        guard Self.stagesOpen, Self.clearOnCamera else { return false }
#endif
        return !isFileDragTarget
    }

    /// The camera's outline at the closed height (the island grows for bubbles).
    private var cameraSurfaceSize: CGSize { CGSize(width: viewModel.geometry.width, height: viewModel.collapsedSize.height) }

    /// Closed, the room beside the camera only catches the pointer: the surface (and its hover peek, which grows down) stays on the camera.
    private var catchesBesideCamera: Bool {
        drawsOnCamera && !isStaged && !viewModel.collapsedActivityKinds.isEmpty
    }

    /// The visible surface's width: the layout's, unless it's on the camera beside bubbles.
    private var drawnWidth: CGFloat { catchesBesideCamera ? cameraSurfaceSize.width : surfaceSize.width }

    /// Cancels the closed surface's shift toward a longer row, which the layout (and so
    /// the pointer's area) keeps, so the surface stays on the camera.
    private var drawnOffset: CGFloat { drawsOnCamera && !isExpanded ? -viewModel.collapsedContentOffset : 0 }

#if DEBUG
    /// Captures draw the open and close as they were before the staging, to compare.
    static var stagesOpen = true
    /// …and as it was before it stayed on the camera (the surface grew from the bubbles' row,
    /// solid behind the bubbles, which faded where they sat).
    static var clearOnCamera = true
#endif

    /// The side bubbles tuck under the camera themselves (`bubblesOut`) before
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

    /// The closed surface only catches the pointer (or shows the notchless
    /// hint) and turns solid as the pointer reaches for it or a file arrives.
    /// Closing, it stays solid down to the camera's outline, until the bubbles come back.
    private var surfaceOpacity: Double {
        if isExpanded || isFileDragTarget || (viewModel.isHoveringCollapsed && !theme.reduceMotion) { return 1 }
        if !bubblesOut { return 1 }
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
                // The bubbles sit outside the (invisible) outline, placed on
                // the camera itself rather than on the surface, which shifts and resizes
                // as lanes come and go: each bubble moves only by its own transition. The
                // surface underneath takes their clicks and hovers.
                if bubblesShown {
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
                let bubbles = !viewModel.collapsedActivityKinds.isEmpty
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
                    if isExpanded, let look = theme.activeLook, look.fade || look.picture {
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
                        MusicArtworkAmbience(nowPlaying: nowPlaying)
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
            if !isExpanded || viewModel.settings.swipeToChangeSongs {
                ScrollWheelCatcher(
                    onScroll: { event in
                        viewModel.handleScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                               momentum: event.momentumPhase != [])
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
                            .swipesSongs(viewModel)
                    }
                case .calendar:
                    CalendarAppView(service: AppServices.shared.calendar)
                case .notes:
                    NotesAppView(service: AppServices.shared.notes,
                                 onEditingChanged: { viewModel.isPageEditing = $0 })
                case .weather:
                    WeatherAppView(service: AppServices.shared.weather, onEditingChanged: { viewModel.isPageEditing = $0 })
                case .tray, .clipboard:
                    let start = viewModel.folioStartPlace
                    TrayPageView(tray: viewModel.shelf, isDropTargeted: $viewModel.isDropTargeted,
                                 clipboard: start == .clipboard ? .some(AppServices.shared.clipboard) : nil, place: start)
                        .transition(.nookDepth(blur: 0, scale: 0.98, anchor: .center))
                case .reminders:
                    RemindersAppView(service: AppServices.shared.calendar,
                                     onEditingChanged: { viewModel.isPageEditing = $0 })
                case .timers:
                    TimersAppView(onEditingChanged: { viewModel.isPageEditing = $0 })
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
                // Dictation is Studio's Dictate (`NotchViewModel.resolve`).
                case .prompter, .dictation:
                    StudioPage(prompter: .shared, onEditingChanged: { viewModel.isPageEditing = $0 })
                case .mirror:
                    MirrorAppView()
                case .clock:
                    ClockPage(onEditingChanged: { viewModel.isPageEditing = $0 })
                case .meetings:
                    MeetingControlsView(model: .shared)
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

/// One closed activity that slides out from under the camera and back under it, driven
/// by its own state rather than a transition: a view being removed keeps the place it
/// had, so a transition left the bubble fading where it sat. The old activity stays drawn until it has tucked away; a new one then comes out. Tucked, it
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

/// A running timer's bubble: minutes left inside a thin arc in its colour, no track. It spins
/// out as it arrives, and is simply there under Reduce Motion.
private struct TimerBubble: View {
    @ObservedObject var timer: TimerService
    let side: CGFloat
    let squircle: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var settings = NookSettings.shared
    @State private var settled = false

    var body: some View {
        NotchBubble(side: side, ring: timer.bubbleTint, progress: timer.total > 0 ? timer.remaining / timer.total : nil,
                    ringWidth: 1.5, squircle: squircle, track: false) {
            Text("\(Int((timer.remaining / 60).rounded(.up)))")
                .font(.system(size: side * 0.36, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(timer.bubbleTint)
        }
        .rotationEffect(.degrees(settled || theme.reduceMotion ? 0 : -180))
        .scaleEffect(settled || theme.reduceMotion ? 1 : 0.4)
        .onAppear {
            guard !theme.reduceMotion else { return }
            withAnimation(Design.laneAnimation(arriving: true)) { settled = true }
        }
        .accessibilityLabel("\(timer.name), \(timer.remainingText) left")
    }
}

/// A finished timer beside the camera: a tick and its name in its colour, pulsing with the sound.
/// Under Reduce Motion it's simply there.
struct TimerAlertPill: View {
    @ObservedObject var timer: TimerService
    let side: CGFloat
    let squircle: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var settings = NookSettings.shared
    @State private var settled = false

    private static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)

    /// Known before it's drawn, so its lane and the row around it never wait on a measurement.
    static func width(name: String, side: CGFloat) -> CGFloat {
        let text = (TimerDone.laneLabel(name) as NSString).size(withAttributes: [.font: font]).width
        return ceil(text) + side * 0.36 + 4 + 2 * (side * 0.34)
    }

    var body: some View {
        let radius = squircle ? NotchBubble<EmptyView>.squircleRadius(side) : side / 2
        HStack(spacing: 4) {
            TimerDoneTick(size: side * 0.36, tint: timer.bubbleTint)
            Text(TimerDone.laneLabel(timer.name))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(timer.bubbleTint)
                .lineLimit(1)
        }
        .frame(width: Self.width(name: timer.name, side: side), height: side)
        .background(Color.black, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .background { TimerAlertRings(finishedAt: timer.finishedAt, tint: timer.bubbleTint, cornerRadius: radius) }
        .scaleEffect(settled || theme.reduceMotion ? 1 : 0.5)
        .onAppear {
            guard !theme.reduceMotion else { return }
            withAnimation(Design.laneAnimation(arriving: true)) { settled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timer.name) finished")
    }
}

/// The alert's pulses, out from its edge, then nothing: it stops drawing once they're over.
struct TimerAlertRings: View {
    let finishedAt: Date?
    let tint: Color
    let cornerRadius: CGFloat
    @ObservedObject private var theme = ThemeStore.shared
    @State private var isOver = false

    var body: some View {
        if let finishedAt, !isOver, !theme.reduceMotion {
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { context in
                if let progress = TimerDone.pulseProgress(elapsed: context.date.timeIntervalSince(finishedAt)) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tint, lineWidth: 2)
                        .scaleEffect(1 + 0.45 * progress)
                        .opacity(0.9 * (1 - progress))
                }
            }
            .allowsHitTesting(false)
            .task {
                let left = TimerDone.pulseDuration - Date().timeIntervalSince(finishedAt)
                if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                isOver = true
            }
        }
    }
}

/// A finished timer's tick: it settles in on the lane curve, and is simply there under Reduce Motion.
private struct TimerDoneTick: View {
    let size: CGFloat
    let tint: Color
    @ObservedObject private var theme = ThemeStore.shared
    @State private var settled = false

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(tint)
            .scaleEffect(settled || theme.reduceMotion ? 1 : 0.6)
            .onAppear {
                guard !theme.reduceMotion else { return }
                withAnimation(Design.laneAnimation(arriving: true)) { settled = true }
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

/// Live subscriptions stop at the closed bubbles, instead of invalidating the opening shell.
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
    @ObservedObject private var timers = AppServices.shared.timerPool
    @ObservedObject private var keepAwake = AppServices.shared.keepAwake
    @ObservedObject private var spaces = AppServices.shared.spaces

    @ObservedObject private var theme = ThemeStore.shared
    private var isFileDragTarget: Bool { viewModel.isDropTargeted }
    /// The bubbles held under the camera while the Nook opens, is open and closes.
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

    /// Bubbles beside the camera. The window stays centered; only the compact surface shifts
    /// to fit its sides.
    var body: some View {
        bubbles
        // A song pausing or starting (or a timer ending) adds or removes a bubble, so the
        // agent bubble is told directly to move with it.
        .onChange(of: viewModel.collapsedActivityKinds) { kinds in
            // The shell's surface and offset follow on the same curve.
            withAnimation(viewModel.laneAnimation(to: kinds)) { viewModel.shownActivities = kinds }
            DispatchQueue.main.async { NotchManager.active?.closedLanesChanged() }
        }
        .onAppear {
            let kinds = viewModel.collapsedActivityKinds
            if viewModel.shownActivities != kinds { viewModel.shownActivities = kinds }
        }
        .onChange(of: timerRowIDs) { _ in viewModel.timerRowChanged() }
    }

    /// Each activity its own bubble, the agent bubble's size and spacing,
    /// laid out by `ClearBubbles` (a song keeps its cover left of the camera and its sound
    /// right of it; a timer or anything else sits outside the cover). Each bubble has a fixed
    /// slot one bubble wide (and the gap), so it never rides a row that resizes; it arrives
    /// and leaves by sliding exactly its slot's width out from and back under its inner edge.
    private var bubbles: some View {
        let kinds = isFileDragTarget ? [] : viewModel.collapsedActivityKinds
        let timers = NotchViewModel.timerSides(kinds)
        let layout = ClearBubbles(kinds, timers: timers.left.count + timers.right.count)
        let side = viewModel.closedBubbleSide
        let slot = AgentPopoutLayout.laneWidth(bubbles: 1, side: side)
        // A slot holding timers is as wide as its side's row of them; the rest are one bubble wide.
        func width(_ content: ClearBubbles.Slot?, _ items: [NotchViewModel.TimerItem]) -> CGFloat {
            content == .activity(.timer) ? NotchViewModel.timerLaneWidth(side: side, items: items) : slot
        }
        let outerLeft = layout.left.count > 1 ? layout.left[0] : nil
        let widths = (outer: width(outerLeft, timers.left), left: width(layout.left.last, timers.left),
                      right: width(layout.right.first, timers.right))
        return HStack(spacing: 0) {
            // Outside the song's cover: a timer or other activity beside the song. The slot
            // is always there, so what fills it slides out and back like any other.
            bubbleSlot(outerLeft, side: side, width: widths.outer, outer: .leading)
            bubbleSlot(layout.left.last, side: side, width: widths.left, outer: .leading)
            Color.clear.frame(width: viewModel.geometry.width)
            bubbleSlot(layout.right.first, side: side, width: widths.right, outer: .trailing)
        }
        // This sits on the camera's centre, so the row shifts by whatever the left has more
        // than the right, to keep the camera between them.
        .offset(x: (widths.right - widths.outer - widths.left) / 2)
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
                case .activity(.timer): timerRow(side: side, outer: outer)
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
        NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.music)) {
            SoundBubbleBars(playing: nowPlaying.info.isPlaying)
                .scaleEffect(side * 0.55 / 26)
        }
        .accessibilityHidden(true)
    }

    /// What the timers' rows hold, so the shell follows a timer that comes, goes or changes side.
    private var timerRowIDs: [String] {
        let timers = NotchViewModel.timerSides(viewModel.collapsedActivityKinds)
        return timers.left.map(\.id) + ["|"] + timers.right.map(\.id)
    }

    /// One side's timers: nearest the camera is the first finished, then the soonest. Reversed on
    /// the left, which reads outward from the camera.
    private func timerRow(side: CGFloat, outer: HorizontalEdge) -> some View {
        let timers = NotchViewModel.timerSides(viewModel.collapsedActivityKinds)
        let items = outer == .leading ? timers.left : timers.right
        let squircle = settings.isSquircle(.timer)
        return HStack(spacing: AgentPopoutLayout.gap) {
            ForEach(outer == .leading ? items.reversed() : items) { item in
                switch item {
                case .pill(let timer):
                    TimerAlertPill(timer: timer, side: side, squircle: squircle)
                case .tick(let timer):
                    NotchBubble(side: side, ring: .clear, squircle: squircle) { TimerDoneTick(size: side * 0.42, tint: timer.bubbleTint) }
                        .accessibilityLabel("\(timer.name) finished")
                case .running(let timer):
                    TimerBubble(timer: timer, side: side, squircle: squircle)
                case .more(let count):
                    NotchBubble(side: side, ring: .clear, squircle: squircle) {
                        Text("+\(count)")
                            .font(.system(size: side * 0.36, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(settings.followsTheme(.timer) ? ThemeInks.bubbleAccent(theme) : Color.white.opacity(0.8))
                    }
                    .accessibilityLabel("\(count) more timers")
                }
            }
        }
        .padding(outer == .leading ? .trailing : .leading, AgentPopoutLayout.gap)
    }

    /// One activity as a bubble: the song's artwork with its progress, otherwise the activity's
    /// own symbol or picture.
    @ViewBuilder
    private func bubble(_ activity: CollapsedActivityKind, side: CGFloat) -> some View {
        let colour = { (popOut: NotchPopOut) in ThemeInks.bubbleColour(popOut, theme) }
        let glyph = side * 0.4
        switch activity {
        case .music:
            let info = nowPlaying.info
            // A squircle, like the album cover it holds, filled by it: no outline, so it
            // sits with the agent bubble's black dot (the Music page shows the progress).
            NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.music)) {
                if let artwork = info.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: side - 4, height: side - 4)
                        .clipShape(RoundedRectangle(cornerRadius: settings.isSquircle(.music) ? NotchBubble<EmptyView>.squircleRadius(side - 4) : (side - 4) / 2,
                                                    style: .continuous))
                } else {
                    Image(systemName: "music.note").font(.system(size: glyph, weight: .semibold)).foregroundStyle(colour(.music))
                }
            }
            .offset(x: viewModel.songNudge)
            .accessibilityLabel(info.title.isEmpty ? "Music playing" : "Playing \(info.title)")
        case .timer:
            // `bubbleSlot` draws the timers as a row (`timerRow`).
            EmptyView()
        case .keepAwake:
            // The cup; with a limit, a thin arc of the time left, like a timer's.
            if let end = keepAwake.expiresAt, let total = keepAwake.duration, total > 0 {
                TimelineView(KeepAwakeCountdown(end: end)) { context in
                    NotchBubble(side: side, ring: colour(.keepAwake), progress: max(0, end.timeIntervalSince(context.date)) / total,
                                ringWidth: 1.5, squircle: settings.isSquircle(.keepAwake), track: false) {
                        KeepAwakeCup(size: glyph, tint: colour(.keepAwake))
                    }
                    .accessibilityLabel("Keep Awake, \(KeepAwakeCountdown.label(until: end, at: context.date)) left")
                }
            } else {
                NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.keepAwake)) { KeepAwakeCup(size: glyph, tint: colour(.keepAwake)) }
                    .accessibilityLabel("Keep Awake on")
            }
        case .screenshot:
            NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.screenshot)) {
                if let image = screenshots.recentImage {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: side - 7, height: side - 7)
                        .clipShape(RoundedRectangle(cornerRadius: settings.isSquircle(.screenshot) ? NotchBubble<EmptyView>.squircleRadius(side - 7) : (side - 7) / 2,
                                                    style: .continuous))
                } else {
                    Image(systemName: "camera.viewfinder").font(.system(size: glyph, weight: .semibold)).foregroundStyle(colour(.screenshot))
                }
            }
            .accessibilityLabel("New screenshot, in Tray")
        case .meeting:
            NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.meeting)) {
                Image(systemName: "video.fill").font(.system(size: glyph, weight: .semibold)).foregroundStyle(colour(.meeting))
            }
            .accessibilityLabel(meetings.meeting.map { "\($0.title), \(MeetingCountdown.label(for: $0, at: Date()))" } ?? "Meeting")
        case .pasteQueue:
            // A count only: clip contents never show in the closed Nook.
            NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.pasteQueue)) {
                Text("\(pasteQueue.remaining)")
                    .font(.system(size: side * 0.38, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(colour(.pasteQueue))
            }
            .accessibilityLabel("\(pasteQueue.remaining) clips left to paste")
        case .power:
            NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.power)) {
                PowerActivityGaugeView(monitor: powerMonitor).scaleEffect(0.75)
            }
        case .system:
            if let current = systemActivityMonitor.currentActivity {
                NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.system)) {
                    NotchActivityGlyphView(systemImage: current.systemImage, tint: systemActivityColor(current))
                }
            }
        case .spaces:
            // The number alone; its name is in the widget.
            NotchBubble(side: side, ring: .clear, squircle: settings.isSquircle(.spaces)) {
                Text(spaces.lastChange(on: viewModel.displayIdentifier).map { "\($0.number)" } ?? "")
                    .font(.system(size: side * 0.38, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(colour(.spaces))
            }
            .accessibilityLabel("Desktop \(spaces.activityLabel(on: viewModel.displayIdentifier) ?? "")")
        }
    }

    /// A muted microphone stays red with Follow theme on: it's a warning, not a colour choice.
    private func systemActivityColor(_ activity: SystemLiveActivity) -> Color {
        let themed = settings.followsTheme(.system) ? ThemeInks.bubbleAccent(theme) : nil
        switch activity.kind {
        case .microphone:
            return activity.label == "Muted" ? .red : themed ?? .green
        case .focus:
            return themed ?? .purple
        }
    }

}

/// The sound bubble's bars in the playing cover's strongest colour (`ArtworkWashStore.tint`),
/// or the theme's accents for a cover without one. Its own view, so a new cover redraws only it.
private struct SoundBubbleBars: View {
    let playing: Bool
    @ObservedObject private var wash = ArtworkWashStore.shared
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        AudioSpectrumView(isPlaying: playing, tint: settings.followsTheme(.music) ? ThemeInks.bubbleAccent(theme) : wash.tint)
    }
}
