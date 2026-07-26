import SwiftUI
import UniformTypeIdentifiers

/// The dock surface: a frosted rounded strip laying out widget tiles
/// horizontally (bottom) or vertically (left/right).
struct DockContainerView: View {
    @ObservedObject var store: DockStore
    @ObservedObject private var theme = ThemeStore.shared
    @State private var visualWidgets: [WidgetInstance]
    @State private var draggedWidgetID: UUID?

    init(store: DockStore) {
        self.store = store
        _visualWidgets = State(initialValue: store.widgets)
    }

    var body: some View {
        ScrollView(store.effectivePosition.isVertical ? .vertical : .horizontal, showsIndicators: false) {
            DockTilesLayout(
                vertical: store.effectivePosition.isVertical,
                spacing: DockController.tileSpacing
            ) {
                if visualWidgets.isEmpty {
                    DockEmptyWidgetMenu(store: store)
                        .frame(
                            width: store.effectivePosition.isVertical
                                ? CGFloat(store.sideDockWidth)
                                : 76,
                            height: store.effectivePosition.isVertical
                                ? 76
                                : CGFloat(store.tileSize)
                        )
                } else {
                    tiles
                }
            }
            .padding(DockController.outerPadding)
        }
        .background(
            ZStack {
                if theme.dockPreset == .frosted {
                    VisualEffectView()
                }
                theme.dock.surface
                LinearGradient(
                    colors: [theme.dock.surfaceSecondary, .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(theme.dockCornerRadius), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(theme.dockCornerRadius), style: .continuous)
                .strokeBorder(theme.dock.border, lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, theme.dock.colorScheme)
        .tint(theme.dock.accent)
        .onChange(of: store.widgets) { _, widgets in
            guard draggedWidgetID == nil,
                  visualWidgets != widgets else { return }
            visualWidgets = widgets
        }
        .onDisappear {
            if draggedWidgetID != nil {
                WidgetDragSession.shared.finish()
            }
        }
    }

    private var compactWidgetIDs: Set<UUID> {
        Set(
            visualWidgets
                .dockLayoutItems(vertical: store.effectivePosition.isVertical)
                .filter(\.isStack)
                .flatMap(\.instances)
                .map(\.id)
        )
    }

    private var tiles: some View {
        let compactIDs = compactWidgetIDs
        return ForEach(visualWidgets) { instance in
            let isCompact = compactIDs.contains(instance.id)
            WidgetTileView(
                instance: instance,
                store: store,
                isCompactRow: isCompact,
                isReordering: draggedWidgetID == instance.id
            )
            .onDrag {
                draggedWidgetID = instance.id
                store.beginInteractiveReorder()
                WidgetDragSession.shared.begin {
                    if draggedWidgetID == instance.id {
                        draggedWidgetID = nil
                    }
                    store.endInteractiveReorder()
                }
                return NSItemProvider(
                    object: instance.id.uuidString as NSString
                )
            }
            .onDrop(
                of: [UTType.text],
                delegate: DockWidgetDropDelegate(
                    targetID: instance.id,
                    widgets: $visualWidgets,
                    draggedWidgetID: $draggedWidgetID,
                    onOrderChanged: store.setWidgetOrder,
                    onFinish: WidgetDragSession.shared.finish
                )
            )
            .layoutValue(
                key: DockCompactRowLayoutValueKey.self,
                value: isCompact
            )
        }
    }
}

private struct DockEmptyWidgetMenu: View {
    @ObservedObject var store: DockStore
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Menu {
            ForEach(WidgetKind.allCases) { kind in
                Button {
                    store.add(kind)
                } label: {
                    Label(kind.title, systemImage: kind.systemImage)
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Widget")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.dock.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                theme.dock.control,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.dock.border, lineWidth: 0.8)
            }
        }
        .menuStyle(.borderlessButton)
        .help("Add a widget")
    }
}

private struct DockWidgetDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var widgets: [WidgetInstance]
    @Binding var draggedWidgetID: UUID?
    let onOrderChanged: ([WidgetInstance]) -> Void
    let onFinish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedWidgetID,
              draggedWidgetID != targetID,
              let source = widgets.firstIndex(
                where: { $0.id == draggedWidgetID }
              ),
              let destination = widgets.firstIndex(
                where: { $0.id == targetID }
              ) else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            widgets.move(
                fromOffsets: IndexSet(integer: source),
                toOffset: destination > source ? destination + 1 : destination
            )
        }
        onOrderChanged(widgets)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onFinish()
        return true
    }
}

