import SwiftUI
import UniformTypeIdentifiers

/// Root view hosted in the notch window. Renders the black notch-shaped
/// surface and morphs between the collapsed strip and the expanded nook.
struct NotchContainerView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var settings: NookSettings
    // Observed here so collapsed-state live activities refresh with the data.
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject var powerMonitor: PowerSourceMonitor
    @ObservedObject var timerService: TimerService
    @ObservedObject var systemActivityMonitor: SystemActivityMonitor
    @ObservedObject private var messageActivity = MessageActivityState.shared
    @ObservedObject private var pasteQueue = PasteQueueState.shared
    @ObservedObject private var meetings = MeetingCountdown.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @ObservedObject private var screenshots = ScreenshotWatcher.shared
    @ObservedObject private var secondTimer = AppServices.shared.extraTimers[0]
    @ObservedObject private var thirdTimer = AppServices.shared.extraTimers[1]

    /// Every running timer, soonest first ("9:49  14:38  24:39").
    private var timerLabel: String { NotchViewModel.timerLabel }
    private var runningTimers: [TimerService] { NotchViewModel.runningTimers }
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
        self.nowPlaying = viewModel.nowPlaying
        self.powerMonitor = viewModel.powerMonitor
        self.timerService = viewModel.timerService
        self.systemActivityMonitor = viewModel.systemActivityMonitor
    }

    private var isExpanded: Bool { viewModel.state == .expanded }

    /// A file dragged near the closed notch: the notch swells into a target.
    private var isFileDragTarget: Bool { !isExpanded && viewModel.isDropTargeted }

    private var surfaceSize: CGSize {
        if isExpanded { return viewModel.expandedPanelSize }
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, theme.notch.colorScheme)
        .tint(theme.notch.accent)
        .foregroundStyle(theme.nookForeground)
    }

    private var notchSurface: some View {
        ZStack(alignment: .top) {
            NotchShape(topCornerRadius: isExpanded ? 12 : 6,
                       bottomCornerRadius: isExpanded ? Design.nookRadius : 10, roundsTopInward: isExpanded)
                .fill(theme.notch.surface)
                .background {
                    if theme.family == .glass || (theme.family == nil && theme.notchPreset == .frosted) {
                        VisualEffectView(material: .popover)
                    }
                }
                .overlay {
                    NotchShape(
                        topCornerRadius: isExpanded ? 12 : 6,
                        bottomCornerRadius: isExpanded ? Design.nookRadius : 10, roundsTopInward: isExpanded
                    )
                    .fill(
                        LinearGradient(
                            colors: [theme.notch.surfaceSecondary, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    if isExpanded, let motif = theme.activeMotif {
                        ThemeMotifView(motif: motif, accent: theme.notch.accent, ink: theme.nookForeground,
                                       animated: theme.animatesEffects && !reduceMotion)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if isExpanded && viewModel.selectedTab == .music {
                        ArtworkAmbience(artwork: nowPlaying.info.artwork)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    let edgeWidth: CGFloat = isExpanded ? 1 : 2
                    NotchEdgeShape(
                        topCornerRadius: isExpanded ? 12 : 6,
                        bottomCornerRadius: isExpanded
                            ? Design.nookRadius
                            : 10,
                        roundsTopInward: isExpanded
                    )
                        .stroke(
                            Color.white.opacity(
                                isExpanded
                                    ? 0.10
                                    : 0.07
                            ),
                            style: StrokeStyle(
                                lineWidth: edgeWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .padding(edgeWidth / 2)
                }
                .clipShape(NotchShape(topCornerRadius: isExpanded ? 12 : 6,
                                      bottomCornerRadius: isExpanded ? Design.nookRadius : 10,
                                      roundsTopInward: isExpanded))
                .padding(.top, isExpanded && viewModel.geometry.isHardwareNotch
                         ? viewModel.geometry.height + NotchViewModel.cameraGap : 0)
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
                            .transition(.nookDepth())
                    } else {
                        collapsedContent
                            .transition(.nookDepth(blur: 4, scale: 1, anchor: .center))
                    }
                }
                .clipShape(NotchShape(topCornerRadius: isExpanded ? 12 : 6,
                                      bottomCornerRadius: isExpanded ? Design.nookRadius : 10, roundsTopInward: isExpanded))
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
        .overlay {
            // Accent rim and glow while a file hovers over the closed notch.
            NotchEdgeShape(topCornerRadius: 6, bottomCornerRadius: 10)
                .stroke(theme.notch.accent.opacity(isFileDragTarget ? 0.9 : 0), lineWidth: 1.5)
                .shadow(color: theme.notch.accent.opacity(isFileDragTarget ? 0.55 : 0), radius: 12)
                .allowsHitTesting(false)
        }
        .shadow(color: theme.notch.shadow.opacity(isExpanded ? 1 : 0), radius: 22, y: 8)
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

    // MARK: - Collapsed

    /// Live activities rendered in the padding either side of the hardware
    /// notch. Each side is a fixed inner lane so artwork and meters never hug
    /// the expanded surface edge. Two activities can coexist (Music + Timer).
    private var collapsedContent: some View {
        let activities = isFileDragTarget ? [] : viewModel.collapsedActivityKinds
        let laneWidth = viewModel.collapsedActivityLaneWidth
        // Power and system cards keep their own fixed lanes; everything else fits its content.
        let fits = !activities.contains(.power) && !activities.contains(.system)

        // Each side is measured at its natural width; the lanes fit the wider one.
        // The narrower side sits toward the outer edge, so any slack is beside the camera.
        return HStack(spacing: 0) {
            Group {
                if activities.count > 1, let activity = stackedLeftActivity(in: activities) {
                    pairedActivity(activity)
                } else if let activity = activities.first {
                    leftActivity(activity)
                }
            }
            .modifier(FittedLane(fits: fits, outerEdge: .leading))
            .frame(width: laneWidth, alignment: fits ? .leading : .center)

            Spacer(minLength: viewModel.geometry.width)

            Group {
                if activities.count > 1, let activity = stackedRightActivity(in: activities) {
                    pairedActivity(activity)
                } else if let activity = activities.first {
                    rightActivity(activity)
                }
            }
            .modifier(FittedLane(fits: fits, outerEdge: .trailing))
            .frame(width: laneWidth, alignment: fits ? .trailing : .center)
        }
        .frame(width: viewModel.collapsedSize.width, height: viewModel.collapsedSize.height)
        .onPreferenceChange(LaneWidthKey.self) { width in
            let fitted = ceil(width)
            if abs(viewModel.measuredLaneContent - fitted) > 0.5 { viewModel.measuredLaneContent = fitted }
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
            PowerActivityIconView(monitor: powerMonitor, compact: true)
        case .agent:
            AgentActivityRow(sessions: agents.notchSessions, accent: theme.notch.accent)
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
        case .message:
            Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(theme.notch.accent)
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
        case .agent:
            if agents.notchSessions.count > 1 {
                AgentActivityRow(sessions: Array(agents.notchSessions.prefix((agents.notchSessions.count + 1) / 2)), accent: theme.notch.accent)
            } else {
                AgentActivityGlyph(session: agents.headline, accent: theme.notch.accent)
                    .frame(width: 22, height: 22)
            }
        case .pasteQueue:
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.notch.accent)
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(runningTimers.first?.tint ?? .orange)
        case .music:
            MusicActivityArtworkView(nowPlaying: viewModel.nowPlaying)
        case .power:
            PowerActivityIconView(monitor: viewModel.powerMonitor)
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
        case .message:
            Text("\(messageActivity.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.notch.accent).accessibilityLabel("\(messageActivity.count) incoming messages")
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
        case .agent:
            if agents.notchSessions.count > 1 {
                AgentActivityRow(sessions: Array(agents.notchSessions.dropFirst((agents.notchSessions.count + 1) / 2)), accent: theme.notch.accent)
            } else if let session = agents.headline {
                AgentActivityPulse(state: session.state, agent: session.agent)
                    .accessibilityLabel("\(session.name) in \(session.project): \(session.headline)")
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
        case .music:
            AudioSpectrumView(isPlaying: nowPlaying.info.isPlaying)
        case .power:
            PowerActivityLabelView(monitor: powerMonitor)
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
                        .transition(.nookDepth(blur: 4, scale: 0.98, anchor: .center))
                case .music:
                    MediaPlayerView(nowPlaying: nowPlaying, style: .studio, largeArtwork: true,
                                    lyricsService: viewModel.teleprompter)
                case .calendar:
                    CalendarAppView(service: AppServices.shared.calendar)
                case .notes:
                    NotesAppView(service: AppServices.shared.notes)
                case .weather:
                    WeatherAppView(service: AppServices.shared.weather)
                case .tray:
                    TrayPageView(tray: viewModel.shelf, isDropTargeted: $viewModel.isDropTargeted)
                        .transition(.nookDepth(blur: 4, scale: 0.98, anchor: .center))
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
                                  bluetooth: viewModel.bluetoothMonitor, keepAwake: AppServices.shared.keepAwake)
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
                case .messages:
                    MessagesPage(service: AppServices.shared.messages,
                                 onEditingChanged: { viewModel.isPageEditing = $0 })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A page opened from a Home tile grows out of that tile; going back fades.
            .id(viewModel.selectedTab)
            .transition(viewModel.selectedTab == .nook ? .opacity
                        : .asymmetric(insertion: .scale(scale: 0.4, anchor: viewModel.pageAnchor).combined(with: .opacity),
                                      removal: .opacity))

            if viewModel.selectedTab == .nook {
                if settings.widgets.contains(.notifications) {
                    removableQuickBar(.notifications) {
                        MessagesWidget(onEditingChanged: { viewModel.isQuickReplyEditing = $0 })
                    }
                }
            }

        }
        .frame(
            width: max(0, viewModel.expandedSize.width - 2 * horizontalInset),
            height: max(0, viewModel.expandedPanelSize.height - topInset - bottomInset)
        )
        .padding(.top, topInset)
        .colorScheme(theme.notch.colorScheme)
    }
    private func removableQuickBar<Content: View>(
        _ kind: NookWidgetKind, @ViewBuilder content: () -> Content
    ) -> some View {
        content().quickActionBar()
            .overlay {
                WidgetContextMenuOverlay(items: [
                    WidgetContextMenuItem(title: "Remove \(kind.title)", systemImage: "trash") {
                        removeQuickBar(kind)
                    }
                ])
            }
            .accessibilityAction(named: Text("Remove \(kind.title)")) {
                removeQuickBar(kind)
            }
    }

    private func removeQuickBar(_ kind: NookWidgetKind) {
        if kind == .notifications { viewModel.isQuickReplyEditing = false }
        settings.setEnabled(false, for: kind)
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
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A lane drawn at its natural width (with its padding) and measured.
private struct FittedLane: ViewModifier {
    let fits: Bool
    /// The side away from the camera: room for the rounded corner there, almost none beside the camera.
    let outerEdge: Edge.Set

    func body(content: Content) -> some View {
        if fits {
            content.fixedSize()
                .padding(outerEdge, 10)
                .padding(outerEdge == .leading ? .trailing : .leading, 4)
                .background(LaneWidthReader())
        } else {
            content
        }
    }
}

private struct LaneWidthReader: View {
    var body: some View {
        GeometryReader { proxy in Color.clear.preference(key: LaneWidthKey.self, value: proxy.size.width) }
    }
}

/// Claude or Codex: a pulsing mark while working, a bell when it needs you, a check when done.
/// The agent's colours in the closed notch, fixed so they read on every theme:
/// Claude in its orange, Codex in a pale blue-white; green once it's done.
enum AgentTint {
    static func agent(_ agent: String) -> Color {
        agent == "codex" ? Color(red: 0.78, green: 0.87, blue: 1) : Color(red: 0.85, green: 0.47, blue: 0.34)
    }

    static func color(_ state: AgentActivityMonitor.Session.State, agent: String) -> Color {
        state == .done ? .green : self.agent(agent)
    }
}

/// The app an agent runs in, plain: the orb on the other side shows what it's doing.
struct AgentActivityGlyph: View {
    let session: AgentActivityMonitor.Session?
    let accent: Color

    var body: some View {
        Group {
            if let session, let icon = AgentActivityMonitor.icon(for: session) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "sparkle").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AgentTint.agent(session?.agent ?? "claude"))
            }
        }
        .accessibilityLabel(session.flatMap(\.appName) ?? session?.name ?? "Coding agent")
    }
}

/// The other side of the notch: KemoSabe's searching orb (a turning dotted globe,
/// as on the KemoSabe demo) while the agent works, a pulsing "!" when it needs you, a check when it's done.
struct AgentActivityPulse: View {
    let state: AgentActivityMonitor.Session.State
    var agent = "claude"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tint = AgentTint.color(state, agent: agent)
        HStack(spacing: 4) {
            // Driven by a timer-scheduled timeline (`.animation` ones pause in the menu-bar panel).
            TimelineView(.periodic(from: .now, by: reduceMotion ? 3600 : 1 / 30)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                switch state {
                case .working:
                    // The full-size preset: its even rows of dots read as a turning globe on a Retina notch,
                    // where the 20 px preset scatters into specks. Drawn three times through the orb's mask so the fine dots hold up.
                    ZStack {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(tint)
                                .mask { ThinkingOrb(state: .searching, size: .px64, theme: .dark, displaySize: 22).orbFrozenTime(t) }
                        }
                    }
                    .frame(width: 22, height: 22)
                case .needsYou:
                    let pulseScale: CGFloat = CGFloat(1.0 + 0.075 * (sin(t * 5.0) + 1.0))
                    Image(systemName: "exclamationmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                        .scaleEffect(pulseScale)
                case .done:
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                }
            }

        }
        .frame(width: 22, height: 22)
    }
}


/// Each session keeps its host icon beside its own status, including multiple sessions in one app.
struct AgentActivityRow: View {
    let sessions: [AgentActivityMonitor.Session]
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(sessions) { session in
                HStack(spacing: 4) {
                    AgentActivityGlyph(session: session, accent: accent)
                        .frame(width: 22, height: 22)
                    AgentActivityPulse(state: session.state, agent: session.agent)
                }
                .frame(width: 48, height: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(session.name) in \(session.project): \(session.headline)")
                .help("\(session.name) · \(session.project) · \(session.headline)")
            }
        }
        .fixedSize()
    }
}
