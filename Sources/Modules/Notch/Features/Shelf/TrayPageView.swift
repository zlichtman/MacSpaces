import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The Nook's Folio page, laid out like the Folio app: a slim sidebar of places with counts
/// (All Items, the Tray as the inbox, the clipboard's history, smart folders, each basket as a
/// collection, then each watched folder's new files), justified rows of thumbnails that keep every picture whole, and a details
/// column for the selection. One search covers every list (names, kinds, the words in pictures
/// and PDFs, what photos show), and each place counts its matches. Files dropped on the grid go
/// to the place showing (the Tray for All Items and smart folders); files dropped on a place in
/// the sidebar go there. Return or a double-click shows the selection full size (`FolioViewer`).
struct TrayPageView: View {
    @ObservedObject var tray: ShelfStore
    @Binding var isDropTargeted: Bool
    /// Nil until something starts the history: the page starts it only when Clipboard is asked for.
    @State private var clipboard: ClipboardMonitor?
    @ObservedObject private var baskets = BasketWindowController.shared
    @ObservedObject private var watched = FolioWatchedFolders.shared
    @ObservedObject private var library = FolioIndex.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var trashBin = FolioTrash.shared
    @ObservedObject private var swatches = FolioSwatches.shared
    @ObservedObject private var links = FolioLinks.shared
    @StateObject private var changes = FolioStoreChanges()
    @ObservedObject private var tools = FileToolsModel.shared
    /// T and N ask the details column for its tag field or note.
    @StateObject private var fields = FolioFieldRequest()
    @State private var place: FolioPlace
    @State private var query: String
    /// Find Similar's picture, while its matches show.
    @State private var similarTo: URL?
    /// The file the full-size viewer shows, while it's open.
    @State private var viewing: UUID?
    /// Rows, Columns, List, Infinity or Board, for every place that shows files.
    @AppStorage(WidgetOptions.Keys.folioView) private var savedView: FolioViewMode = .rows
    /// A view the check renders start in, until one is chosen.
    @State private var forcedView: FolioViewMode?

    /// `place`, `query`, `similarTo`, `viewing` and `view` start the page there (check renders).
    @MainActor
    init(tray: ShelfStore, isDropTargeted: Binding<Bool>, clipboard: ClipboardMonitor?? = nil,
         place: FolioPlace = .all, query: String = "", similarTo: URL? = nil, viewing: UUID? = nil, view: FolioViewMode? = nil) {
        self.tray = tray
        self._isDropTargeted = isDropTargeted
        typealias Start = (clipboard: ClipboardMonitor?, place: FolioPlace, query: String, similarTo: URL?, viewing: UUID?, view: FolioViewMode?)
        let given: Start = (clipboard ?? AppServices.shared.clipboardIfLoaded, place, query, similarTo, viewing, view)
        #if DEBUG
        // Website captures open the Nook's page on a place, a search, the viewer or a view.
        let start: Start = Self.previewStart.map { ($0.clipboard, $0.place, $0.query, nil, $0.viewing, $0.view) } ?? given
        #else
        let start = given
        #endif
        self._clipboard = State(initialValue: start.clipboard)
        self._place = State(initialValue: start.place)
        self._query = State(initialValue: start.query)
        self._similarTo = State(initialValue: start.similarTo)
        self._viewing = State(initialValue: start.viewing)
        self._forcedView = State(initialValue: start.view)
    }

    /// A place asked for (`NotchViewModel.pendingFolioPlace`), posted with the place: an open
    /// page isn't rebuilt for a new request, so it moves there itself.
    static let placeRequested = Notification.Name("TrayPageView.placeRequested")

    #if DEBUG
    /// Website captures: where the Nook's Folio page starts, and the clipboard it shows.
    struct PreviewStart {
        var clipboard: ClipboardMonitor?
        var place: FolioPlace = .all
        var query = ""
        var viewing: UUID?
        var view: FolioViewMode?
    }
    @MainActor static var previewStart: PreviewStart?
    /// Website captures type into the open page's search: post the text so far.
    static let previewQuery = Notification.Name("TrayPageView.previewQuery")
    #endif

