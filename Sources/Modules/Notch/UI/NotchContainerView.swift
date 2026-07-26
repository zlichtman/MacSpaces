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
    @ObservedObject var bluetoothMonitor: BluetoothMonitor
    @ObservedObject var systemActivityMonitor: SystemActivityMonitor
    @ObservedObject private var theme = ThemeStore.shared

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
        self.nowPlaying = viewModel.nowPlaying
        self.powerMonitor = viewModel.powerMonitor
        self.timerService = viewModel.timerService
        self.bluetoothMonitor = viewModel.bluetoothMonitor
        self.systemActivityMonitor = viewModel.systemActivityMonitor
    }

    private var isExpanded: Bool { viewModel.state == .expanded }

    private var surfaceSize: CGSize {
        isExpanded ? viewModel.expandedSize : viewModel.collapsedSize
    }

    var body: some View {
        VStack(spacing: 0) {
            notchSurface
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var notchSurface: some View {
        ZStack(alignment: .top) {
            NotchShape(topCornerRadius: isExpanded ? 12 : 6,
                       bottomCornerRadius: isExpanded ? CGFloat(theme.notchCornerRadius) : 10)
                .fill(theme.notch.surface)
                .background {
                    if theme.notchPreset == .frosted {
                        VisualEffectView(material: .popover)
                    }
                }
                .overlay {
                    NotchShape(
                        topCornerRadius: isExpanded ? 12 : 6,
                        bottomCornerRadius: isExpanded ? CGFloat(theme.notchCornerRadius) : 10
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
                    let edgeWidth = isExpanded
                        ? max(3, theme.notchEdgeWidth * 2.4)
                        : 2
                    NotchEdgeShape(
                        topCornerRadius: isExpanded ? 12 : 6,
                        bottomCornerRadius: isExpanded
                            ? CGFloat(theme.notchCornerRadius)
                            : 10
                    )
                        .stroke(
                            Color.white.opacity(
                                isExpanded
                                    ? 0.025 + 0.16 * theme.notchEdgeStrength
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
                .overlay(alignment: .top) {
                    if isExpanded {
                        expandedContent
                            .transition(.opacity)
                    } else {
                        collapsedContent
                            .transition(.opacity)
                    }
                }
                .clipShape(NotchShape(topCornerRadius: isExpanded ? 12 : 6,
                                      bottomCornerRadius: isExpanded ? CGFloat(theme.notchCornerRadius) : 10))
        }
        .frame(width: surfaceSize.width, height: surfaceSize.height)
        .shadow(color: theme.notch.shadow.opacity(isExpanded ? 1 : 0), radius: 22, y: 8)
        .shadow(color: theme.notch.glow.opacity(isExpanded ? 1 : 0), radius: 34)
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
        .onHover { viewModel.hoverChanged($0) }
        .onTapGesture {
            if !isExpanded { viewModel.expand() }
        }
        .onDrop(of: [UTType.fileURL], delegate: NotchDropDelegate(viewModel: viewModel))
        .animation(.easeOut(duration: 0.18), value: isExpanded)
        .environment(\.colorScheme, theme.notch.colorScheme)
        .tint(theme.notch.accent)
    }

    // MARK: - Collapsed

    /// Live activities rendered in the padding either side of the hardware
    /// notch. Each side is a fixed inner lane so artwork and meters never hug
    /// the expanded surface edge. Two activities can coexist (Music + Timer).
    private var collapsedContent: some View {
        let activities = viewModel.collapsedActivityKinds
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
        HStack(spacing: 5) {
            leftActivity(activity)
            rightActivity(activity)
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private func leftActivity(_ activity: CollapsedActivityKind) -> some View {
        switch activity {
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        case .music:
            MusicActivityArtworkView(nowPlaying: viewModel.nowPlaying)
        case .bluetooth:
            Image(systemName: bluetoothMonitor.activitySystemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.notch.accent)
        case .power:
            PowerActivityIconView(monitor: viewModel.powerMonitor)
        case .system:
            if let activity = systemActivityMonitor.currentActivity {
                Image(systemName: activity.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(systemActivityColor(activity))
            }
        }
    }

    @ViewBuilder
    private func rightActivity(_ activity: CollapsedActivityKind) -> some View {
        switch activity {
        case .timer:
            Text(timerService.remainingText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
        case .music:
            AudioSpectrumView(isPlaying: nowPlaying.info.isPlaying)
        case .bluetooth:
            Text(bluetoothMonitor.activityLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.notch.accent)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.86)
                .layoutPriority(1)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .power:
            PowerActivityLabelView(monitor: powerMonitor)
        case .system:
            if let activity = systemActivityMonitor.currentActivity {
                Text(activity.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(systemActivityColor(activity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
        // Notched hardware reports a menu-bar-height safe top area. Header
        // controls are placed in the usable shoulders around it instead of
        // leaving a full empty band above Nook/Tray.
        let topInset: CGFloat = viewModel.geometry.isHardwareNotch ? 9 : 8
        let horizontalInset: CGFloat = 20
        let bottomInset: CGFloat = 18

        return VStack(spacing: 8) {
            NotchHeaderView(viewModel: viewModel)

            Group {
                switch viewModel.selectedTab {
                case .nook:
                    NookDashboardView(viewModel: viewModel)
                case .tray:
                    ShelfView(store: viewModel.shelf, isDropTargeted: $viewModel.isDropTargeted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if settings.showTeleprompterBar {
                TeleprompterBarView(
                    service: viewModel.teleprompter,
                    settings: settings
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(
            width: max(0, viewModel.expandedSize.width - 2 * horizontalInset),
            height: max(0, viewModel.expandedSize.height - topInset - bottomInset)
        )
        .padding(.top, topInset)
        .colorScheme(theme.notch.colorScheme)
    }
}

/// Expands the shelf when a drag hovers over the collapsed notch.
private struct NotchDropDelegate: DropDelegate {
    let viewModel: NotchViewModel

    func dropEntered(info: DropInfo) {
        viewModel.dragEntered()
        viewModel.isDropTargeted = true
    }

    func dropExited(info: DropInfo) {
        viewModel.isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.isDropTargeted = false
        viewModel.expand(to: .tray)
        return viewModel.shelf.handleDrop(providers: info.itemProviders(for: [.fileURL]))
    }
}
