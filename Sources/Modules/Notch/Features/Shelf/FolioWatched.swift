import AppKit
import SwiftUI

/// A folder Folio watches for new files (Settings → Folio → Watched folders).
struct WatchedFolder: Identifiable, Equatable {
    let id: UUID
    var url: URL
    /// Follows the folder if it's moved or renamed.
    var bookmark: Data?
    /// The newest arrival taken, or when watching began: a file added to the folder by then is
    /// old news, so one removed from its place never comes back, while one that arrived while
    /// MacSpaces wasn't running still does.
    var mark: Date

    var name: String { url.lastPathComponent }

    var saved: [String: Any] {
        var saved: [String: Any] = ["id": id.uuidString, "path": url.path, "mark": mark.timeIntervalSince1970]
        if let bookmark { saved["bookmark"] = bookmark }
        return saved
    }

    init(id: UUID = UUID(), url: URL, bookmark: Data?, mark: Date) {
        self.id = id; self.url = url; self.bookmark = bookmark; self.mark = mark
    }

    init?(saved: [String: Any]) {
        guard let id = (saved["id"] as? String).flatMap(UUID.init(uuidString:)), let path = saved["path"] as? String else { return nil }
        self.init(id: id, url: URL(fileURLWithPath: path, isDirectory: true), bookmark: saved["bookmark"] as? Data,
                  mark: Date(timeIntervalSince1970: saved["mark"] as? Double ?? Date().timeIntervalSince1970))
    }
}

/// Folio's watched folders. A folder is added only from Settings' Add Folder (an open panel, so
/// choosing it is the permission), and nothing is watched until then. Each folder's new files
/// (top level only, once their size and date stay put for six seconds, browser partial files
/// never) join a list of its own, shown as a place under the folder's name on the Folio page.
/// Like the Tray, the list holds references: nothing is ever moved, copied or deleted, and
/// removing a folder forgets its list and what Folio knew of its files. A kernel event on the
/// folder (a `DispatchSource` on a utility queue) asks for a scan; scans list the folder on a
/// worker, one at a time per folder, and a scan for a folder that has since stopped or started
/// again is dropped. MacSpaces isn't sandboxed, so the folder's bookmark only follows moves.
@MainActor
final class FolioWatchedFolders: ObservableObject {
    static let shared = FolioWatchedFolders()
    static let limit = 20

    @Published private(set) var folders: [WatchedFolder] = []
    /// Why a folder can't be read right now, by folder.
    @Published private(set) var problems: [UUID: String] = [:]

    private var stores: [UUID: ShelfStore] = [:]
    private var sources: [UUID: DispatchSourceFileSystemObject] = [:]
    private var trackers: [UUID: CompletedFileTracker] = [:]
    /// Bumped whenever a folder starts or stops being watched; a scan from before is dropped.
    private var generations: [UUID: Int] = [:]
    private var scanning: Set<UUID> = []
    private var scanAgain: Set<UUID> = []
    private var pending: [UUID: DispatchWorkItem] = [:]
    private var started = false
    /// Check renders: shown, never watched or saved.
    private var previewing = false
    /// Checks watch a real folder but never save the list of folders.
    private var savesDisabled = false
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.folio-watch", qos: .utility)

    init() {
        let saved = UserDefaults.standard.array(forKey: WidgetOptions.Keys.folioWatchedFolders) as? [[String: Any]] ?? []
        folders = saved.compactMap(WatchedFolder.init(saved:))
    }

    /// Every watched folder's list that's loaded.
    var loadedStores: [ShelfStore] { folders.compactMap { stores[$0.id] } }

    func store(for id: UUID) -> ShelfStore {
        if let store = stores[id] { return store }
        let store = ShelfStore(watchedID: id)
        stores[id] = store
        return store
    }

    func allStores() -> [(folder: WatchedFolder, store: ShelfStore)] {
        folders.map { ($0, store(for: $0.id)) }
    }

    /// At launch: loads each folder's list, follows its bookmark (on a worker) and watches it.
    func start() {
        guard !started, !previewing else { return }
        started = true
        guard !folders.isEmpty else { return }
        folders.forEach { _ = store(for: $0.id) }
        let saved = folders
        Task { [weak self] in
            let located = await Task.detached(priority: .utility) { () -> [(UUID, URL?)] in
                saved.map { folder in (folder.id, folder.bookmark.flatMap(TrayFiles.resolve)?.standardizedFileURL) }
            }.value
            guard let self else { return }
            var changed = false
            for (id, url) in located {
                guard let url, let index = self.folders.firstIndex(where: { $0.id == id }), self.folders[index].url != url else { continue }
                self.folders[index].url = url; changed = true
            }
            if changed { self.save() }
            self.folders.forEach(self.watch)
        }
    }

