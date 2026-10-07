import SwiftUI
import UniformTypeIdentifiers

/// The customizable primary Nook. Each feature is a focused horizontal card,
/// ordered by the user and shared with the same services used by the Dock.
struct NookDashboardView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings: NookSettings
    @ObservedObject private var theme = ThemeStore.shared
    @State private var visualOrder: [NookWidgetKind]
    @State private var draggedKind: NookWidgetKind?
    @State private var keyMonitor: Any?

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
        _visualOrder = State(initialValue: viewModel.settings.widgets.filter { !$0.isQuickBar })
    }

    var body: some View {
        GeometryReader { proxy in
            if visualOrder.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(theme.notch.accent)
                    Text("This Nook profile is empty")
                        .font(.system(size: 13, weight: .semibold))
                    AddNookWidgetMenu(settings: viewModel.settings, labeled: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                compatibleWidgetScroll {
                    let fullHeight = max(138, proxy.size.height)
                    let sizes = settings.widgetSizes
                    let widths = visualOrder.fittedNookWidths(availableWidth: proxy.size.width, sizes: sizes)
                    let compactKinds = compactWidgetKinds(sizes)
                    NookTilesLayout(spacing: 10) {
                        ForEach(Array(visualOrder.enumerated()), id: \.element) { index, kind in
                            let compact = compactKinds.contains(kind)
                            dashboardTile(
                                kind: kind,
                                width: widths[kind] ?? kind.width(for: settings.size(for: kind)),
                                height: compact ? (fullHeight - 10) / 2 : fullHeight,
                                compact: compact,
                                entranceIndex: index
                            )
                            .layoutValue(
                                key: NookCompactRowLayoutValueKey.self,
                                value: compact
                            )
                        }
                    }
                    .frame(
                        minWidth: proxy.size.width,
                        minHeight: proxy.size.height,
                        alignment: .center
                    )
                }
            }
        }
        .coordinateSpace(name: NookDashboardTile.space)
        .onChange(of: settings.widgets) { widgets in
            let tiles = widgets.filter { !$0.isQuickBar }
            guard draggedKind == nil, visualOrder != tiles else { return }
            visualOrder = tiles
        }
        // Clicking empty space between or around tiles clears the selection.
        .background {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { viewModel.selectedWidget = nil }
        }
        .overlay(alignment: .bottom) {
            if let removed = viewModel.recentlyRemoved {
                HStack(spacing: 10) {
                    Text("Removed \(removed.kind.title)").font(.system(size: 11, weight: .medium))
                    Button("Undo") { viewModel.undoRemoveWidget() }
                        .buttonStyle(.borderless).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.notch.accent)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(theme.notch.control, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Design.spring(), value: viewModel.recentlyRemoved?.kind)
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if draggedKind != nil {
                WidgetDragSession.shared.finish()
            }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    /// Delete or Forward Delete removes the selected widget, ⌘Z undoes, Escape deselects.
    /// Ignored while a text field has focus, so typing in a widget still edits text, and for
    /// other displays' Nooks, whose own dashboards handle their keys.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let model = viewModel
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard (event.window as? NotchWindow)?.owner === model,
                  model.state == .expanded, model.selectedTab == .nook,
                  !(event.window?.firstResponder is NSTextInputClient) else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 51, 117:
                // Plain Delete only: ⌘⌫ and ⌥⌫ keep their usual meaning. Forward Delete carries .function.
                guard flags.subtracting(.function).isEmpty, model.selectedWidget != nil else { return event }
                model.removeSelectedWidget()
                return nil
            case 6 where flags == .command:
                guard model.recentlyRemoved != nil else { return event }
                model.undoRemoveWidget()
                return nil
            case 53:
                guard model.selectedWidget != nil else { return event }
                model.selectedWidget = nil
                return nil
            default:
                return event
            }
        }
    }

    @ViewBuilder
    private func compatibleWidgetScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 14.0, *) {
            ScrollView(.horizontal, showsIndicators: false, content: content)
                .scrollClipDisabled()
        } else {
            ScrollView(.horizontal, showsIndicators: false, content: content)
        }
    }

    private func compactWidgetKinds(_ sizes: [NookWidgetKind: NookWidgetSize]) -> Set<NookWidgetKind> {
        Set(
            visualOrder
                .nookLayoutItems(sizes: sizes)
                .filter(\.isStack)
                .flatMap(\.kinds)
        )
    }

    private func dashboardTile(
        kind: NookWidgetKind,
        width: CGFloat,
        height: CGFloat,
        compact: Bool,
        entranceIndex: Int
    ) -> some View {
        NookDashboardTile(
            kind: kind,
            width: width,
            height: height,
            compact: compact,
            viewModel: viewModel,
            isReordering: draggedKind == kind,
            isSelected: viewModel.selectedWidget == kind
        )
        .modifier(NookTileEntrance(index: entranceIndex))
        // A click anywhere on a tile selects it; its own buttons keep working.
        .simultaneousGesture(TapGesture().onEnded { viewModel.selectedWidget = kind })
        .onDrag {
            draggedKind = kind
            settings.beginInteractiveReorder()
            WidgetDragSession.shared.begin {
                if draggedKind == kind {
                    draggedKind = nil
                }
                settings.endInteractiveReorder()
            }
            return NSItemProvider(
                object: kind.rawValue as NSString
            )
        }
        .onDrop(
            of: [UTType.text],
            delegate: NookWidgetDropDelegate(
                target: kind,
                order: $visualOrder,
                draggedKind: $draggedKind,
                onOrderChanged: { settings.setWidgetOrder($0 + settings.widgets.filter(\.isQuickBar)) },
                onFinish: WidgetDragSession.shared.finish
            )
        )
    }
}

