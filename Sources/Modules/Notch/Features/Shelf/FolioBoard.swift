import AppKit
import SwiftUI

/// Every place's board: where each file sits, by place key and path, in `folio-boards.json`
/// beside the Tray's lists, read and written on `ShelfDisk.queue` a second after the last
/// change; never UserDefaults. A board keeps spots only once you move something: until then
/// (and after Tidy Up) it lays itself out in rows.
@MainActor
final class FolioBoards: ObservableObject {
    static let shared = FolioBoards()
    @Published private(set) var boards: [String: [String: FolioBoardSpot]] = [:]
    private var loaded = false
    private var saveWork: DispatchWorkItem?
    private var savesDisabled = false
    private let file = FolioStorage.url("folio-boards.json")

    init() {
        let file = self.file
        ShelfDisk.queue.async {
            let saved = FolioStorage.read([String: [String: FolioBoardSpot]].self, from: file) ?? [:]
            Task { @MainActor [weak self, saved] in
                guard let self else { return }
                // Anything moved while the boards loaded wins.
                self.boards = saved.merging(self.boards) { _, new in new }
                self.loaded = true
            }
        }
    }

    func board(_ key: String) -> [String: FolioBoardSpot] { boards[key] ?? [:] }

    /// Pins every spot of a board (after a move, a resize or bringing one to the front).
    func set(_ key: String, _ spots: [String: FolioBoardSpot]) {
        guard boards[key] != spots else { return }
        boards[key] = spots.isEmpty ? nil : spots
        scheduleSave()
    }

    /// Tidy Up: forgets every spot, so the board lays itself out in rows again.
    func tidy(_ key: String) { forget(key) }

    /// A board whose place is gone (a removed basket or watched folder).
    func forget(_ key: String) {
        guard boards[key] != nil else { return }
        boards[key] = nil
        scheduleSave()
    }

    private func scheduleSave() {
        guard !savesDisabled else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        guard loaded, !savesDisabled else { scheduleSave(); return }
        let boards = self.boards, file = self.file
        ShelfDisk.queue.async { FolioStorage.write(boards, to: file) }
    }

#if DEBUG
    /// Check renders: these boards, never saved.
    func setPreview(_ boards: [String: [String: FolioBoardSpot]]) {
        savesDisabled = true
        saveWork?.cancel()
        self.boards = boards
    }
#endif
}

/// A move or resize in progress on a board.
struct FolioBoardGesture: Equatable {
    var path: String
    var delta: CGSize
    var resizing: Bool
}

/// Board: the place's files laid out by hand. Drag a picture anywhere, pull its corner to resize
/// it, click to select it and bring it to the front; Tidy Up (in the header) lays it out again.
/// Only the pieces near what shows are drawn, however many there are.
struct FolioBoardCanvas: View {
    let key: String
    /// Every file the place holds, so a search's narrowed board keeps the others' spots.
    let paths: Set<String>
    let entries: [FolioEntry]
    @Binding var isDropTargeted: Bool
    let drop: ([NSItemProvider]) -> Bool
    let select: (FolioEntry, NSEvent.ModifierFlags) -> Void
    let clear: () -> Void
    let open: (FolioEntry) -> Void
    @ObservedObject var boards = FolioBoards.shared
    @ObservedObject var theme = ThemeStore.shared
    @State var gesture: FolioBoardGesture?
    /// The scrolled-to corner, in steps, so scrolling seldom redraws.
    @State var corner = CGPoint.zero
    @State var space = UUID()

