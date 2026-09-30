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
    @ObservedObject private var theme = ThemeStore.shared

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
                        .frame(width: min(480, viewModel.expandedSize.width - 16),
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
                        ThemeMotifView(motif: motif, accent: theme.notch.accent, ink: theme.nookForeground)
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

        return HStack(spacing: 0) {
            Group {
                if activities.count > 1, let activity = stackedLeftActivity(in: activities) {
                    pairedActivity(activity)
                } else if let activity = activities.first {
                    leftActivity(activity)
                }
            }
            .frame(width: laneWidth, alignment: .center)

            Spacer(minLength: viewModel.geometry.width)

            Group {
                if activities.count > 1, let activity = stackedRightActivity(in: activities) {
                    pairedActivity(activity)
                } else if let activity = activities.first {
                    rightActivity(activity)
                }
            }
            .frame(width: laneWidth, alignment: .center)
        }
        .frame(width: viewModel.collapsedSize.width, height: viewModel.collapsedSize.height)
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
        default:
            HStack(spacing: 5) {
                leftActivity(activity)
                rightActivity(activity)
            }
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private func leftActivity(_ activity: CollapsedActivityKind) -> some View {
        switch activity {
        case .message:
            Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(theme.notch.accent)
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
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
        case .timer:
            Text(timerService.remainingText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
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
        case .volume:
            return theme.notch.accent
        case .displayBrightness, .keyboardBrightness:
            return .yellow
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
                case .coding:
                    CodingUsageView(service: AppServices.shared.codingUsage)
                case .notes:
                    NotesAppView(service: AppServices.shared.notes)
                case .weather:
                    WeatherAppView(service: AppServices.shared.weather)
                case .tray:
                    ShelfView(store: viewModel.shelf, isDropTargeted: $viewModel.isDropTargeted)
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.selectedTab == .nook {
                if settings.widgets.contains(.notifications) {
                    removableQuickBar(.notifications) {
                        MessagesWidget(onEditingChanged: { viewModel.isQuickReplyEditing = $0 })
                    }
                }
            }

            if settings.showTeleprompterBar && viewModel.selectedTab == .nook {
                TeleprompterBarView(
                    service: viewModel.teleprompter,
                    settings: settings, allowsDismissal: viewModel.selectedTab != .music
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