private struct NookWidgetDropDelegate: DropDelegate {
    let target: NookWidgetKind
    @Binding var order: [NookWidgetKind]
    @Binding var draggedKind: NookWidgetKind?
    let onOrderChanged: ([NookWidgetKind]) -> Void
    let onFinish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedKind,
              draggedKind != target,
              let source = order.firstIndex(of: draggedKind),
              let destination = order.firstIndex(of: target) else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            order.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: destination > source ? destination + 1 : destination
            )
        }
        onOrderChanged(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onFinish()
        return true
    }
}

/// Keeps every widget as a direct child even when two compact widgets share a
/// column. Stable identity is important for media, timers, and camera sessions.
private struct NookTilesLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let grouped = columns(in: subviews)
        let columnWidths: [CGFloat] = grouped.map { column in
            column.map { sizes[$0].width }.max() ?? 0
        }
        let columnHeights: [CGFloat] = grouped.map { column in
            let tilesHeight = column.map { sizes[$0].height }.reduce(0, +)
            let gapsHeight = CGFloat(max(0, column.count - 1)) * spacing
            return tilesHeight + gapsHeight
        }
        let gapsWidth = CGFloat(max(0, grouped.count - 1)) * spacing
        let contentWidth = columnWidths.reduce(0, +) + gapsWidth
        let contentHeight = columnHeights.max() ?? 0
        return CGSize(width: contentWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        for column in columns(in: subviews) {
            let width = column.map { sizes[$0].width }.max() ?? 0
            let height = column.map { sizes[$0].height }.reduce(0, +)
                + CGFloat(max(0, column.count - 1)) * spacing
            var y = bounds.midY - height / 2
            for index in column {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x + (width - size.width) / 2, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                y += size.height + spacing
            }
            x += width + spacing
        }
    }

    private func columns(in subviews: Subviews) -> [[Int]] {
        var result: [[Int]] = []
        var index = subviews.startIndex
        while index < subviews.endIndex {
            let next = subviews.index(after: index)
            if subviews[index][NookCompactRowLayoutValueKey.self],
               next < subviews.endIndex,
               subviews[next][NookCompactRowLayoutValueKey.self] {
                result.append([index, next])
                index = subviews.index(after: next)
            } else {
                result.append([index])
                index = next
            }
        }
        return result
    }
}

private struct NookCompactRowLayoutValueKey: LayoutValueKey {
    static let defaultValue = false
}

private struct NookDashboardTile: View {
    let kind: NookWidgetKind
    let width: CGFloat
    let height: CGFloat
    let compact: Bool
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var theme = ThemeStore.shared
    let isReordering: Bool
    var isSelected = false