    var body: some View {
        let lists = baskets.allStores()
        let watchedLists = watched.allStores()
        // Every list after the Tray: the baskets, then watched folders.
        let others = lists.map(\.store) + watchedLists.map(\.store)
        // Find Similar: the picture, then its look-alikes nearest first.
        let ranked = similarTo.map { picture in
            [picture.standardizedFileURL.path] + library.similar(to: picture, among: ([tray] + others).flatMap { $0.items.map(\.url) })
        }
        let filter = FolioFilter(terms: FolioIndex.terms(query), paths: ranked.map(Set.init))
        let shown = Self.exists(place, lists: lists, watched: watchedLists, clipboard: clipboard) ? place : .all
        let entries = Self.ordered(FolioPlaces.entries(shown, tray: tray, baskets: others, filter: filter, library: library), by: ranked)
        let stores = Self.stores(of: shown, tray: tray, baskets: others)
        let active = stores.first { !$0.selectedIDs.isEmpty }
        // The place's own list (the Tray, a basket or a watched folder, which Clear All empties).
        let own = Self.ownList(shown, stores: stores)
        // Where drops and Paste go: the Tray or a basket itself; the Tray for everything else.
        let dropStore = shown.isWatched ? tray : own ?? tray
        let viewed = !shown.showsFiles ? nil : viewing.flatMap { id in entries.firstIndex { $0.id == id } }
        let mode = forcedView ?? savedView
        ZStack {
            HStack(spacing: 0) {
                FolioSidebar(place: shown, select: choose, query: $query, similarTo: $similarTo, tray: tray, lists: lists,
                             watched: watchedLists, clipboard: clipboard, filter: filter, clipQuery: similarTo == nil ? query : nil)
                    .frame(width: 132)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5).padding(.vertical, 2)
                VStack(spacing: 6) {
                    FolioHeader(place: shown, title: title(of: shown, lists: lists), entries: entries, filter: filter, own: own, dropStore: dropStore,
                                stores: stores, active: active, clipboard: clipboard, select: selectAll,
                                view: shown.showsFiles ? viewChoice : nil, saved: choose)
                    Group {
                        if shown == .colors {
                            FolioColorsGrid(terms: filter.terms, isDropTargeted: $isDropTargeted, drop: dropHandler(shown, into: dropStore))
                        } else if shown == .links {
                            FolioLinksGrid(terms: filter.terms, isDropTargeted: $isDropTargeted, drop: dropHandler(shown, into: dropStore))
                        } else if shown == .clipboard, let clipboard {
                            FolioClipGrid(monitor: clipboard, query: similarTo == nil ? query : "")
                        } else if shown == .tools {
                            FileToolsView(model: tools, query: similarTo == nil ? query : "")
                        } else if entries.isEmpty && filter.isActive && stores.contains(where: { !$0.items.isEmpty }) || entries.isEmpty && similarTo != nil {
                            noMatches(filter: filter, lists: lists, watched: watchedLists)
                        } else if entries.isEmpty, let empty = emptyText(shown) {
                            FolioQuietEmpty(symbol: empty.symbol, title: empty.title, detail: empty.detail)
                        } else if entries.isEmpty {
                            FolioDropEmpty(store: dropStore, isDropTargeted: $isDropTargeted, saved: choose)
                        } else {
                            FolioFileViews(mode: mode, boardKey: shown.key, boardPaths: mode == .board ? Self.paths(of: shown, tray: tray, others: others) : [],
                                           entries: entries, isDropTargeted: $isDropTargeted, drop: dropHandler(shown, into: dropStore),
                                           select: { select($0, modifiers: $1, among: entries) },
                                           clear: { stores.forEach { $0.select(nil) } }, keys: key, open: { view($0.id) })
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    FolioStatusLine(stores: stores, caption: shown == .trash ? FolioTrash.help : nil, collectionUndo: collectionUndo(shown))
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity)
                if let active, shown.showsFiles {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5).padding(.vertical, 2).padding(.leading, 10)
                    FolioDetails(store: active, request: fields) { tag in similarTo = nil; query = tag }
                        .frame(width: 148)
                        .padding(.leading, 10)
                        .transition(.opacity)
                }
            }
            .accessibilityHidden(viewed != nil)
            // A file that left the place closes the viewer, so it never reopens on its own.
            .onChange(of: viewed == nil) { closed in if closed { viewing = nil } }
            if let viewed {
                FolioViewer(entries: entries, index: viewed, page: { offset in
                    let next = entries[viewed + offset]
                    select(next, modifiers: [], among: entries)
                    viewing = next.id
                }, close: { withAnimation(Design.spring()) { viewing = nil } })
                .transition(theme.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(1)
            }
        }
        .environment(\.folioFindSimilar) { url in
            query = ""; similarTo = url
            choose(.all)
        }
        .environment(\.folioRemove) { entry in
            if entry.store.isTrash { entry.store.remove(entry.item) } else { entry.store.trash([entry.item]) }
        }
        .environment(\.folioTrashes, true)
        .environment(\.folioSaveColors) { url in
            Task { @MainActor in if await FolioSwatches.shared.saveColors(from: url) > 0 { choose(.colors) } }
        }
        .onAppear {
            baskets.loadCatalog()
            changes.watch([tray] + others + [trashBin.store])
            ([tray] + others + [trashBin.store]).forEach { $0.pruneMissingItems() }
            trashBin.purgeExpired()
        }
        .onReceive(baskets.$baskets) { _ in changes.watch(watchedStores) }
        .onReceive(watched.$folders) { _ in changes.watch(watchedStores) }
        .onChange(of: query) { if !$0.isEmpty { similarTo = nil } }
        // File Tools asked for from elsewhere while the page is open (`FileToolsModel.open`).
        .onReceive(tools.$request.dropFirst()) { _ in choose(.tools) }
        // A place asked for while the page is open (the Clipboard widget or App Intent). Asking
        // for Clipboard is what starts its history, as opening on it does.
        .onReceive(NotificationCenter.default.publisher(for: Self.placeRequested)) { note in
            guard let next = note.object as? FolioPlace else { return }
            if next == .clipboard, clipboard == nil { clipboard = AppServices.shared.clipboard }
            choose(next)
        }
        .modifier(PreviewQuery(query: $query))
    }

    /// Every list the page shows changes from (the Trash among them).
    private var watchedStores: [ShelfStore] {
        [tray] + baskets.allStores().map(\.store) + watched.allStores().map(\.store) + [trashBin.store]
    }

    /// Every loaded list, for clearing selections: one list's selection at a time.
    private var loadedStores: [ShelfStore] {
        [tray] + baskets.loadedStores + watched.loadedStores + [trashBin.store]
    }

    /// Colors' or Links' Undo bar after a removal there.
    private func collectionUndo(_ place: FolioPlace) -> FolioCollectionUndo? {
        if place == .colors, let text = swatches.undoText { return FolioCollectionUndo(text: text) { FolioSwatches.shared.undo() } }
        if place == .links, let text = links.undoText { return FolioCollectionUndo(text: text) { FolioLinks.shared.undo() } }
        return nil
    }

    /// What a drop on the files does: the Trash takes nothing dropped; elsewhere it's added.
    private func dropHandler(_ place: FolioPlace, into store: ShelfStore) -> ([NSItemProvider]) -> Bool {
        if place == .trash { return { _ in false } }
        return { providers in FolioDrops.handle(providers, into: store, saved: choose) }
    }

    /// The view control's choice: saved, and it replaces a check render's starting view.
    private var viewChoice: Binding<FolioViewMode> {
        Binding(get: { forcedView ?? savedView }, set: { next in
            forcedView = nil
            withAnimation(theme.reduceMotion ? nil : Design.spring()) { savedView = next }
        })
    }

    /// Every file a place holds, unfiltered (a board keeps the spots of files a search hides).
    private static func paths(of place: FolioPlace, tray: ShelfStore, others: [ShelfStore]) -> Set<String> {
        let all = FolioPlaces.entries(place, tray: tray, baskets: others, filter: FolioFilter(), library: FolioIndex.shared)
        return Set(all.map { $0.item.url.standardizedFileURL.path })
    }

    /// Opens the full-size viewer on this file.
    private func view(_ id: UUID) {
        withAnimation(Design.spring()) { viewing = id }
    }

    private func choose(_ next: FolioPlace) {
        viewing = nil
        guard next != place else { return }
        // A selection in a place that's no longer showing would take the toolbar's actions.
        loadedStores.forEach { $0.select(nil) }
        place = next
    }

    /// The lists behind a place.
    private static func stores(of place: FolioPlace, tray: ShelfStore, baskets: [ShelfStore]) -> [ShelfStore] {
        switch place {
        case .clipboard, .tools, .colors, .links: return []
        case .tray: return [tray]
        case .trash: return [FolioTrash.shared.store]
        case .basket(let id): return baskets.filter { $0.listID == id }
        case .watched(let id): return baskets.filter { $0.watchedID == id }
        case .all, .smart: return [tray] + baskets
        }
    }

    /// Entries in Find Similar's order, when it's showing.
    private static func ordered(_ entries: [FolioEntry], by ranked: [String]?) -> [FolioEntry] {
        guard let ranked else { return entries }
        let rank = Dictionary(ranked.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return entries.sorted { rank[$0.item.url.standardizedFileURL.path, default: .max] < rank[$1.item.url.standardizedFileURL.path, default: .max] }
    }

    private static func ownList(_ place: FolioPlace, stores: [ShelfStore]) -> ShelfStore? {
        switch place {
        case .tray, .basket, .watched, .trash: return stores.first
        case .all, .smart, .clipboard, .tools, .colors, .links: return nil
        }
    }

    /// A removed basket or watched folder, or a clipboard that's gone, falls back to All Items.
    private static func exists(_ place: FolioPlace, lists: [(basket: FileBasket, store: ShelfStore)],
                               watched: [(folder: WatchedFolder, store: ShelfStore)], clipboard: ClipboardMonitor?) -> Bool {
        switch place {
        case .basket(let id): return lists.contains { $0.basket.id == id }
        case .watched(let id): return watched.contains { $0.folder.id == id }
        case .clipboard: return clipboard != nil
        default: return true
        }
    }

    private func title(of place: FolioPlace, lists: [(basket: FileBasket, store: ShelfStore)]) -> String {
        switch place {
        case .all: return "All Items"
        case .tray: return "Tray"
        case .clipboard: return "Clipboard"
        case .tools: return "File Tools"
        case .trash: return "Trash"
        case .colors: return "Colors"
        case .links: return "Links"
        case .smart(let folder): return folder.title
        case .basket(let id): return lists.first { $0.basket.id == id }?.basket.name ?? "Basket"
        case .watched(let id): return watched.folders.first { $0.id == id }?.name ?? "Watched"
        }
    }

    private func emptyText(_ place: FolioPlace) -> (symbol: String, title: String, detail: String)? {
        if place == .trash {
            return ("trash", "The Trash is empty", "Removed items wait here for 30 days. Only references: no file on disk is ever moved or deleted.")
        }
        if case .watched(let id) = place {
            let name = watched.folders.first { $0.id == id }?.name ?? "this folder"
            return ("eye", "Nothing new yet", "Files that arrive in \(name) appear here. They stay where they are.")
        }
        guard case .smart(let folder) = place else { return nil }
        switch folder {
        case .liked: return ("heart", "Nothing liked yet", "Press L or Option-click a picture to like it.")
        case .pictures: return ("photo", "No pictures yet", "Pictures in the Tray and your baskets gather here.")
        case .pdfs: return ("doc.richtext", "No PDFs yet", "PDFs in the Tray and your baskets gather here.")
        case .withText: return ("text.viewfinder", "Nothing with text yet", "Files whose words Folio has read gather here.")
        }
    }

    /// A click on a tile: selects in that file's list (one list's selection at a time), and a
    /// Shift range follows the grid's order.
    private func select(_ entry: FolioEntry, modifiers: NSEvent.ModifierFlags, among entries: [FolioEntry]) {
        let store = entry.store
        loadedStores.filter { $0 !== store }.forEach { $0.select(nil) }
        if modifiers.contains(.shift), let anchor = store.selectedItemID,
           let from = entries.firstIndex(where: { $0.id == anchor }), let to = entries.firstIndex(where: { $0.id == entry.id }) {
            let range = entries[min(from, to)...max(from, to)].filter { $0.store === store }.map(\.id)
            store.setSelection(store.selectedIDs.union(range), focus: entry.id)
        } else {
            store.select(entry.item, extending: modifiers.contains(.command))
        }
    }

    /// The page's keys for the selection, while a tile has the keys: Return views it full size,
    /// T adds a tag, N writes the note, L likes it (or unlikes it), Delete moves it to the Trash
    /// (or, in the Trash, lets it go).
    private func key(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased(),
              let active = loadedStores.first(where: { !$0.selectedIDs.isEmpty }) else { return false }
        if event.keyCode == 51 || event.keyCode == 117 {
            if active.isTrash { active.removeSelected() } else { active.trashSelected() }
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            guard let item = active.selectedItem ?? active.selectedItems.first, !active.offlineIDs.contains(item.id) else { return false }
            view(item.id)
            return true
        }
        switch key {
        case "l": library.toggleLike(active.selectedItems.map(\.url))
        case "t": fields.ask(.tag)
        case "n": fields.ask(.note)
        default: return false
        }
        return true
    }

    private func selectAll(_ entries: [FolioEntry]) {
        guard let store = entries.first?.store, entries.allSatisfy({ $0.store === store }) else { return }
        store.setSelection(Set(entries.map(\.id)), focus: entries.first?.id)
    }

    /// Nothing here matches: says which places do, one click away.
    private func noMatches(filter: FolioFilter, lists: [(basket: FileBasket, store: ShelfStore)],
                           watched: [(folder: WatchedFolder, store: ShelfStore)]) -> some View {
        let elsewhere: [(FolioPlace, String, Int)] = ([(FolioPlace.tray, "Tray", tray)] + lists.map { (.basket($0.basket.id), $0.basket.name, $0.store) }
                                                      + watched.map { (.watched($0.folder.id), $0.folder.name, $0.store) })
            .filter { $0.0 != place }
            .map { ($0.0, $0.1, filter.matches(in: $0.2, library)?.count ?? 0) }
            .filter { $0.2 > 0 }
        return VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
            Text(filter.paths != nil ? "No similar pictures here" : "Nothing here matches \u{201C}\(query)\u{201D}")
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if elsewhere.isEmpty {
                Text("Search reads names, your tags and notes, the words in pictures and PDFs, and what photos show.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                HStack(spacing: 6) {
                    // Keyed by the place: two baskets can share a name.
                    ForEach(elsewhere, id: \.0) { entry in
                        Button("\(entry.2) in \(entry.1)") { choose(entry.0) }
                            .buttonStyle(WidgetChipStyle(height: 24))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

/// An Undo bar for Colors or Links.
struct FolioCollectionUndo {
    let text: String
    let undo: () -> Void
}

/// Republishes every list's changes, so places that combine lists stay current.
@MainActor
final class FolioStoreChanges: ObservableObject {
    private var watched: [ObjectIdentifier: AnyCancellable] = [:]

    func watch(_ stores: [ShelfStore]) {
        let ids = Set(stores.map(ObjectIdentifier.init))
        watched = watched.filter { ids.contains($0.key) }
        for store in stores where watched[ObjectIdentifier(store)] == nil {
            watched[ObjectIdentifier(store)] = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
}

// MARK: Sidebar

/// The places, each with its count (matches while searching), under the search field.
private struct FolioSidebar: View {
    let place: FolioPlace
    let select: (FolioPlace) -> Void
    @Binding var query: String
    @Binding var similarTo: URL?
    @ObservedObject var tray: ShelfStore
    let lists: [(basket: FileBasket, store: ShelfStore)]
    let watched: [(folder: WatchedFolder, store: ShelfStore)]
    let clipboard: ClipboardMonitor?
    let filter: FolioFilter
    /// The clipboard's own search, or nil while Find Similar shows (clips have no pictures to compare).
    let clipQuery: String?
    @ObservedObject private var swatches = FolioSwatches.shared
    @ObservedObject private var links = FolioLinks.shared
    @ObservedObject private var library = FolioIndex.shared
    @ObservedObject private var baskets = BasketWindowController.shared

    var body: some View {
        let stores = [tray] + lists.map(\.store) + watched.map(\.store)
        let unfiltered = FolioFilter()
        VStack(alignment: .leading, spacing: 6) {
            if let similarTo {
                SimilarChip(name: TrayFiles.displayName(similarTo.lastPathComponent)) { self.similarTo = nil }
            } else {
                TraySearchField(text: $query)
            }
            ScrollViewReader { scroller in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 1) {
                    row(.all, "All Items", "square.grid.2x2", count(.all, stores))
                    row(.tray, "Tray", "tray", count(.tray, stores), drop: tray)
                    if let clipboard {
                        FolioClipboardRow(monitor: clipboard, query: clipQuery, selected: place == .clipboard) { select(.clipboard) }
                    }
                    row(.tools, "Tools", "wand.and.stars", 0)
                        .help("File Tools: convert, resize, crop, compress or extract text. Originals stay untouched.")
                    row(.colors, "Colors", "paintpalette", swatches.book.matching(filter.terms).count, drop: tray)
                        .help("Colors: pasted hex codes, the color picker and Save Colors. Click a swatch to copy it.")
                    row(.links, "Links", "link", links.book.matching(filter.terms).count, drop: tray)
                        .help("Links: web addresses you paste or drop, each with its page's title and picture")
                    let smart = FolioSmartFolder.allCases.filter {
                        !FolioPlaces.entries(.smart($0), tray: tray, baskets: Array(stores.dropFirst()), filter: unfiltered, library: library).isEmpty
                    }
                    if !smart.isEmpty {
                        FolioSidebarHeading(title: "Smart Folders")
                        ForEach(smart, id: \.self) { folder in
                            row(.smart(folder), folder.title, folder.symbol, count(.smart(folder), stores))
                        }
                    }
                    FolioSidebarHeading(title: "Baskets") {
                        Button { baskets.create() } label: {
                            Image(systemName: "plus").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 14).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(baskets.baskets.count >= 25)
                        .help("New basket, shown on the desktop")
                    }
                    ForEach(lists, id: \.basket.id) { entry in
                        row(.basket(entry.basket.id), entry.basket.name, "basket", count(.basket(entry.basket.id), stores), drop: entry.store)
                            .contextMenu {
                                Button("Show on Desktop") { baskets.show(entry.basket.id) }
                                Divider()
                                Button("Remove Basket", role: .destructive) { baskets.remove(entry.basket.id) }
                            }
                    }
                    if !watched.isEmpty {
                        FolioSidebarHeading(title: "Watched")
                        ForEach(watched, id: \.folder.id) { entry in
                            row(.watched(entry.folder.id), entry.folder.name, "eye", count(.watched(entry.folder.id), stores))
                                .contextMenu {
                                    Button("Show in Finder") { FolioWatchedFolders.shared.reveal(entry.folder.id) }
                                    Button("Watched Folders Settings") { SettingsWindowController.shared.show(.folio) }
                                    Divider()
                                    Button("Stop Watching", role: .destructive) { FolioWatchedFolders.shared.remove(entry.folder.id) }
                                }
                        }
                    }
                    Spacer(minLength: 8)
                    row(.trash, "Trash", "trash", count(.trash, stores))
                        .help(FolioTrash.help)
                        .contextMenu {
                            Button("Empty Trash", role: .destructive) { FolioTrash.shared.store.removeAll() }
                                .disabled(FolioTrash.shared.store.items.isEmpty)
                        }
                }
                .padding(.bottom, 8)
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                         .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom))
            // A place further down (a watched folder, say) is scrolled into sight when it shows.
            .onAppear { scroller.scrollTo(place, anchor: .center) }
            .onChange(of: place) { scroller.scrollTo($0, anchor: .center) }
            }
        }
    }

    private func count(_ place: FolioPlace, _ stores: [ShelfStore]) -> Int {
        FolioPlaces.entries(place, tray: tray, baskets: Array(stores.dropFirst()), filter: filter, library: library).count
    }

    private func row(_ target: FolioPlace, _ title: String, _ symbol: String, _ count: Int, drop: ShelfStore? = nil) -> some View {
        FolioPlaceRow(title: title, symbol: symbol, count: count, selected: place == target, drop: drop ?? (target == .all ? tray : nil), saved: select) {
            select(target)
        }
        .id(target)
    }
}

/// A section title in the sidebar, with an optional button at its end.
private struct FolioSidebarHeading<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 0) {
            Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.leading, 8).padding(.trailing, 4)
        .padding(.top, 8).padding(.bottom, 1)
    }
}

extension FolioSidebarHeading where Accessory == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// One place: its symbol, name and count. Files dropped on it join its list.
private struct FolioPlaceRow: View {
    let title: String
    let symbol: String
    let count: Int
    let selected: Bool
    let drop: ShelfStore?
    /// Shows the place that took dropped colours or links.
    var saved: ((FolioPlace) -> Void)? = nil
    let action: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: targeted ? "tray.and.arrow.down.fill" : symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected || targeted ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 15)
                Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
                if count > 0 {
                    Text("\(count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(selected ? theme.notch.selected : Color.primary.opacity(hovering ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(theme.notch.accent, lineWidth: 1.5).opacity(targeted ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDrop(of: drop == nil ? [] : FolioDrops.types, isTargeted: $targeted) { providers in
            guard let drop else { return false }
            return FolioDrops.handle(providers, into: drop, saved: saved)
        }
        .accessibilityLabel("\(title), \(count) items")
        .help(drop == nil ? title : "\(title): drop files here to add them")
    }
}

/// The clipboard's place, counting its clips (matches while searching).
private struct FolioClipboardRow: View {
    @ObservedObject var monitor: ClipboardMonitor
    let query: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        FolioPlaceRow(title: "Clipboard", symbol: "doc.on.clipboard",
                      count: query.map { monitor.matching($0, favoritesOnly: false).count } ?? 0,
                      selected: selected, drop: nil, action: action)
    }
}

// MARK: Header

/// The place's name and what it holds, then its actions: Paste and Clear All, or for a
/// selection Quick Look, the file actions, Share, Show in Finder and Remove.
private struct FolioHeader: View {
    let place: FolioPlace
    let title: String
    let entries: [FolioEntry]
    let filter: FolioFilter
    /// The place's own list (Clear All empties it), and where Paste puts things.
    let own: ShelfStore?
    let dropStore: ShelfStore
    let stores: [ShelfStore]
    let active: ShelfStore?
    let clipboard: ClipboardMonitor?
    let select: ([FolioEntry]) -> Void
    /// The view control, for places that show files.
    let view: Binding<FolioViewMode>?
    /// Shows the place that took pasted colours or links.
    let saved: (FolioPlace) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var boards = FolioBoards.shared
    @ObservedObject private var swatches = FolioSwatches.shared
    @ObservedObject private var links = FolioLinks.shared