    var body: some View {
        GeometryReader { proxy in
            let paths = entries.map { $0.item.url.standardizedFileURL.path }
            let aspects = entries.map(FolioFileGrid.aspect)
            let spots = FolioBoardLayout.complete(boards.board(key), paths: paths, aspects: aspects, width: Double(proxy.size.width))
            let frames = spots.indices.map { liveFrame(spots[$0], path: paths[$0], aspect: aspects[$0]) }
            let extent = FolioBoardLayout.extent(frames, atLeast: proxy.size)
            let shown = drawn(frames, spots: spots, size: proxy.size)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    FolioBoardBackdrop(size: extent)
                        .onTapGesture(perform: clear)
                        .background(GeometryReader { inner in
                            Color.clear.preference(key: FolioBoardOffset.self, value: inner.frame(in: .named(space)).origin)
                        })
                    ForEach(shown) { piece in
                        let index = piece.index, entry = entries[index]
                        FolioBoardPiece(entry: entry, preview: entry.store.previews[entry.id],
                                        isSelected: entry.store.selectedIDs.contains(entry.id),
                                        isOffline: entry.store.offlineIDs.contains(entry.id), isBusy: entry.store.busyItemIDs.contains(entry.id),
                                        isLiked: FolioIndex.shared.isLiked(entry.item.url), space: space,
                                        changed: { delta, resizing in gesture = FolioBoardGesture(path: paths[index], delta: delta, resizing: resizing) },
                                        ended: { delta, resizing in finish(index, delta: delta, resizing: resizing, spots: spots, paths: paths, aspects: aspects) },
                                        tapped: { tap(index, spots: spots, paths: paths) },
                                        front: { bringToFront(index, spots: spots, paths: paths) },
                                        open: { open(entry) })
                            .frame(width: frames[index].width, height: frames[index].height)
                            .offset(x: frames[index].minX, y: frames[index].minY)
                            .zIndex(gesture?.path == paths[index] ? 1_000_000 : spots[index].z)
                    }
                }
                .frame(width: extent.width, height: extent.height, alignment: .topLeading)
            }
            .coordinateSpace(name: space)
            .onPreferenceChange(FolioBoardOffset.self) { origin in
                let step: CGFloat = 100
                let next = CGPoint(x: (max(0, -origin.x) / step).rounded(.down) * step, y: (max(0, -origin.y) / step).rounded(.down) * step)
                if next != corner { corner = next }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.notch.accent, lineWidth: 2).opacity(isDropTargeted ? 1 : 0)
            }
            .onDrop(of: FolioDrops.types, isTargeted: $isDropTargeted, perform: drop)
            .animation(theme.reduceMotion ? nil : Design.spring(), value: boards.board(key))
        }
    }

    /// A spot's frame, with the drag or resize in progress.
    private func liveFrame(_ spot: FolioBoardSpot, path: String, aspect: CGFloat) -> CGRect {
        guard let gesture, gesture.path == path else { return spot.frame(aspect: aspect) }
        let live = gesture.resizing ? FolioBoardLayout.resized(spot, by: gesture.delta, aspect: aspect) : FolioBoardLayout.moved(spot, by: gesture.delta)
        return live.frame(aspect: aspect)
    }

    /// The pieces within a few hundred points of what shows, lowest first.
    private func drawn(_ frames: [CGRect], spots: [FolioBoardSpot], size: CGSize) -> [FolioShownTile] {
        let window = CGRect(origin: corner, size: size).insetBy(dx: -260, dy: -260)
        let indices = FolioVisible.indices(frames, in: window).filter { entries.indices.contains($0) }
        return indices.sorted { spots[$0].z < spots[$1].z }.map { FolioShownTile(index: $0, id: entries[$0].id) }
    }

    private func finish(_ index: Int, delta: CGSize, resizing: Bool, spots: [FolioBoardSpot], paths: [String], aspects: [CGFloat]) {
        gesture = nil
        var spot = resizing ? FolioBoardLayout.resized(spots[index], by: delta, aspect: aspects[index]) : FolioBoardLayout.moved(spots[index], by: delta)
        spot.z = FolioBoardLayout.front(spots)
        pin(index, spot, spots: spots, paths: paths)
    }

    private func tap(_ index: Int, spots: [FolioBoardSpot], paths: [String]) {
        select(entries[index], NSEvent.modifierFlags)
        bringToFront(index, spots: spots, paths: paths)
    }

    private func bringToFront(_ index: Int, spots: [FolioBoardSpot], paths: [String]) {
        guard spots[index].z < spots.map(\.z).max() ?? 0 || boards.board(key)[paths[index]] == nil else { return }
        var spot = spots[index]
        spot.z = FolioBoardLayout.front(spots)
        pin(index, spot, spots: spots, paths: paths)
    }

    /// Keeps every spot as it shows now (so new files no longer reflow the ones you placed), with
    /// this one changed; spots of files the place no longer holds go.
    private func pin(_ index: Int, _ spot: FolioBoardSpot, spots: [FolioBoardSpot], paths: [String]) {
        var all = boards.board(key).filter { self.paths.contains($0.key) }
        for (path, current) in zip(paths, spots) { all[path] = current }
        all[paths[index]] = spot
        // Undo-free and instant: the piece is already where the pointer left it.
        var plain = Transaction()
        plain.disablesAnimations = true
        withTransaction(plain) { boards.set(key, all) }
    }
}