    /// Settings' Add Folder: an open panel (a sheet on Settings), so the folder is the one chosen.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        panel.message = "New files that arrive in this folder appear on the Folio page. Files stay where they are."
        SettingsWindowController.shared.runPanel(panel) { [weak self] chosen in
            guard chosen, let url = panel.url else { return }
            self?.add(url)
        }
    }

    func add(_ url: URL) {
        let url = url.standardizedFileURL
        guard !previewing, !folders.contains(where: { $0.url == url }), folders.count < Self.limit else { return }
        let folder = WatchedFolder(url: url, bookmark: TrayFiles.bookmark(for: url), mark: Date())
        folders.append(folder)
        save()
        _ = store(for: folder.id)
        started = true
        watch(folder)
    }

    /// Stops watching and forgets the folder's list and what Folio read from its files (unless
    /// the Tray or a basket holds them too). The files themselves are untouched.
    func remove(_ id: UUID) {
        stopWatching(id)
        folders.removeAll { $0.id == id }
        problems[id] = nil
        save()
        FolioBoards.shared.forget(FolioPlace.watched(id).key)
        guard let store = stores.removeValue(forKey: id) else { return }
        let urls = store.items.map(\.url)
        store.forgetSavedList()
        urls.forEach { FolioIndex.shared.forget($0) }
    }

    func reveal(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
    }

    // MARK: Watching

    private func watch(_ folder: WatchedFolder) {
        guard !previewing else { return }
        stopWatching(folder.id)
        let id = folder.id, generation = generations[id, default: 0]
        let descriptor = open(folder.url.path, O_EVTONLY)
        if descriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self, weak source] in
                guard let event = source?.data else { return }
                let moved = !event.intersection([.rename, .delete]).isEmpty
                Task { @MainActor [weak self] in self?.changed(id, generation: generation, moved: moved) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources[id] = source
        }
        scan(id)
    }

    private func stopWatching(_ id: UUID) {
        sources.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.cancel()
        trackers[id] = nil
        scanning.remove(id); scanAgain.remove(id)
        generations[id, default: 0] += 1
    }

    private func changed(_ id: UUID, generation: Int, moved: Bool) {
        guard generations[id] == generation else { return }
        if moved { relocate(id) } else { schedule(id, after: 0.5) }
    }

    /// The folder itself was moved, renamed or deleted: follows its bookmark, or says it's gone.
    private func relocate(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        let generation = generations[id, default: 0]
        Task { [weak self] in
            let url = await Task.detached(priority: .utility) { () -> URL? in
                guard let url = folder.bookmark.flatMap(TrayFiles.resolve)?.standardizedFileURL,
                      FileManager.default.fileExists(atPath: url.path), !TrayFiles.isInTrash(url) else { return nil }
                return url
            }.value
            guard let self, self.generations[id] == generation, let index = self.folders.firstIndex(where: { $0.id == id }) else { return }
            guard let url else {
                self.stopWatching(id)
                self.problems[id] = "\(folder.name) was moved to the Trash or deleted"
                return
            }
            if url != self.folders[index].url {
                self.folders[index].url = url
                self.folders[index].bookmark = TrayFiles.bookmark(for: url) ?? self.folders[index].bookmark
                self.save()
            }
            self.watch(self.folders[index])
        }
    }

    /// A scan soon; the main queue runs it in every run-loop mode, so it fires while a menu is open.
    private func schedule(_ id: UUID, after seconds: TimeInterval) {
        pending[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pending[id] = nil
            self?.scan(id)
        }
        pending[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private struct Listing: Sendable {
        var files: [URL: CompletedFileTracker.Fingerprint] = [:]
        var added: [URL: Date] = [:]
    }

    private func scan(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        guard !scanning.contains(id) else { scanAgain.insert(id); return }
        scanning.insert(id)
        let generation = generations[id, default: 0], url = folder.url
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.list(url) }.value
            guard let self, self.generations[id] == generation else { return }
            self.scanning.remove(id)
            if self.scanAgain.remove(id) != nil { self.schedule(id, after: 0.3) }
            guard let index = self.folders.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .failure(let problem):
                if self.problems[id] != problem.message { self.problems[id] = problem.message }
            case .success(let listing):
                if self.problems[id] != nil { self.problems[id] = nil }
                self.take(listing, folder: index)
            }
        }
    }

    /// Adds the files that have arrived and settled, newest on top, and moves the mark on.
    private func take(_ listing: Listing, folder index: Int) {
        let id = folders[index].id, mark = folders[index].mark
        if trackers[id] == nil {
            let old = listing.files.keys.filter { (listing.added[$0] ?? .distantPast) <= mark }
            trackers[id] = CompletedFileTracker(existing: Set(old))
        }
        let arrived = trackers[id]?.poll(listing.files, at: Date()) ?? []
        if !arrived.isEmpty {
            let store = store(for: id)
            arrived.sorted { (listing.added[$0] ?? .distantPast) < (listing.added[$1] ?? .distantPast) }.forEach { store.add(url: $0) }
            if let newest = arrived.compactMap({ listing.added[$0] }).max(), newest > mark {
                folders[index].mark = newest
                save()
            }
        }
        if trackers[id]?.isWaiting == true { schedule(id, after: 2) }
    }

    private struct Problem: Error { let message: String }

    /// The folder's top-level files with their size, date and when each arrived. File I/O: on a worker.
    nonisolated private static func list(_ folder: URL) -> Result<Listing, Problem> {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey, .creationDateKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch {
            return .failure(Problem(message: "\(folder.lastPathComponent) can't be read: \(error.localizedDescription)"))
        }
        guard urls.count <= 10_000 else { return .failure(Problem(message: "\(folder.lastPathComponent) holds over 10,000 items; choose a smaller folder")) }
        var listing = Listing()
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let file = url.standardizedFileURL
            listing.files[file] = .init(bytes: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
            listing.added[file] = values.addedToDirectoryDate ?? values.creationDate
        }
        return .success(listing)
    }

    private func save() {
        guard !previewing, !savesDisabled else { return }
        UserDefaults.standard.set(folders.map(\.saved), forKey: WidgetOptions.Keys.folioWatchedFolders)
    }