/// Keeps every widget as a direct child even when two glanceable widgets
/// share a column. Their identities therefore survive crossing stack
/// boundaries during a drag instead of being recreated inside a new VStack.
private struct DockTilesLayout: Layout {
    let vertical: Bool
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return .zero }

        if vertical {
            return CGSize(
                width: sizes.map(\.width).max() ?? 0,
                height: sizes.map(\.height).reduce(0, +)
                    + CGFloat(max(0, sizes.count - 1)) * spacing
            )
        }

        let columns = horizontalColumns(in: subviews)
        let widths = columns.map { column in
            column.map { sizes[$0].width }.max() ?? 0
        }
        let heights = columns.map { column in
            column.map { sizes[$0].height }.reduce(0, +)
                + CGFloat(max(0, column.count - 1)) * spacing
        }
        return CGSize(
            width: widths.reduce(0, +)
                + CGFloat(max(0, widths.count - 1)) * spacing,
            height: heights.max() ?? 0
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return }

        if vertical {
            var y = bounds.minY
            for index in subviews.indices {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: bounds.midX - size.width / 2, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                y += size.height + spacing
            }
            return
        }

        var x = bounds.minX
        for column in horizontalColumns(in: subviews) {
            let columnWidth = column.map { sizes[$0].width }.max() ?? 0
            let columnHeight = column.map { sizes[$0].height }.reduce(0, +)
                + CGFloat(max(0, column.count - 1)) * spacing
            var y = bounds.midY - columnHeight / 2

            for index in column {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(
                        x: x + (columnWidth - size.width) / 2,
                        y: y
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                y += size.height + spacing
            }
            x += columnWidth + spacing
        }
    }

    private func horizontalColumns(in subviews: Subviews) -> [[Int]] {
        var columns: [[Int]] = []
        var index = subviews.startIndex
        while index < subviews.endIndex {
            let next = subviews.index(after: index)
            if subviews[index][DockCompactRowLayoutValueKey.self],
               next < subviews.endIndex,
               subviews[next][DockCompactRowLayoutValueKey.self] {
                columns.append([index, next])
                index = subviews.index(after: next)
            } else {
                columns.append([index])
                index = next
            }
        }
        return columns
    }
}

private struct DockCompactRowLayoutValueKey: LayoutValueKey {
    static let defaultValue = false
}

/// Uniform tile chrome plus dispatch from widget kind to its concrete view.
struct WidgetTileView: View {
    let instance: WidgetInstance
    @ObservedObject var store: DockStore
    let isCompactRow: Bool
    let isReordering: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @State private var isHovering = false

    private var tile: CGFloat { CGFloat(store.tileSize) }

    private var length: CGFloat {
        instance.kind.axisLength(tile: tile, spacing: DockController.tileSpacing)
    }

    private var crossLength: CGFloat {
        store.effectivePosition.isVertical ? CGFloat(store.sideDockWidth) : tile
    }

    private var renderedHeight: CGFloat {
        guard isCompactRow, !store.effectivePosition.isVertical else {
            return store.effectivePosition.isVertical ? length : tile
        }
        return (tile - DockController.tileSpacing) / 2
    }