    var body: some View {
        HStack(spacing: 4) {
            content
            if let view {
                FolioViewSwitch(mode: view)
            }
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private var content: some View {
            if let active {
                let selected = active.selectedItems
                Button { active.select(nil) } label: {
                    HStack(spacing: 4) {
                        Text("\(selected.count) selected").monospacedDigit().fixedSize()
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .help("Deselect (Escape)")
                Spacer(minLength: 4)
                iconButton("Quick Look (Space)", "eye") { active.quickLook() }
                // In the Trash, putting back comes first; file actions wait until it's back.
                if !active.isTrash {
                    FileActionMenu(store: active)
                    ShareLink(items: selected.map(\.url)) { FolioToolbarIcon(symbol: "square.and.arrow.up") }
                        .buttonStyle(PremiumPressButtonStyle())
                        .help("Share or AirDrop")
                }
                iconButton("Show in Finder", "folder") { active.revealInFinder(selected) }
                if active.isTrash {
                    iconButton("Put Back where it came from", "arrow.uturn.backward") { FolioTrash.shared.putBack(selected) }
                    iconButton("Remove from the Trash (Delete). The files stay where they are.", "minus.circle") { active.removeSelected() }
                } else {
                    iconButton("Remove from \(active.listPhrase) (Delete). It waits in the Trash for 30 days; the files stay where they are.", "minus.circle") {
                        active.trashSelected()
                    }
                }
            } else {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(summary).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if place == .colors || place == .links {
                    collectionActions
                } else if place == .clipboard {
                    // No Undo for clips, so clearing is a choice between two named things.
                    if let clipboard, !clipboard.entries.isEmpty {
                        NookMenu {
                            NookMenuRow("Clear Recent Clips") { clipboard.clear(keepingFavorites: true) }
                            NookMenuRow("Clear All, Including Favorites", destructive: true) { clipboard.clear() }
                        } label: { Label("Clear", systemImage: "xmark.circle") }
                        .buttonStyle(WidgetChipStyle(height: 24))
                        .help("Clear the clipboard history")
                        .accessibilityLabel("Clear clipboard history")
                    }
                } else if place != .tools {
                    let single = !entries.isEmpty && entries.allSatisfy { $0.store === entries[0].store }
                    if single {
                        Button("Select All") { select(entries) }
                            .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.notch.accent)
                    }
                    // An empty list offers Paste in its own invitation.
                    if !place.isWatched && place != .trash && (!entries.isEmpty || filter.isActive) {
                        iconButton("Paste copied files, text, links, colors or images (⌘V)", "doc.on.clipboard") { FolioDrops.paste(into: dropStore, saved: saved) }
                            .keyboardShortcut("v")
                    }
                    if view?.wrappedValue == .board, !entries.isEmpty {
                        Button { withAnimation(theme.reduceMotion ? nil : Design.spring()) { FolioBoards.shared.tidy(place.key) } } label: {
                            Label("Tidy Up", systemImage: "wand.and.rays")
                        }
                        .buttonStyle(WidgetChipStyle(height: 24))
                        .disabled(boards.board(place.key).isEmpty)
                        .help("Lay this board out again in rows")
                    }
                    if let store = own, !store.items.isEmpty, store.isTrash {
                        Button { store.removeAll() } label: { Label("Empty Trash", systemImage: "trash.slash") }
                            .buttonStyle(WidgetChipStyle(height: 24))
                            .help("Let go of every reference here. No file on disk is touched, and Undo brings them back.")
                    } else if let store = own, !store.items.isEmpty {
                        Button { store.trashAll() } label: { Label("Clear All", systemImage: "xmark.circle") }
                            .buttonStyle(WidgetChipStyle(height: 24))
                            .help("Move everything in this list to the Trash. Files stay where they are, and Undo brings them back.")
                    }
                }
            }
    }

    private var summary: String {
        if place == .tools { return "Copies go beside the originals" }
        if place == .clipboard {
            let count = clipboard?.entries.count ?? 0
            return count == 1 ? "1 clip" : "\(count) clips"
        }
        if place == .colors {
            let count = swatches.book.matching(filter.terms).count
            if filter.isActive { return count == 1 ? "1 match" : "\(count) matches" }
            return count == 1 ? "1 color" : "\(count) colors"
        }
        if place == .links {
            let count = links.book.matching(filter.terms).count
            if filter.isActive { return count == 1 ? "1 match" : "\(count) matches" }
            return count == 1 ? "1 link" : "\(count) links"
        }
        if filter.isActive { return entries.count == 1 ? "1 match" : "\(entries.count) matches" }
        let bytes = entries.reduce(Int64(0)) { $0 + ($1.store.info[$1.id]?.bytes ?? 0) }
        return TrayFiles.summary(count: entries.count, bytes: bytes)
    }

    /// Colors and Links: Paste (hex codes, a copied colour or web addresses) and Clear All.
    @ViewBuilder
    private var collectionActions: some View {
        let colors = place == .colors
        let help = colors ? "Paste hex codes, a palette or a copied color (⌘V)" : "Paste web addresses (⌘V)"
        iconButton(help, "doc.on.clipboard") { FolioDrops.paste(into: dropStore, saved: saved) }
            .keyboardShortcut("v")
        let empty = colors ? swatches.book.swatches.isEmpty : links.book.links.isEmpty
        if !empty {
            Button {
                if colors { FolioSwatches.shared.removeAll() } else { FolioLinks.shared.removeAll() }
            } label: { Label("Clear All", systemImage: "xmark.circle") }
                .buttonStyle(WidgetChipStyle(height: 24))
                .help(colors ? "Remove every color. Undo brings them back." : "Remove every link. Undo brings them back.")
        }
    }

    private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { FolioToolbarIcon(symbol: symbol) }
            .buttonStyle(PremiumPressButtonStyle())
            .help(title)
            .accessibilityLabel(title)
    }
}

private struct FolioToolbarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }
}

// MARK: Status line

/// The Undo bar after a removal, a quiet notice or an error, for the lists showing.
private struct FolioStatusLine: View {
    let stores: [ShelfStore]
    /// A quiet line when there's nothing else to say (the Trash says what it holds).
    var caption: String? = nil
    /// Colors' or Links' Undo bar.
    var collectionUndo: FolioCollectionUndo? = nil
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Group {
            if let collectionUndo {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(theme.notch.accent)
                    Text(collectionUndo.text).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button("Undo", action: collectionUndo.undo)
                        .buttonStyle(WidgetChipStyle(prominent: true, height: 20))
                        .keyboardShortcut("z")
                        .help("Undo (⌘Z)")
                }
                .padding(.leading, 8).padding(.trailing, 2)
                .frame(height: 22)
                .background(theme.notch.control, in: Capsule())
            } else             if let store = stores.first(where: { $0.errorText != nil }), let error = store.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(error).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if store.needsRecovery {
                        Button("Preserve & Recover") { store.recoverPersistence() }.buttonStyle(WidgetChipStyle(height: 20))
                    } else {
                        Button { store.dismissError() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Dismiss")
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let store = stores.first(where: { $0.undoText != nil }), let undo = store.undoText {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(theme.notch.accent)
                    Text(undo).lineLimit(1).truncationMode(.middle)
                    Text("Files stay where they are").foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    // One bar shows at a time, so only one Undo here holds ⌘Z; the removed tile
                    // took the keys with it, so the tiles' own ⌘Z can't reach this list.
                    Button("Undo") { store.undoRemoval() }
                        .buttonStyle(WidgetChipStyle(prominent: true, height: 20))
                        .keyboardShortcut("z")
                        .help("Undo (⌘Z)")
                }
                .padding(.leading, 8).padding(.trailing, 2)
                .frame(height: 22)
                .background(theme.notch.control, in: Capsule())
            } else if let notice = stores.lazy.compactMap(\.notice).first {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                    Text(notice).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).frame(height: 20)
            } else if let store = stores.first(where: { !$0.offlineIDs.isEmpty }) {
                HStack {
                    Spacer(minLength: 0)
                    Button("Remove \(store.offlineIDs.count) on disconnected drives") { store.removeOffline() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).frame(height: 20)
            } else if let caption {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                    Text(caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
            }
        }
        .font(.system(size: 10))
        .animation(Design.spring(), value: stores.map { $0.undoText ?? $0.notice ?? "" })
    }
}

// MARK: Empty states

/// An empty list: an invitation to drop files or paste, with a dashed outline.
private struct FolioDropEmpty: View {
    @ObservedObject var store: ShelfStore
    @Binding var isDropTargeted: Bool
    /// Shows the place that took pasted or dropped colours or links.
    let saved: (FolioPlace) -> Void
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 7) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(isDropTargeted ? theme.notch.accent : Color.secondary)
                .scaleEffect(isDropTargeted && !theme.reduceMotion ? 1.14 : 1)
            Text(isDropTargeted ? "Release to add" : "Drop files here")
                .font(.system(size: 12, weight: .semibold))
            Text("They wait here until you drag them into another app.\nRemoving one never deletes the file.")
                .font(.system(size: 10)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .opacity(isDropTargeted ? 0 : 1)
            Button { FolioDrops.paste(into: store, saved: saved) } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                .buttonStyle(WidgetChipStyle(height: 24))
                .keyboardShortcut("v")
                .help("Paste copied files, text, links or images (⌘V)")
                .opacity(isDropTargeted ? 0 : 1)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(theme.notch.accent.opacity(isDropTargeted ? 0.08 : 0))
                .overlay {
                    shape.strokeBorder(style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.25, dash: isDropTargeted ? [] : [5, 4]))
                        .foregroundStyle(isDropTargeted ? theme.notch.accent : Color.primary.opacity(0.14))
                }
        }
        .animation(Design.hoverAnimation, value: isDropTargeted)
        .onDrop(of: FolioDrops.types, isTargeted: $isDropTargeted) { providers in
            FolioDrops.handle(providers, into: store, saved: saved)
        }
    }
}

