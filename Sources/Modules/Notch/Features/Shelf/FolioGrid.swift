import SwiftUI
import UniformTypeIdentifiers

/// The Folio page's grid: justified rows of the place's files (`FolioRows`), each picture whole
/// at its own shape, or columns (`FolioColumns`), each picture at its own height, from the Tray's
/// thumbnails (made off the main thread, cached and bounded). Only tiles near the visible part
/// are drawn. Click, ⌘-click and ⇧-click select; dragging carries the selection; anything
/// dropped here goes to `drop`.
struct FolioFileGrid: View {
    let entries: [FolioEntry]
    @Binding var isDropTargeted: Bool
    let drop: ([NSItemProvider]) -> Bool
    let select: (FolioEntry, NSEvent.ModifierFlags) -> Void
    let clear: () -> Void
    /// The page's letters (T, N, L) and Return, while a tile has the keys.
    var keys: ((NSEvent) -> Bool)? = nil
    /// A double-click: the full-size viewer.
    var open: ((FolioEntry) -> Void)? = nil
    /// Columns (masonry) instead of justified rows.
    var columns = false
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let aspects = entries.map(Self.aspect)
        let masonry = columns
        FolioLaidOutScroll(ids: entries.map(\.id), layout: { width in
            Self.layout(aspects: aspects, width: width, columns: masonry)
        }, clear: clear) { index in
            let entry = entries[index], store = entry.store, id = entry.id
            FolioFileTile(entry: entry, preview: store.previews[id], info: store.info[id],
                          isSelected: store.selectedIDs.contains(id), isOffline: store.offlineIDs.contains(id),
                          isBusy: store.busyItemIDs.contains(id), isLiked: FolioIndex.shared.isLiked(entry.item.url),
                          select: select, keys: keys, open: open)
        }
        .background {
            shape.fill(theme.notch.accent.opacity(isDropTargeted ? 0.08 : 0))
                .overlay { shape.strokeBorder(theme.notch.accent, lineWidth: 2).opacity(isDropTargeted ? 1 : 0) }
        }
        .animation(Design.hoverAnimation, value: isDropTargeted)
        .onDrop(of: FolioDrops.types, isTargeted: $isDropTargeted, perform: drop)
    }

    private static func layout(aspects: [CGFloat], width: CGFloat, columns: Bool) -> (frames: [CGRect], height: CGFloat) {
        let gap = FolioLaidOutScroll<EmptyView>.gap
        if columns {
            let column: CGFloat = width < 320 ? 72 : 86
            return FolioColumns.layout(aspects: aspects, width: width, column: column, gap: gap)
        }
        let target: CGFloat = width < 320 ? 64 : 76
        return FolioRows.layout(aspects: aspects, width: width, target: target, gap: gap)
    }

    /// Width over height: a content thumbnail's own shape, else a square card.
    static func aspect(_ entry: FolioEntry) -> CGFloat {
        guard let preview = entry.store.previews[entry.id] else { return 1 }
        guard preview.isContent, preview.image.size.height > 0 else { return 1 }
        return preview.image.size.width / preview.image.size.height
    }
}

/// Justified rows (the clipboard's grid), through `FolioLaidOutScroll`.
struct FolioRowsScroll<Tile: View>: View {
    let ids: [UUID]
    let aspects: [CGFloat]
    let clear: () -> Void
    @ViewBuilder let tile: (Int) -> Tile

    var body: some View {
        let aspects = self.aspects
        FolioLaidOutScroll(ids: ids, layout: { width in
            let target: CGFloat = width < 320 ? 64 : 76
            return FolioRows.layout(aspects: aspects, width: width, target: target, gap: FolioLaidOutScroll<EmptyView>.gap)
        }, clear: clear, tile: tile)
    }
}

