import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A place's files in the chosen view: Rows, Columns, List, Infinity or Board. Each draws only
/// what's in sight; anything dropped on it goes to `drop`.
struct FolioFileViews: View {
    let mode: FolioViewMode
    /// The place's board (`FolioBoards`): its key and every file the place holds.
    let boardKey: String
    let boardPaths: Set<String>
    let entries: [FolioEntry]
    @Binding var isDropTargeted: Bool
    let drop: ([NSItemProvider]) -> Bool
    let select: (FolioEntry, NSEvent.ModifierFlags) -> Void
    let clear: () -> Void
    let keys: (NSEvent) -> Bool
    let open: (FolioEntry) -> Void

    var body: some View {
        switch mode {
        case .rows, .columns:
            FolioFileGrid(entries: entries, isDropTargeted: $isDropTargeted, drop: drop, select: select, clear: clear,
                          keys: keys, open: open, columns: mode == .columns)
        case .list:
            FolioFileList(entries: entries, isDropTargeted: $isDropTargeted, drop: drop, select: select, clear: clear, keys: keys, open: open)
        case .infinity:
            FolioInfinityWall(entries: entries, isDropTargeted: $isDropTargeted, drop: drop, open: open)
        case .board:
            FolioBoardCanvas(key: boardKey, paths: boardPaths, entries: entries, isDropTargeted: $isDropTargeted, drop: drop,
                             select: select, clear: clear, open: open)
        }
    }
}

// MARK: The switch

/// The header's view control: the current view's symbol, opening a menu of all five with their
/// keys. ⌘1 to ⌘5 switch while the page shows.
struct FolioViewSwitch: View {
    @Binding var mode: FolioViewMode

    var body: some View {
        NookMenu {
            ForEach(FolioViewMode.allCases, id: \.self) { choice in
                NookMenuRow("\(choice.title)    \u{2318}\(choice.key)", systemImage: choice.symbol, selected: choice == mode) { mode = choice }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: mode.symbol).font(.system(size: 10.5, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 6.5, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 24)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .help("View: \(mode.title). \(mode.detail) (\u{2318}1 to \u{2318}5)")
        .accessibilityLabel("View, \(mode.title)")
        .background {
            // ⌘1 to ⌘5, without a menu bar to hold them.
            ZStack {
                ForEach(FolioViewMode.allCases, id: \.self) { choice in
                    Button("") { mode = choice }
                        .keyboardShortcut(KeyEquivalent(choice.key), modifiers: .command)
                }
            }
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

// MARK: List

/// List: one row per file with its thumbnail, name, kind, size and date modified. Rows are made
/// as they scroll into view. Clicks, keys and drags are the grid's.
struct FolioFileList: View {
    let entries: [FolioEntry]
    @Binding var isDropTargeted: Bool
    let drop: ([NSItemProvider]) -> Bool
    let select: (FolioEntry, NSEvent.ModifierFlags) -> Void
    let clear: () -> Void
    let keys: (NSEvent) -> Bool
    let open: (FolioEntry) -> Void
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        GeometryReader { proxy in
            let columns = FolioListColumns(width: proxy.size.width)
            VStack(spacing: 0) {
                FolioListHeader(columns: columns)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            let store = entry.store, id = entry.id
                            FolioListRow(entry: entry, preview: store.previews[id], info: store.info[id], columns: columns,
                                         striped: index % 2 == 1, isSelected: store.selectedIDs.contains(id),
                                         isOffline: store.offlineIDs.contains(id), isBusy: store.busyItemIDs.contains(id),
                                         isLiked: FolioIndex.shared.isLiked(entry.item.url), select: select, keys: keys, open: open)
                        }
                    }
                    .padding(.bottom, 14)
                    Color.clear.frame(height: 40).contentShape(Rectangle()).onTapGesture(perform: clear)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92),
                                             .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.notch.accent, lineWidth: 2).opacity(isDropTargeted ? 1 : 0)
        }
        .onDrop(of: FolioDrops.types, isTargeted: $isDropTargeted, perform: drop)
    }
}

/// Which of the list's columns fit: Kind and Date step aside when the details column narrows it.
struct FolioListColumns {
    let showsKind: Bool
    let showsDate: Bool
    static let kind: CGFloat = 92
    static let size: CGFloat = 54
    static let date: CGFloat = 78

    init(width: CGFloat) {
        showsKind = width >= 360
        showsDate = width >= 300
    }
}

private struct FolioListHeader: View {
    let columns: FolioListColumns