/// An empty smart folder or clipboard: what will gather here.
struct FolioQuietEmpty: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Search and filtering

/// The page's search: a magnifying glass, the field and a clear button. ⌘F focuses it,
/// Escape clears it.
private struct TraySearchField: View {
    @Binding var text: String
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($focused)
                .onExitCommand { text = ""; focused = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(Color.primary.opacity(0.09), in: Capsule())
        .overlay { Capsule().strokeBorder(theme.notch.accent, lineWidth: 1.5).opacity(focused ? 1 : 0) }
        .background {
            Button("") { focused = true }.keyboardShortcut("f").opacity(0).allowsHitTesting(false)
        }
.help("Search the Tray, baskets, watched folders, colors, links and the clipboard: names, your tags and notes, words in pictures and PDFs, what photos show (⌘F)")
    }
}

/// What the page is narrowed to: search words, and Find Similar's pictures.
struct FolioFilter {
    var terms: [String] = []
    /// Paths Find Similar kept (the picture itself and those like it); nil when not in use.
    var paths: Set<String>?

    var isActive: Bool { !terms.isEmpty || paths != nil }

    /// The matching items' ids, or nil when nothing narrows the list.
    @MainActor func matches(in store: ShelfStore, _ library: FolioIndex) -> Set<UUID>? {
        guard isActive else { return nil }
        return Set(store.items.filter { item in
            if let paths, !paths.contains(item.url.standardizedFileURL.path) { return false }
            return library.matches(terms, url: item.url, name: item.name, kind: store.info[item.id]?.kind ?? "")
        }.map(\.id))
    }
}

/// Stands in for the search field while Find Similar shows a picture's look-alikes.
private struct SimilarChip: View {
    let name: String
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text("Like \(name)").font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.85).truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show everything again")
        }
        .help("Pictures like \(name), nearest first")
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(Color.primary.opacity(0.09), in: Capsule())
    }
}

private struct FolioFindSimilarKey: EnvironmentKey {
    static let defaultValue: ((URL) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by the Folio page: shows the pictures like this one, from every list.
    var folioFindSimilar: ((URL) -> Void)? {
        get { self[FolioFindSimilarKey.self] }
        set { self[FolioFindSimilarKey.self] = newValue }
    }
}

/// Website captures type into the Tray page's search (`TrayPageView.previewQuery`); a release
/// build has nothing here.
private struct PreviewQuery: ViewModifier {
    @Binding var query: String

    func body(content: Content) -> some View {
        #if DEBUG
        content.onReceive(NotificationCenter.default.publisher(for: TrayPageView.previewQuery)) { note in
            if let text = note.object as? String { query = text }
        }
        #else
        content
        #endif
    }
}