#if DEBUG
    /// Checks: watches this one folder for real (replacing any others), never saved.
    func watchForCheck(_ url: URL) -> UUID? {
        folders.map(\.id).forEach(stopWatching)
        stores = [:]; problems = [:]; folders = []
        previewing = false; savesDisabled = true
        add(url)
        return folders.last?.id
    }

    /// Check renders: folders with these files, never watched or saved.
    func setPreviewFolders(_ preview: [(url: URL, files: [URL])]) {
        previewing = true
        folders.map(\.id).forEach(stopWatching)
        stores = [:]; problems = [:]
        folders = preview.map { WatchedFolder(url: $0.url, bookmark: nil, mark: Date()) }
        for (folder, entry) in zip(folders, preview) {
            let store = ShelfStore(watchedID: folder.id)
            store.setPreviewItems(entry.files, selectedIndex: nil)
            stores[folder.id] = store
        }
    }
#endif
}

/// Settings → Folio → Sources → Watched folders: each folder with how many new files it has
/// brought in, Add Folder (the only way one is added) and a minus to stop watching.
struct FolioWatchedFoldersList: View {
    @ObservedObject private var watched = FolioWatchedFolders.shared

    var body: some View {
        SettingsSection("Watched folders") {
            if watched.folders.isEmpty {
                Text("No folders watched yet").foregroundStyle(.secondary)
            }
            ForEach(watched.folders) { folder in
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.name).lineLimit(1)
                        Text(watched.problems[folder.id] ?? (folder.url.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption).foregroundStyle(watched.problems[folder.id] == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    FolioWatchedCount(store: watched.store(for: folder.id))
                    SettingsRemoveButton(label: "Stop watching \(folder.name)") { watched.remove(folder.id) }
                }
            }
            HStack {
                Button("Add Folder") { watched.chooseFolder() }
                    .buttonStyle(.settings(.secondary))
                    .disabled(watched.folders.count >= FolioWatchedFolders.limit)
                Spacer()
            }
            SettingsCaption("New files here show in Folio under the folder's name. Files stay put.",
                            help: "Only files that arrive after you add a folder are shown, without subfolders, once their size stays put for six seconds; browser partial files never. Removing one from Folio, or the folder from here, never touches the file.")
        }
    }
}

/// How many files a watched folder has brought in.
private struct FolioWatchedCount: View {
    @ObservedObject var store: ShelfStore

    var body: some View {
        Text(store.items.isEmpty ? "Nothing new yet" : store.items.count == 1 ? "1 new file" : "\(store.items.count) new files")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
}