    var body: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 34)
            if columns.showsKind { Text("Kind").frame(width: FolioListColumns.kind, alignment: .leading) }
            Text("Size").frame(width: FolioListColumns.size, alignment: .trailing)
            if columns.showsDate { Text("Modified").frame(width: FolioListColumns.date, alignment: .trailing) }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
    }
}

@MainActor
private struct FolioListRow: View {
    let entry: FolioEntry
    let preview: TrayPreview?
    let info: ShelfFileInfo?
    let columns: FolioListColumns
    let striped: Bool
    let isSelected: Bool
    let isOffline: Bool
    let isBusy: Bool
    let isLiked: Bool
    let select: (FolioEntry, NSEvent.ModifierFlags) -> Void
    let keys: (NSEvent) -> Bool
    let open: (FolioEntry) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.folioRemove) private var remove
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            HStack(spacing: 4) {
                Text(entry.item.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                if isLiked { Image(systemName: "heart.fill").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Color.pink) }
                if isBusy { ProgressView().controlSize(.mini) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if columns.showsKind {
                Text(kind).frame(width: FolioListColumns.kind, alignment: .leading).lineLimit(1).foregroundStyle(.secondary)
            }
            Text(size).frame(width: FolioListColumns.size, alignment: .trailing).monospacedDigit().foregroundStyle(.secondary)
            if columns.showsDate {
                Text(date).frame(width: FolioListColumns.date, alignment: .trailing).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.system(size: 10))
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(isOffline ? 0.45 : 1)
        .overlay {
            ShelfDragHandle(store: entry.store, item: entry.item, select: { _, modifiers in select(entry, modifiers) }, keys: keys,
                            optionClick: { _ in FolioIndex.shared.toggleLike([entry.item.url]) }, open: { _ in open(entry) })
                .accessibilityLabel(entry.item.name)
        }
        .overlay(alignment: .trailing) {
            if hovering && !isBusy {
                Button { if let remove { remove(entry) } else { entry.store.remove(entry.item) } } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(theme.notch.control, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove from \(entry.store.listPhrase) (the file stays where it is)")
                .padding(.trailing, 4)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            ShelfItemMenu(item: entry.item, store: entry.store, isSelected: isSelected, isOffline: isOffline, isBusy: isBusy)
        }
    }

    private var background: Color {
        if isSelected { return theme.notch.accent.opacity(0.22) }
        if hovering { return Color.primary.opacity(0.07) }
        return striped ? Color.primary.opacity(0.03) : .clear
    }

    @ViewBuilder
    private var thumbnail: some View {
        let corner = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            if let preview, preview.isContent {
                Color.clear.overlay { Image(nsImage: preview.image).resizable().interpolation(.medium).scaledToFill() }
            } else if let preview {
                Image(nsImage: preview.image).resizable().interpolation(.medium).scaledToFit().padding(1)
            } else {
                Image(systemName: isOffline ? "externaldrive.badge.xmark" : "doc").font(.system(size: 11, weight: .light)).foregroundStyle(.tertiary)
            }
        }
        .frame(width: 26, height: 22)
        .clipShape(corner)
    }

    private var kind: String { info?.kind ?? "" }

    private var size: String {
        guard let info, !info.isDirectory, let bytes = info.bytes else { return "--" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var date: String {
        guard let modified = info?.modified else { return "" }
        if Calendar.current.isDateInToday(modified) { return modified.formatted(date: .omitted, time: .shortened) }
        return modified.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
    }
}

// MARK: Infinity

/// Infinity: the place's pictures as a wall that never ends (`FolioWall`). The pictures are laid
/// once into columns that repeat in every direction, so scrolling or dragging any way keeps
/// finding pictures. Only the pieces in view are drawn. A click opens the picture full size.
struct FolioInfinityWall: View {
    let entries: [FolioEntry]
    @Binding var isDropTargeted: Bool
    let drop: ([NSItemProvider]) -> Bool
    let open: (FolioEntry) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    /// The wall point at the view's top-left corner.
    @State private var offset = CGPoint(x: 0, y: 0)
    @State private var dragStart: CGPoint?

    static let cell: CGFloat = 96
    static let gap: CGFloat = 6

    var body: some View {
        let pictures = entries.filter { $0.store.info[$0.id]?.isImage == true && $0.store.previews[$0.id]?.isContent == true }
        if pictures.isEmpty {
            FolioQuietEmpty(symbol: "infinity", title: "No pictures to wander",
                            detail: "Infinity shows this place's pictures as an endless wall. Press \u{2318}1 for Rows.")
                .onDrop(of: FolioDrops.types, isTargeted: $isDropTargeted, perform: drop)
        } else {
            wall(pictures)
        }
    }

    private func wall(_ pictures: [FolioEntry]) -> some View {
        GeometryReader { proxy in
            let layout = FolioWall(aspects: pictures.map(FolioFileGrid.aspect), cell: Self.cell, gap: Self.gap)
            let view = CGRect(origin: offset, size: proxy.size).insetBy(dx: -Self.cell / 2, dy: -Self.cell / 2)
            let pieces = layout.placed(in: view)
            ZStack(alignment: .topLeading) {
                Color.primary.opacity(0.001)
                ForEach(pieces) { piece in
                    let entry = pictures[piece.index]
                    FolioWallTile(entry: entry, preview: entry.store.previews[entry.id]) { open(entry) }
                        .frame(width: piece.frame.width, height: piece.frame.height)
                        .offset(x: piece.frame.minX - offset.x, y: piece.frame.minY - offset.y)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                let start = dragStart ?? offset
                if dragStart == nil { dragStart = start }
                offset = CGPoint(x: start.x - value.translation.width, y: start.y - value.translation.height)
            }.onEnded { _ in dragStart = nil })
            .background(FolioScrollCatcher { dx, dy in offset = CGPoint(x: offset.x - dx, y: offset.y - dy) })
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.notch.accent, lineWidth: 2).opacity(isDropTargeted ? 1 : 0)
            }
            .onDrop(of: FolioDrops.types, isTargeted: $isDropTargeted, perform: drop)
            .help("Scroll or drag to wander; click a picture to see it full size")
        }
    }
}

private struct FolioWallTile: View {
    let entry: FolioEntry
    let preview: TrayPreview?
    let open: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            Color.primary.opacity(0.07)
            if let preview { Color.clear.overlay { Image(nsImage: preview.image).resizable().interpolation(.medium).scaledToFill() } }
        }
        .clipShape(corner)
        .overlay { corner.strokeBorder(Color.white.opacity(hovering ? 0.5 : 0), lineWidth: 1) }
        .brightness(hovering ? 0.04 : 0)
        .animation(theme.reduceMotion ? nil : Design.hoverAnimation, value: hovering)
        .contentShape(corner)
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .contextMenu {
            let store = entry.store
            ShelfItemMenu(item: entry.item, store: store, isSelected: store.selectedIDs.contains(entry.id),
                          isOffline: store.offlineIDs.contains(entry.id), isBusy: store.busyItemIDs.contains(entry.id))
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(entry.item.name)
    }
}

