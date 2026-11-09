import AppKit

/// Folio's Trash: what you remove on the Folio page waits here, as references only, for 30 days.
/// Put Back returns a reference to the list it came from (the Tray when that list is gone), and
/// Empty Trash or the 30 days let it go. Nothing here ever moves, trashes or deletes a file on
/// disk. Its list is `trash.json` like any other (`ShelfStore(trash:)`); where each reference
/// came from and when is `folio-trash.json`, both on `ShelfDisk.queue`.
@MainActor
final class FolioTrash: ObservableObject {
    static let shared = FolioTrash()
    let store: ShelfStore
    @Published private(set) var book = FolioTrashBook()
    private var bookLoaded = false
    private var savesDisabled = false
    private var saveWork: DispatchWorkItem?
    private let file = FolioStorage.url("folio-trash.json")

    static let help = "Removed items wait here 30 days. Only references: no file on disk is ever touched."

    init() {
        store = ShelfStore(trash: true)
        let file = self.file, store = self.store
        Task { @MainActor [weak self] in
            let saved = await withCheckedContinuation { (continuation: CheckedContinuation<FolioTrashBook?, Never>) in
                ShelfDisk.queue.async { continuation.resume(returning: FolioStorage.read(FolioTrashBook.self, from: file)) }
            }
            await store.loaded()
            guard let self else { return }
            // Anything trashed while the book loaded wins.
            var book = saved ?? FolioTrashBook()
            for (path, entry) in self.book.entries { book.record([path], from: entry.from, now: entry.removed) }
            self.book = book
            self.bookLoaded = true
            self.purgeExpired()
        }
    }

    /// References removed from a list on the Folio page.
    func receive(_ urls: [URL], from origin: String) {
        guard !urls.isEmpty else { return }
        urls.forEach { store.add(url: $0) }
        book.record(urls.map { $0.standardizedFileURL.path }, from: origin, now: Date())
        scheduleSave()
    }

    /// Undo of a move to the Trash: the references leave it again.
    func withdraw(_ urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        store.discard(store.items.filter { paths.contains($0.url.standardizedFileURL.path) })
        book.forget(Array(paths))
        scheduleSave()
    }

    /// Returns each reference to the list it came from, or the Tray when that list is gone.
    func putBack(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            target(for: book.origin(item.url.standardizedFileURL.path)).add(url: item.url)
        }
        store.discard(items)
        book.forget(items.map { $0.url.standardizedFileURL.path })
        scheduleSave()
    }

    /// Lets go of references older than 30 days. Runs as the Trash loads and as the page opens.
    func purgeExpired(now: Date = Date()) {
        guard bookLoaded else { return }
        let paths = store.items.map { $0.url.standardizedFileURL.path }
        let expired = Set(book.expired(paths, now: now))
        if !expired.isEmpty { store.discard(store.items.filter { expired.contains($0.url.standardizedFileURL.path) }) }
        let before = book
        book.keep(only: Set(store.items.map { $0.url.standardizedFileURL.path }), now: now)
        if book != before { scheduleSave() }
    }

    func moved(from old: URL, to new: URL) {
        book.moved(from: old.standardizedFileURL.path, to: new.standardizedFileURL.path)
        scheduleSave()
    }

    /// "Weekend trip", "Tray" or a watched folder's name: where Put Back sends this reference.
    func originName(_ url: URL) -> String {
        let origin = book.origin(url.standardizedFileURL.path)
        if origin.hasPrefix("basket:"), let id = UUID(uuidString: String(origin.dropFirst(7))),
           let basket = BasketWindowController.shared.baskets.first(where: { $0.id == id }) {
            return basket.name
        }
        if origin.hasPrefix("watched:"), let id = UUID(uuidString: String(origin.dropFirst(8))),
           let folder = FolioWatchedFolders.shared.folders.first(where: { $0.id == id }) {
            return folder.name
        }
        return "Tray"
    }

    func daysLeft(_ url: URL) -> Int { book.daysLeft(url.standardizedFileURL.path, now: Date()) }

    /// The list an origin names, while it exists; the Tray otherwise.
    private func target(for origin: String) -> ShelfStore {
        if origin.hasPrefix("basket:"), let id = UUID(uuidString: String(origin.dropFirst(7))),
           BasketWindowController.shared.baskets.contains(where: { $0.id == id }) {
            return BasketWindowController.shared.store(for: id)
        }
        if origin.hasPrefix("watched:"), let id = UUID(uuidString: String(origin.dropFirst(8))),
           FolioWatchedFolders.shared.folders.contains(where: { $0.id == id }) {
            return FolioWatchedFolders.shared.store(for: id)
        }
        return ShelfStore.shared
    }

    private func scheduleSave() {
        guard !savesDisabled else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func save() {
        guard bookLoaded else { scheduleSave(); return }
        guard !savesDisabled else { return }
        let book = self.book, file = self.file
        ShelfDisk.queue.async { FolioStorage.write(book, to: file) }
    }

#if DEBUG
    /// Check renders: these references, removed this many days ago from these lists, never saved.
    func setPreview(_ entries: [(url: URL, daysAgo: Double, from: String)]) {
        savesDisabled = true
        saveWork?.cancel()
        store.setPreviewItems(entries.map(\.url))
        var book = FolioTrashBook()
        for entry in entries {
            book.record([entry.url.standardizedFileURL.path], from: entry.from, now: Date().addingTimeInterval(-entry.daysAgo * 86_400))
        }
        self.book = book
        bookLoaded = true
    }
#endif
}