/// Tiles at laid-out frames inside a vertical scroll view, drawing only those within a screen of
/// the visible part (the scroll position is read in steps, so scrolling seldom redraws). A click
/// between tiles calls `clear`, and a row cut by the bottom edge fades out.
struct FolioLaidOutScroll<Tile: View>: View {
    let ids: [UUID]
    let layout: (CGFloat) -> (frames: [CGRect], height: CGFloat)
    let clear: () -> Void
    @ViewBuilder let tile: (Int) -> Tile
    /// How far down the content is scrolled, in steps of `step`.
    @State private var band = 0
    @State private var space = UUID()

    static var gap: CGFloat { 6 }
    private static var step: CGFloat { 120 }

    var body: some View {
        GeometryReader { proxy in
            // Rows sit 2 pt in, so the selection ring drawn just outside a tile isn't clipped.
            let width = max(1, proxy.size.width - 4)
            let laid = layout(width)
            let shown = visible(laid.frames, in: proxy.size)
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: proxy.size.width, height: max(proxy.size.height, laid.height + 14))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: clear)
                        .background(GeometryReader { inner in
                            Color.clear.preference(key: FolioScrollOffset.self, value: -inner.frame(in: .named(space)).minY)
                        })
                    ForEach(shown) { piece in
                        let frame = laid.frames[piece.index]
                        tile(piece.index)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX + 2, y: frame.minY + 2)
                    }
                }
            }
            .coordinateSpace(name: space)
            .onPreferenceChange(FolioScrollOffset.self) { offset in
                let next = max(0, Int((offset / Self.step).rounded(.down)))
                if next != band { band = next }
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: max(0, 1 - 14 / max(proxy.size.height, 1))),
                                         .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }

    /// The tiles within a screen above and below what shows.
    private func visible(_ frames: [CGRect], in size: CGSize) -> [FolioShownTile] {
        let top = CGFloat(band) * Self.step
        let window = CGRect(x: -20, y: top - size.height, width: size.width + 40, height: size.height * 3 + Self.step)
        return FolioVisible.indices(frames, in: window).filter { ids.indices.contains($0) }.map { FolioShownTile(index: $0, id: ids[$0]) }
    }
}

/// A tile that's drawn: its place in the layout and its file's id.
struct FolioShownTile: Identifiable {
    let index: Int
    let id: UUID
}