/// Hands scroll-wheel and trackpad scrolling over its area to `scrolled` (points, trackpad
/// momentum included) instead of a scroll view, through a local event monitor while it's in a
/// window. It takes no clicks.
struct FolioScrollCatcher: NSViewRepresentable {
    let scrolled: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.scrolled = scrolled }
    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.stop() }

    final class CatcherView: NSView {
        var scrolled: ((CGFloat, CGFloat) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window, !self.isHiddenOrHasHiddenAncestor else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
                self.scrolled?(event.scrollingDeltaX * scale, event.scrollingDeltaY * scale)
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// MARK: Removing

private struct FolioRemoveKey: EnvironmentKey {
    static let defaultValue: ((FolioEntry) -> Void)? = nil
}

private struct FolioTrashesKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FolioSaveColorsKey: EnvironmentKey {
    static let defaultValue: ((URL) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by the Folio page: Save Colors saves a picture's dominant colours to Colors.
    var folioSaveColors: ((URL) -> Void)? {
        get { self[FolioSaveColorsKey.self] }
        set { self[FolioSaveColorsKey.self] = newValue }
    }

    /// Set by the Folio page: removing from a list's menu moves the reference to Folio's Trash.
    var folioTrashes: Bool {
        get { self[FolioTrashesKey.self] }
        set { self[FolioTrashesKey.self] = newValue }
    }

    /// Set by the Folio page: how a tile's remove button removes its file (to Folio's Trash).
    var folioRemove: ((FolioEntry) -> Void)? {
        get { self[FolioRemoveKey.self] }
        set { self[FolioRemoveKey.self] = newValue }
    }
}