/// The board's surface: a faint dot grid to lay things out on.
private struct FolioBoardBackdrop: View {
    let size: CGSize

    var body: some View {
        Canvas { context, canvas in
            let step: CGFloat = 24
            var dots = Path()
            var y: CGFloat = step / 2
            while y < canvas.height {
                var x: CGFloat = step / 2
                while x < canvas.width {
                    dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(.primary.opacity(0.11)))
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }
}

/// One file on a board: its picture whole (other files a card), a ring when selected, and a
/// corner to pull while hovered or selected. Dragging moves it; a double-click opens it.
@MainActor
private struct FolioBoardPiece: View {
    let entry: FolioEntry
    let preview: TrayPreview?
    let isSelected: Bool
    let isOffline: Bool
    let isBusy: Bool
    let isLiked: Bool
    let space: UUID
    let changed: (CGSize, Bool) -> Void
    let ended: (CGSize, Bool) -> Void
    let tapped: () -> Void
    let front: () -> Void
    let open: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            if let preview, preview.isContent {
                // Filling the tile, never widening it (a clamped shape crops the picture).
                Color.clear.overlay { Image(nsImage: preview.image).resizable().interpolation(.high).scaledToFill() }
            } else {
                Color.primary.opacity(0.09)
                VStack(spacing: 2) {
                    if let preview {
                        Image(nsImage: preview.image).resizable().interpolation(.high).scaledToFit().frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "doc").font(.system(size: 18, weight: .light)).foregroundStyle(.tertiary)
                    }
                    Text(entry.item.displayName).font(.system(size: 8.5, weight: .medium)).lineLimit(2).truncationMode(.middle)
                        .multilineTextAlignment(.center).padding(.horizontal, 3)
                }
            }
            if isBusy {
                Color.black.opacity(0.45)
                ProgressView().controlSize(.small)
            }
        }
        .clipShape(corner)
        .overlay { corner.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        .saturation(isOffline ? 0 : 1)
        .opacity(isOffline ? 0.45 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.notch.accent, lineWidth: 2)
                .padding(-2.5)
                .opacity(isSelected ? 1 : 0)
        }
        .overlay(alignment: .bottomLeading) {
            if isLiked {
                Image(systemName: "heart.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(Color.pink)
                    .frame(width: 13, height: 13).background(Color.black.opacity(0.45), in: Circle()).padding(3)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(corner)
        .gesture(TapGesture(count: 2).onEnded(open).exclusively(before: TapGesture().onEnded(tapped)))
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
            .onChanged { changed($0.translation, false) }
            .onEnded { ended($0.translation, false) })
        .overlay(alignment: .bottomTrailing) {
            if hovering || isSelected {
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(theme.notch.accent, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .padding(-3)
                    .contentShape(Rectangle().inset(by: -5))
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
                        .onChanged { changed($0.translation, true) }
                        .onEnded { ended($0.translation, true) })
                    .help("Drag to resize")
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Bring to Front", action: front)
            Divider()
            let store = entry.store
            ShelfItemMenu(item: entry.item, store: store, isSelected: isSelected, isOffline: isOffline, isBusy: isBusy)
        }
        .help(entry.item.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(entry.item.name)
    }
}

/// Where a board's content sits in its scroll view.
struct FolioBoardOffset: PreferenceKey {
    static let defaultValue = CGPoint.zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}