    var body: some View {
        // No header: what each widget shows says what it is (a clock, a timer,
        // the cover art). VoiceOver still names the tile.
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, compact ? 4 : 6)
            .padding(.bottom, compact ? 2 : 4)
        .frame(width: width, height: height)
        .background {
            PremiumWidgetChrome(
                tokens: theme.notch,
                style: visualStyle,
                isActive: isReordering
            )
            .overlay { tileBackground.opacity(kind == .media ? 1 : 0) }
            .clipShape(RoundedRectangle(cornerRadius: nookRadius, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: nookRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: nookRadius, style: .continuous))
        .scaleEffect(isReordering && !theme.reduceMotion ? 1.018 : 1)
        .opacity(isReordering ? 0.96 : 1)
        .animation(Design.spring(), value: isReordering)
        .zIndex(isReordering ? 10 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.title)
        .overlay {
            WidgetContextMenuOverlay(items: contextMenuItems)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: nookRadius, style: .continuous)
                    .strokeBorder(theme.notch.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        // The tile is the small form of its page: open it from the corner, or double-click.
        .overlay(alignment: .topTrailing) {
            if let page = kind.page, hovering, !isReordering {
                Button { openPage() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().fill(theme.notch.control.opacity(0.5)))
                        .foregroundStyle(theme.nookForeground)
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Open \(page.title)")
                .accessibilityLabel("Open \(page.title)")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { frame = proxy.frame(in: .named(NookDashboardTile.space)) }
                    .onChange(of: proxy.frame(in: .named(NookDashboardTile.space))) { _, value in frame = value }
            }
        }
        .onHover { value in withAnimation(.easeOut(duration: 0.15)) { hovering = value } }
        .simultaneousGesture(TapGesture(count: 2).onEnded { openPage() })
        .animation(Design.spring(), value: isSelected)
    }

    static let space = "nookDashboard"
    @State private var hovering = false
    @State private var frame: CGRect = .zero

    private func openPage() {
        // The page area is the panel less its insets (20 at the sides, camera clearance on top, 12 below).
        let panel = viewModel.expandedPanelSize
        let size = CGSize(width: panel.width - 40, height: panel.height - viewModel.expandedHeaderTopInset - 12)
        let anchor = size.width > 0 && size.height > 0
            ? UnitPoint(x: min(1, max(0, frame.midX / size.width)), y: min(1, max(0, frame.midY / size.height)))
            : .center
        viewModel.openPage(for: kind, from: anchor)
    }

    private var contextMenuItems: [WidgetContextMenuItem] {
        var items: [WidgetContextMenuItem] = kind.page.map { page in
            [WidgetContextMenuItem(title: "Open \(page.title)", systemImage: "arrow.up.left.and.arrow.down.right",
                                   action: { openPage() }), .separator]
        } ?? []
        items += [
            WidgetContextMenuItem(
                title: "Add Widget",
                systemImage: "plus",
                children: NookWidgetKind.alphabetical.map { candidate in
                    WidgetContextMenuItem(
                        title: candidate.title,
                        systemImage: candidate.systemImage,
                        isEnabled: !viewModel.settings.widgets.contains(candidate),
                        action: {
                            viewModel.settings.setEnabled(true, for: candidate)
                        }
                    )
                }
            ),
            WidgetContextMenuItem(
                title: "Size",
                systemImage: "square.resize",
                children: kind.supportedSizes.map { size in
                    WidgetContextMenuItem(
                        title: size.title + (viewModel.settings.size(for: kind) == size ? " ✓" : ""),
                        systemImage: size.symbol,
                        action: { withAnimation(Design.spring()) { viewModel.settings.setSize(size, for: kind) } }
                    )
                }
            ),
            WidgetContextMenuItem(
                title: "Move Earlier", systemImage: "arrow.left",
                isEnabled: viewModel.settings.widgets.first != kind,
                action: { viewModel.settings.moveWidget(kind, offset: -1) }
            ),
            WidgetContextMenuItem(
                title: "Move Later", systemImage: "arrow.right",
                isEnabled: viewModel.settings.widgets.last != kind,
                action: { viewModel.settings.moveWidget(kind, offset: 1) }
            ),

        ]
        if kind == .shortcuts {
            items.append(
                WidgetContextMenuItem(
                    title: "Refresh Shortcuts",
                    systemImage: "arrow.clockwise",
                    action: AppServices.shared.shortcuts.refresh
                )
            )
        }
        items.append(.separator)
        items.append(
            WidgetContextMenuItem(
                title: "Remove \(kind.title)",
                systemImage: "trash",
                action: {
                    viewModel.settings.setEnabled(false, for: kind)
                }
            )
        )
        return items
    }

    private var tileBackground: some View {
        ZStack {
            theme.notch.tileGradient

            if kind == .media {
                LinearGradient(
                    colors: [
                        theme.notch.accent.opacity(0.07),
                        Color.clear,
                    ],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
            }
        }
    }

    private var nookRadius: CGFloat {
        visualStyle.chromeRadius
    }

    private var visualStyle: WidgetVisualStyle {
        viewModel.settings.widgetStyle(for: kind)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .media:
            if compact {
                CompactMediaView(nowPlaying: viewModel.nowPlaying)
            } else {
                MediaPlayerView(nowPlaying: viewModel.nowPlaying, style: visualStyle)
                    .padding(.horizontal, 5)
                    // The cover tints the whole tile, as on the Music page.
                    .background { ArtworkAmbienceFollowing(nowPlaying: viewModel.nowPlaying).padding(-40) }
            }
        case .shortcuts:
            ShortcutsWidget(service: AppServices.shared.shortcuts, compact: true)
        case .calendar:
            CalendarWidget(service: AppServices.shared.calendar, compact: compact,
                           large: viewModel.settings.size(for: .calendar) == .large)
        case .todos:
            RemindersWidget(service: AppServices.shared.calendar, compact: compact)
        case .timer:
            NookTimerWidget(service: viewModel.timerService, compact: compact)
        case .notes:
            NotesWidget(compact: compact)
        case .mirror:
            MirrorView()
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(6)
        case .battery:
            NookBatteryWidget(monitor: viewModel.powerMonitor, bluetooth: viewModel.bluetoothMonitor, compact: compact,
                              onDetailsChanged: { viewModel.isDeviceDetailsPresented = $0 })
        case .clock:
            NookClockWidget(compact: compact)
        case .weather:
            WeatherWidget(service: AppServices.shared.weather, compact: compact,
                          showsForecast: width >= 260, surface: .notch,
                          onDetailsChanged: { viewModel.isWeatherDetailsPresented = $0 })
        case .clipboard:
            ClipboardWidget(monitor: AppServices.shared.clipboard, compact: compact)
        case .pomodoro:
            PomodoroWidget(compact: compact)
        case .quickActions:
            QuickActionsWidget(columns: width >= 220 ? 3 : 2)
        case .systemStats:
            SystemStatsWidget(service: AppServices.shared.systemStats, compact: compact)
        case .notifications:
            MessagesWidget()
        case .keepAwake:
            KeepAwakeWidget(service: AppServices.shared.keepAwake, compact: compact)
        case .terminal:
            TerminalWidget(shell: AppServices.shared.quickShell,
                           onEditingChanged: { viewModel.isPageEditing = $0 })
        case .devServers:
            DevServersWidget()
        case .calculator:
            CalculatorWidget(onEditingChanged: { viewModel.isPageEditing = $0 })

        }
    }
}

struct AddNookWidgetMenu: View {
    @ObservedObject var settings: NookSettings
    var labeled = false

