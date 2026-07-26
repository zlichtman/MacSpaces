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

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
        _visualOrder = State(initialValue: viewModel.settings.widgets)
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
                    let fullHeight = min(max(138, proxy.size.height), 180)
                    let compactKinds = compactWidgetKinds
                    NookTilesLayout(spacing: 10) {
                        ForEach(visualOrder) { kind in
                            let compact = compactKinds.contains(kind)
                            dashboardTile(
                                kind: kind,
                                width: kind.preferredWidth,
                                height: compact ? (fullHeight - 10) / 2 : fullHeight,
                                compact: compact
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
        .onChange(of: settings.widgets) { widgets in
            guard draggedKind == nil, visualOrder != widgets else { return }
            visualOrder = widgets
        }
        .onDisappear {
            if draggedKind != nil {
                WidgetDragSession.shared.finish()
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

    private var compactWidgetKinds: Set<NookWidgetKind> {
        Set(
            visualOrder
                .nookLayoutItems()
                .filter(\.isStack)
                .flatMap(\.kinds)
        )
    }

    private func dashboardTile(
        kind: NookWidgetKind,
        width: CGFloat,
        height: CGFloat,
        compact: Bool
    ) -> some View {
        NookDashboardTile(
            kind: kind,
            width: width,
            height: height,
            compact: compact,
            viewModel: viewModel,
            isReordering: draggedKind == kind
        )
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
                onOrderChanged: settings.setWidgetOrder,
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(theme.notch.accent)
                if width >= 150 {
                    Text(kind.title.uppercased())
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        .overlay {
            WidgetContextMenuOverlay(items: contextMenuItems)
        }
    }

    private var contextMenuItems: [WidgetContextMenuItem] {
        var items = [
            WidgetContextMenuItem(
                title: "Add Widget",
                systemImage: "plus",
                children: NookWidgetKind.allCases.map { candidate in
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
                title: "Widget Look",
                systemImage: "paintbrush",
                children: WidgetVisualStyle.styles(for: kind).map { style in
                    WidgetContextMenuItem(
                        title: style.title,
                        systemImage: style.symbol,
                        isSelected: visualStyle == style,
                        action: {
                            viewModel.settings.setWidgetStyle(style, for: kind)
                        }
                    )
                }
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
            MediaPlayerView(nowPlaying: viewModel.nowPlaying, style: visualStyle)
                .padding(.horizontal, 5)
        case .shortcuts:
            ShortcutsWidget(service: AppServices.shared.shortcuts, compact: true)
        case .calendar:
            CalendarWidget(service: AppServices.shared.calendar)
        case .todos:
            RemindersWidget(service: AppServices.shared.calendar)
        case .timer:
            NookTimerWidget(
                service: viewModel.timerService,
                style: visualStyle,
                compact: compact
            )
        case .notes:
            NotesWidget()
        case .mirror:
            MirrorView()
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .padding(6)
        case .battery:
            NookBatteryWidget(monitor: viewModel.powerMonitor, compact: compact)
        case .clock:
            NookClockWidget(style: visualStyle, compact: compact)
        }
    }
}

struct AddNookWidgetMenu: View {
    @ObservedObject var settings: NookSettings
    var labeled = false

    var body: some View {
        Menu {
            ForEach(NookWidgetKind.allCases) { kind in
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

private struct NookTimerWidget: View {
    @ObservedObject var service: TimerService
    let style: WidgetVisualStyle
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 6) {
                    if service.isRunning {
                        Text(service.remainingText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .layoutPriority(1)
                        ProgressView(value: service.progress)
                            .tint(
                                style == .terminal
                                    ? ThemeStore.shared.notch.accent
                                    : .orange
                            )
                        Button {
                            service.cancel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach([5, 15, 25], id: \.self) { minutes in
                            Button("\(minutes)") { service.start(minutes: minutes) }
                                .buttonStyle(.plain)
                                .font(.system(size: 9, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 20)
                                .background(
                                    .primary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                    }
                }
                .padding(.horizontal, 9)
            } else if service.isRunning, style == .orbit {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: service.progress)
                        .stroke(
                            ThemeStore.shared.notch.accent,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(service.remainingText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Button("Cancel") { service.cancel() }
                            .buttonStyle(.plain)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    if service.isRunning {
                        Text(service.remainingText)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        ProgressView(value: service.progress)
                            .tint(style == .terminal ? ThemeStore.shared.notch.accent : .orange)
                            .padding(.horizontal, 14)
                        Button("Cancel") { service.cancel() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "timer")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(.orange)
                        HStack(spacing: 5) {
                            ForEach([5, 15, 25], id: \.self) { minutes in
                                Button("\(minutes)") { service.start(minutes: minutes) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 25, height: 22)
                                    .background(
                                        .primary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 7)
                                    )
                                    .help("Start \(minutes)-minute timer")
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct NookBatteryWidget: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 8) {
                    Image(systemName: monitor.isCharging ? "bolt.fill" : "battery.100percent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.notch.accent)
                    Text(monitor.hasBattery ? "\(monitor.batteryLevel)%" : "Desktop")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer(minLength: 2)
                    Text(monitor.isCharging ? "Charging" : "Power")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: monitor.isCharging ? "bolt.fill" : "battery.100percent")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(theme.notch.accent)
                    Text(monitor.hasBattery ? "\(monitor.batteryLevel)%" : "Desktop")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(monitor.isCharging ? "Charging" : "Power")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct NookClockWidget: View {
    let style: WidgetVisualStyle
    let compact: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if compact {
                HStack(spacing: 5) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(
                            .system(
                                size: 14,
                                weight: .bold,
                                design: style == .terminal ? .monospaced : .rounded
                            )
                        )
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(context.date, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
            } else if style == .terminal {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LOCAL_TIME")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(ThemeStore.shared.notch.accent)
                    Text(context.date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            } else if style == .orbit {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(Calendar.current.component(.second, from: context.date)) / 60)
                        .stroke(
                            ThemeStore.shared.notch.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(12)
            } else if style == .mono {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LOCAL / \(context.date.formatted(.dateTime.weekday(.abbreviated)))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(ThemeStore.shared.notch.accent)
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .monospacedDigit()
                }
            } else if style == .frame {
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(ThemeStore.shared.notch.accent)
                        .frame(width: 2, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(context.date, format: .dateTime.weekday(.wide))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 5) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