    var body: some View {
        widgetBody
            .frame(width: store.effectivePosition.isVertical ? crossLength : length,
                   height: renderedHeight)
            .background {
                if instance.kind != .spacer && instance.kind != .separator {
                    PremiumWidgetChrome(
                        tokens: theme.dock,
                        style: instance.visualStyle,
                        isActive: isHovering
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: dockRadius, style: .continuous))
            .scaleEffect((isHovering || isReordering) && !theme.reduceMotion ? 1.014 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0), radius: 8, y: 4)
            .animation(Design.hoverAnimation, value: isHovering)
            .onHover { isHovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: dockRadius, style: .continuous))
            .zIndex(isReordering ? 10 : 0)
            .overlay {
                WidgetContextMenuOverlay(items: contextMenuItems)
            }
    }

    private var contextMenuItems: [WidgetContextMenuItem] {
        var items = [
            WidgetContextMenuItem(
                title: "Add Widget",
                systemImage: "plus",
                children: WidgetKind.allCases.map { kind in
                    WidgetContextMenuItem(
                        title: kind.title,
                        systemImage: kind.systemImage,
                        action: { store.add(kind) }
                    )
                }
            ),
            WidgetContextMenuItem(
                title: "Move Earlier",
                systemImage: "arrow.left",
                isEnabled: store.widgets.first?.id != instance.id,
                action: { store.move(instance, offset: -1) }
            ),
            WidgetContextMenuItem(
                title: "Move Later",
                systemImage: "arrow.right",
                isEnabled: store.widgets.last?.id != instance.id,
                action: { store.move(instance, offset: 1) }
            ),
            WidgetContextMenuItem(
                title: "Duplicate",
                systemImage: "plus.square.on.square",
                action: { store.duplicate(instance) }
            ),
            WidgetContextMenuItem(
                title: "Widget Look",
                systemImage: "paintbrush",
                children: WidgetVisualStyle.styles(for: instance.kind).map {
                    style in
                    WidgetContextMenuItem(
                        title: style.title,
                        systemImage: style.symbol,
                        isSelected: instance.visualStyle == style,
                        action: {
                            store.setWidgetStyle(style, for: instance)
                        }
                    )
                }
            ),
        ]
        if instance.kind == .shortcuts {
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
                title: "Remove \(instance.kind.title)",
                systemImage: "trash",
                action: { store.remove(instance) }
            )
        )
        return items
    }

    private var dockRadius: CGFloat {
        instance.visualStyle.chromeRadius
    }

    @ViewBuilder
    private var widgetBody: some View {
        switch instance.kind {
        case .clock:
            ClockWidget(style: instance.visualStyle, compact: isCompactRow)
        case .weather:
            WeatherWidget(service: store.weather, compact: isCompactRow)
        case .calendar: CalendarWidget(service: store.calendar)
        case .reminders: RemindersWidget(service: store.calendar)
        case .nowPlaying:
            NowPlayingWidget(
                nowPlaying: store.nowPlaying,
                isVertical: store.effectivePosition.isVertical,
                style: instance.visualStyle
            )
        case .systemStats:
            SystemStatsWidget(
                service: store.systemStats,
                isVertical: store.effectivePosition.isVertical
            )
        case .apps: AppsWidget()
        case .quickActions: QuickActionsWidget()
        case .clipboard: ClipboardWidget(monitor: store.clipboard)
        case .pomodoro: PomodoroWidget(compact: isCompactRow)
        case .search: SearchWidget()
        case .notes: NotesWidget()
        case .colorPicker: ColorPickerWidget()
        case .converter: ConverterWidget()
        case .bookmarks: BookmarksWidget()
        case .appSwitcher: AppSwitcherWidget()
        case .audio: AudioControlsWidget(isVertical: store.effectivePosition.isVertical)
        case .drinkWater: DrinkWaterWidget()
        case .progress: ProgressWidget()
        case .downloads: DownloadsWidget()
        case .fileShelf: FileShelfWidget()
        case .emoji: EmojiWidget()
        case .screenshots: ScreenshotsWidget()
        case .voiceMemo: VoiceMemoWidget()
        case .mail: MailWidget()
        case .photos: PhotosWidget()
        case .crypto: CryptoWidget(service: store.crypto)
        case .claude: ClaudeWidget()
        case .zoomMeetings: ZoomMeetingsWidget(service: store.calendar)
        case .windowManager: WindowManagerWidget()
        case .wallpaper: WallpaperWidget()
        case .spacer: SpacerWidget()
        case .separator: SeparatorWidget(isVerticalDock: store.effectivePosition.isVertical)
        case .shortcuts: ShortcutsWidget(service: AppServices.shared.shortcuts, compact: false)
        }
    }
}