/// How far a Folio scroll view's content has moved.
struct FolioScrollOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// One file: pictures, PDFs and video whole at their own shape; other files a card with their
/// icon and name. A liked file wears a heart; hover shows the heart to like it and a remove
/// button, and Option-click likes it too. The right-click menu is the basket's.
@MainActor
private struct FolioFileTile: View {
    let entry: FolioEntry
    let preview: TrayPreview?
    let info: ShelfFileInfo?
    let isSelected: Bool
    let isOffline: Bool
    let isBusy: Bool
    let isLiked: Bool
    let select: (FolioEntry, NSEvent.ModifierFlags) -> Void
    let keys: ((NSEvent) -> Bool)?
    let open: ((FolioEntry) -> Void)?
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.folioRemove) private var remove
    @State private var hovering = false

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack {
            if let preview, preview.isContent {
                // Filling the tile, never widening it (a clamped shape crops the picture).
                Color.clear.overlay { Image(nsImage: preview.image).resizable().interpolation(.high).scaledToFill() }
            } else {
                Color.primary.opacity(0.07)
                VStack(spacing: 2) {
                    if let preview {
                        Image(nsImage: preview.image).resizable().interpolation(.high).scaledToFit().frame(width: 24, height: 24)
                    } else {
                        Image(systemName: isOffline ? "externaldrive.badge.xmark" : "doc")
                            .font(.system(size: 18, weight: .light)).foregroundStyle(.tertiary)
                    }
                    // Room for two lines under the icon even in the shortest row.
                    Text(entry.item.displayName)
                        .font(.system(size: 8.5, weight: .medium)).lineLimit(2).truncationMode(.middle)
                        .multilineTextAlignment(.center).padding(.horizontal, 3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if isBusy {
                Color.black.opacity(0.45)
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(corner)
        .overlay { corner.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
        .saturation(isOffline ? 0 : 1)
        .opacity(isOffline ? 0.45 : 1)
        .overlay(alignment: .bottomTrailing) { badge }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.notch.accent, lineWidth: 2)
                .padding(-2.5)
                .opacity(isSelected ? 1 : 0)
        }
        .overlay {
            ShelfDragHandle(store: entry.store, item: entry.item, select: { _, modifiers in select(entry, modifiers) }, keys: keys,
                            optionClick: { _ in toggleLike() }, open: open.map { handler -> (ShelfItem) -> Void in { _ in handler(entry) } })
                .accessibilityLabel(entry.item.name)
        }
        .overlay(alignment: .bottomLeading) {
            if isLiked && !hovering {
                Image(systemName: "heart.fill")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(Color.pink)
                    .frame(width: 15, height: 15)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .padding(3)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if hovering && !isBusy {
                Button(action: toggleLike) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(isLiked ? Color.pink : .white)
                        .frame(width: 15, height: 15)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isLiked ? "Unlike (L)" : "Like (L, or Option-click)")
                .padding(3)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering && !isBusy {
                Button { if let remove { remove(entry) } else { entry.store.remove(entry.item) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Color.black.opacity(0.6), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove from \(entry.store.listPhrase) (the file stays where it is)")
                .padding(3)
                .transition(.opacity)
            }
        }
        .scaleEffect(hovering && !theme.reduceMotion ? 1.02 : 1)
        .animation(Design.hoverAnimation, value: hovering)
        .animation(Design.hoverAnimation, value: isSelected)
        .onHover { hovering = $0 }
        .contextMenu {
            ShelfItemMenu(item: entry.item, store: entry.store, isSelected: isSelected, isOffline: isOffline, isBusy: isBusy)
        }
    }

    private func toggleLike() { FolioIndex.shared.toggleLike([entry.item.url]) }

    /// PDFs, video and documents say what they are; pictures speak for themselves.
    @ViewBuilder
    private var badge: some View {
        if preview?.isContent == true, info?.isImage != true,
           let text = TrayFiles.badge(entry.item.name, isDirectory: info?.isDirectory == true) {
            Text(text)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1.5)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(4)
        }
    }
}

// MARK: Clipboard

/// The clipboard's history as cards in the same rows: pictures whole, colours as swatches,
/// text and links as small cards. Clicking one copies it; the right-click menu is the
/// clipboard's own (Add to Tray among it). With the paste queue on, its card (the order, what
/// ⌘V pastes next, and the Accessibility ask) sits above them.
struct FolioClipGrid: View {
    @ObservedObject var monitor: ClipboardMonitor
    let query: String
    @StateObject private var shapes = FolioClipShapes()

    /// The newest clips shown; search reaches the rest.
    static let shownLimit = 120

    var body: some View {
        VStack(spacing: 6) {
            if monitor.queueEnabled { PasteQueueCard(monitor: monitor) }
            clipRows.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var clipRows: some View {
        let matches = monitor.matching(query, favoritesOnly: false)
        let clips = Array(matches.prefix(Self.shownLimit))
        if clips.isEmpty {
            FolioQuietEmpty(symbol: "doc.on.clipboard",
                            title: monitor.entries.isEmpty ? "Nothing copied yet" : "No matching clips",
                            detail: monitor.entries.isEmpty ? "Copied text, links and pictures appear here." : "Clipboard search reads the clips' text and the words in copied pictures.")
        } else {
            VStack(spacing: 4) {
                FolioRowsScroll(ids: clips.map(\.id), aspects: clips.map(aspect), clear: {}) { index in
                    FolioClipTile(clip: clips[index], monitor: monitor) { shapes.set(clips[index].id, $0) }
                }
                if matches.count > clips.count {
                    Text("The newest \(Self.shownLimit) clips · search for older ones")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func aspect(_ clip: ClipboardEntry) -> CGFloat {
        switch clip.kind {
        case .image: return shapes.aspects[clip.id] ?? 4 / 3
        case .color: return 0.8
        default: return 1.45
        }
    }
}

/// Image clips' shapes, learned as their thumbnails load.
@MainActor
final class FolioClipShapes: ObservableObject {
    @Published private(set) var aspects: [UUID: CGFloat] = [:]

    func set(_ id: UUID, _ aspect: CGFloat) {
        guard aspect.isFinite, aspect > 0, abs((aspects[id] ?? 0) - aspect) > 0.01 else { return }
        aspects[id] = aspect
    }
}

private struct FolioClipTile: View {
    let clip: ClipboardEntry
    @ObservedObject var monitor: ClipboardMonitor
    let learned: (CGFloat) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var image: NSImage?
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        let corner = RoundedRectangle(cornerRadius: 6, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(corner)
            .overlay { corner.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
            .overlay {
                if copied {
                    ZStack {
                        corner.fill(.black.opacity(0.45))
                        Label("Copied", systemImage: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if clip.isFavorite {
                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(theme.notch.accent).padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button { ShelfStore.shared.add(clip) } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(Color.black.opacity(0.6), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Add to Tray")
                    .padding(3)
                    .transition(.opacity)
                }
            }
            .scaleEffect(hovering && !theme.reduceMotion ? 1.02 : 1)
            .animation(Design.hoverAnimation, value: hovering)
            .contentShape(corner)
            .onHover { hovering = $0 }
            .onTapGesture { copy() }
            .onDrag { ClipboardActions.dragItem(clip) }
            .contextMenu { ClipMenu(clip: clip, monitor: monitor) }
            .help("Click to copy")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(clip.isImage ? "Copied picture" : clip.preview)
            .task(id: clip.id) {
                guard clip.isImage else { return }
                let size = CGSize(width: 360, height: 260)
                // The cache answers at once; otherwise the image is decoded on the thumbnails' worker.
                var loaded = ClipThumbnails.cached(for: clip, covering: size)
                if loaded == nil { loaded = await ClipThumbnails.image(for: clip, covering: size) }
                guard !Task.isCancelled, let loaded else { return }
                image = loaded
                if loaded.size.height > 0 { learned(loaded.size.width / loaded.size.height) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if clip.isImage {
            if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFill() }
            else { Color.primary.opacity(0.07) }
        } else if let rgb = clip.hexColor {
            Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                .overlay(alignment: .bottomLeading) {
                    Text(clip.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white)
                        .padding(4)
                }
        } else {
            ZStack(alignment: .topLeading) {
                Color.primary.opacity(0.07)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
                        Text(caption).font(.system(size: 8, weight: .semibold)).lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                    Text(text(of: clip))
                        .font(.system(size: 9.5, weight: clip.kind == .link ? .medium : .regular))
                        .lineLimit(clip.kind == .link ? 3 : 4)
                        .multilineTextAlignment(.leading)
                }
                .padding(6)
            }
        }
    }

    private var symbol: String {
        switch clip.kind {
        case .link: return "link"
        case .file: return "doc"
        case .color: return "paintpalette"
        default: return clip.isSnippet ? "text.quote" : "text.alignleft"
        }
    }

    /// Where it came from, or what it is.
    private var caption: String {
        if clip.kind == .link, let host = URL(string: clip.text.trimmingCharacters(in: .whitespacesAndNewlines))?.host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return clip.sourceName.isEmpty ? (clip.kind == .file ? "File" : "Text") : clip.sourceName
    }

    private func text(of clip: ClipboardEntry) -> String {
        if clip.kind == .file { return clip.fileURLs.map(\.lastPathComponent).joined(separator: ", ") }
        return clip.preview
    }

    private func copy() {
        monitor.copyToPasteboard(clip)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
    }
}