    var body: some View {
        Menu {
            ForEach(NookWidgetKind.alphabetical) { kind in
                Button {
                    settings.setEnabled(true, for: kind)
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                }
                .disabled(settings.widgets.contains(kind))
            }
        } label: {
            if labeled {
                Label("Add Widget", systemImage: "plus")
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
        }
        .menuStyle(.borderlessButton)
        .help("Add a widget to this Nook profile")
    }
}

extension NookWidgetSize {
    var symbol: String {
        switch self {
        case .small: return "square.split.1x2"
        case .medium: return "rectangle.portrait"
        case .large: return "rectangle"
        }
    }
}

/// Tiles fall out of the notch one after another as the Nook opens, so the
/// panel reads as a drop rather than a window appearing.
private struct NookTileEntrance: ViewModifier {
    let index: Int
    @State private var settled = false
    @ObservedObject private var theme = ThemeStore.shared

    func body(content: Content) -> some View {
        content
            .opacity(settled ? 1 : 0)
            .offset(y: settled || theme.reduceMotion ? 0 : -18)
            .scaleEffect(settled || theme.reduceMotion ? 1 : 0.94, anchor: .top)
            .blur(radius: settled || theme.reduceMotion ? 0 : 5)
            .onAppear {
                guard !settled else { return }
                let delay = theme.reduceMotion ? 0 : 0.05 + Double(min(index, 8)) * 0.035
                withAnimation(Design.dropAnimation.delay(delay * Design.demoTimeScale)) { settled = true }
            }
    }
}

/// The album-art wash, following the current track.
private struct ArtworkAmbienceFollowing: View {
    @ObservedObject var nowPlaying: NowPlayingController
    var body: some View { ArtworkAmbience(artwork: nowPlaying.info.artwork) }
}
