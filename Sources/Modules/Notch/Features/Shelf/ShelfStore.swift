import AppKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    var name: String { url.lastPathComponent }
    /// The tile's name: no extension, and today's screenshots without the date.
    var displayName: String { TrayFiles.displayName(name) }
}

/// What the Tray knows about one file, read on a background worker.
struct ShelfFileInfo: Equatable, Sendable {
    var kind = ""
    var bytes: Int64?
    var isDirectory = false
    var isImage = false
    var modified: Date?

    /// Finder-style kind and size, e.g. "PDF document · 2.4 MB".
    var details: String {
        var parts = kind.isEmpty ? [] : [kind]
        if !isDirectory, let bytes { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    static func read(_ url: URL) -> ShelfFileInfo {
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey,
                                                       .contentModificationDateKey, .contentTypeKey])
        return ShelfFileInfo(kind: values?.localizedTypeDescription ?? "",
                             bytes: values?.fileSize.map(Int64.init),
                             isDirectory: values?.isDirectory == true,
                             isImage: values?.contentType?.conforms(to: .image) == true,
                             modified: values?.contentModificationDate)
    }
}

/// Files waiting between apps (the Tray, and each file basket). It holds
/// references only: removing an item never touches the file. Saved lists,
/// bookmarks, file checks and thumbnails are read and written off the main
/// thread; a file that moves is followed, a file on a disconnected drive is
/// kept and dimmed, and a deleted or trashed file quietly leaves the list.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedItemID: UUID?
    @Published private(set) var selectedIDs: Set<UUID> = []
    /// On a disconnected drive (or an iCloud file not downloaded): kept, not draggable.
    @Published private(set) var offlineIDs: Set<UUID> = []
    @Published private(set) var info: [UUID: ShelfFileInfo] = [:]
    @Published private(set) var previews: [UUID: TrayPreview] = [:]
    /// Items with a file operation, such as compression, still running.
    @Published private(set) var busyItemIDs: Set<UUID> = []
    @Published private(set) var errorText: String?
    /// A short status, e.g. that deleted files left the Tray; clears itself.
    @Published private(set) var notice: String?
    /// The Undo bar's text while the last removal can be undone.
    @Published private(set) var undoText: String?
    var canUndoRemoval: Bool { undoText != nil }
    var needsRecovery: Bool { persistenceBlocked }
    var selectedItems: [ShelfItem] { items.filter { selectedIDs.contains($0.id) } }
    var selectedItem: ShelfItem? { items.first { $0.id == selectedItemID } }
    /// "8 items · 24.3 MB".
    var summary: String {
        TrayFiles.summary(count: items.count, bytes: items.reduce(0) { $0 + (info[$1.id]?.bytes ?? 0) })
    }

    static let undoSeconds: TimeInterval = 6
    private var removedItems: [(index: Int, item: ShelfItem)] = []
    private var bookmarks: [UUID: Data] = [:]
    private var previewStamps: [UUID: Date] = [:]
    private var undoExpiry: DispatchWorkItem?
    private var noticeExpiry: DispatchWorkItem?
    private var errorExpiry: DispatchWorkItem?
    private var refreshTask: Task<Void, Never>?
    private var refreshNeeded = false
    private var loadTask: Task<Void, Never>?
    private var isLoaded = false
    private var saveAfterLoad = false
    private var persistenceBlocked = false
    /// QA previews never write the list.
    private var savesDisabled = false

    /// URLs whose security-scoped access was successfully started. Each needs
    /// a balancing stop when its item leaves the tray.
    private var securityScopedURLs: Set<URL> = []

    private let basketID: UUID?
    private let persistenceURL: URL

    init(basketID: UUID? = nil) {
        self.basketID = basketID
        let root = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests"))
        persistenceURL = root.appendingPathComponent("MacSpaces", isDirectory: true)
            .appendingPathComponent(basketID.map { "basket-" + $0.uuidString + ".json" } ?? "tray.json")
        loadTask = Task { [weak self] in await self?.load() }
    }

    deinit {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Deletes a removed basket's saved list. It holds references only, so the
    /// files themselves are untouched.
    func forgetSavedList() {
        guard basketID != nil else { return }
        let file = persistenceURL
        ShelfDisk.queue.async { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: Adding

    @discardableResult
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    let message = error?.localizedDescription
                    Task { @MainActor in
                        if let url { self.add(url: url) } else { self.report(message ?? "Couldn't read the dropped file.") }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    let url = (item as? URL) ?? (item as? String).flatMap(URL.init(string:))
                        ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }.flatMap(URL.init(string:))
                    Task { @MainActor in if let url { self.stageLink(url) } else { self.report("Couldn't read the dropped link.") } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) ?? UTType.image.identifier) { data, _ in
                    // Decoded on the provider's worker, never on the main thread.
                    let png = data.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
                    Task { @MainActor in
                        if let png { self.stage(png, name: TrayFiles.stagedName(for: .image), ext: "png") }
                        else { self.report("Couldn't read the dropped image.") }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    Task { @MainActor in if let text { self.stageText(text) } }
                }
            }
        }
        return accepted
    }

    func paste() {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.forEach { add(url: $0) }
        } else if let data = board.data(forType: .png) { stage(data, name: TrayFiles.stagedName(for: .image), ext: "png") }
        else if let tiff = board.data(forType: .tiff) {
            Task.detached(priority: .userInitiated) {
                let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                await MainActor.run {
                    if let png { self.stage(png, name: TrayFiles.stagedName(for: .image), ext: "png") }
                    else { self.report("Couldn't read the copied image.") }
                }
            }
        }
        else if let link = board.string(forType: .URL), let url = URL(string: link) { stageLink(url) }
        else if let text = board.string(forType: .string), !text.isEmpty { stageText(text) }
        else { report("Copy files, text, a link or an image, then paste into the Tray.") }
    }

    private func stageText(_ text: String) {
        stage(Data(text.utf8), name: TrayFiles.stagedName(for: .text(text)), ext: "txt")
    }

    private func stageLink(_ url: URL) {
        do { stage(try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0),
                   name: TrayFiles.stagedName(for: .link(url)), ext: "webloc") }
        catch { report(error.localizedDescription) }
    }

    /// Writes pasted or dropped content into its own folder (so names never
    /// collide) on the disk worker, then adds it.
    private func stage(_ data: Data, name: String, ext: String) {
        let folder = persistenceURL.deletingLastPathComponent().appendingPathComponent("Staged", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension(ext)
        ShelfDisk.queue.async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                Task { @MainActor in self.add(url: url) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in self.report("Couldn't stage content: " + message) }
            }
        }
    }

    func add(url: URL) {
        let url = url.standardizedFileURL
        defer { pruneMissingItems() }
        // Dropping a file that is already staged brings it back to the front
        // instead of silently ignoring the drop.
        if let index = items.firstIndex(where: { $0.url == url }) {
            guard index != 0 else { return }
            withAnimation(Design.spring()) {
                let existing = items.remove(at: index)
                items.insert(existing, at: 0)
            }
            save()
            return
        }
        let item = ShelfItem(url: url)
        startSecurityScopedAccess(for: url)
        withAnimation(Design.spring()) {
            items.insert(item, at: 0)
        }
        save()
    }

    // MARK: File actions

    func process(_ item: ShelfItem, operation: LocalFileTools.Operation) {
        let actionID: String
        switch operation {
        case .png: actionID = "image.png"
        case .jpeg: actionID = "image.jpg"
        case .extractText: actionID = "tool.ocr"
        case .removeBackground: actionID = "tool.cutout"
        }
        run(FileConverter.Action(id: actionID, title: operation.title, symbol: "wand.and.stars"), on: [item])
    }

    func run(_ action: FileConverter.Action, on files: [ShelfItem]? = nil) {
        let inputs = files ?? selectedItems
        guard !inputs.isEmpty else { report("Select one or more files first."); return }
        guard !inputs.contains(where: { offlineIDs.contains($0.id) }) else { report("Reconnect the drive these files are on first."); return }
        guard !inputs.contains(where: { busyItemIDs.contains($0.id) }) else { report("These files are already being processed."); return }
        let ids = Set(inputs.map(\.id))
        busyItemIDs.formUnion(ids)
        ConverterJobs.shared.start(action, on: inputs.map(\.url)) { [weak self] outputs in
            guard let self else { return }
            self.busyItemIDs.subtract(ids)
            outputs.forEach { self.add(url: $0) }
        }
    }

    /// The files an action applies to: the selection when the item is part of
    /// it, otherwise just the item.
    func targets(for item: ShelfItem) -> [ShelfItem] {
        selectedIDs.contains(item.id) ? selectedItems : [item]
    }

    private var availableSelection: [URL] {
        selectedItems.filter { !offlineIDs.contains($0.id) }.map(\.url)
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func openSelected() {
        availableSelection.forEach { NSWorkspace.shared.open($0) }
    }

    func revealInFinder(_ items: [ShelfItem]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.filter { !offlineIDs.contains($0.id) }.map(\.url))
    }

    func airDrop(_ items: [ShelfItem]) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: items.map(\.url))
    }

    /// Puts the files themselves on the pasteboard so they paste into Finder,
    /// Mail or Messages like a Finder copy.
    func copyToPasteboard(_ items: [ShelfItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.url as NSURL })
    }

    /// OCR uses the same visible, cancellable result cards as other file actions.
    func copyText(_ item: ShelfItem) {
        run(FileConverter.Action(id: "tool.ocr", title: "Copy Text", symbol: "text.viewfinder"), on: [item])
    }

    /// Stages the ZIP and reports failures through the shared job cards.
    func compress(_ items: [ShelfItem]) {
        run(FileConverter.Action(id: "zip", title: "ZIP", symbol: "doc.zipper"), on: items)
    }

    func quickLook() {
        let files = availableSelection
        guard !files.isEmpty else { report("Select a file to preview."); return }
        ShelfPreview.shared.show(files)
    }

    /// Repoints an item on a disconnected drive at a copy elsewhere.
    func locate(_ item: ShelfItem) {
        let panel = NSOpenPanel()
        panel.message = "Locate " + item.name
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        repoint(item.id, to: url.standardizedFileURL)
        pruneMissingItems(); save()
    }

    // MARK: Removing

    func remove(_ item: ShelfItem) { removeItems([item]) }
    func removeSelected() { removeItems(selectedItems) }
    func removeAll() { removeItems(items) }
    /// Clears files on disconnected drives in one go.
    func removeOffline() { removeItems(items.filter { offlineIDs.contains($0.id) }) }

    private func removeItems(_ removed: [ShelfItem]) {
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        removedItems = items.enumerated().filter { ids.contains($0.element.id) }.map { ($0.offset, $0.element) }
        withAnimation(Design.spring()) { items.removeAll { ids.contains($0.id) } }
        for item in removed { stopSecurityScopedAccess(for: item.url) }
        selectedIDs.subtract(ids)
        if let selectedItemID, ids.contains(selectedItemID) { self.selectedItemID = selectedItems.first?.id }
        let count = removed.count
        showUndo(items.isEmpty && count > 1 ? "Cleared \(count) items" : count == 1 ? "Removed \u{201C}\(removed[0].displayName)\u{201D}" : "Removed \(count) items")
        save()
    }

    /// Puts the last removal back where it was; items added since stay put.
    func undoRemoval() {
        guard !removedItems.isEmpty else { return }
        let restored = removedItems.filter { entry in !items.contains { $0.id == entry.item.id || $0.url == entry.item.url } }
        withAnimation(Design.spring()) {
            items = TrayFiles.restoring(removedItems, into: items) { $0.id == $1.id || $0.url == $1.url }
        }
        restored.forEach { startSecurityScopedAccess(for: $0.item.url) }
        selectedIDs = Set(restored.map(\.item.id)); selectedItemID = restored.first?.item.id
        removedItems = []
        undoExpiry?.cancel(); undoText = nil
        pruneMissingItems(); save()
    }

    private func showUndo(_ text: String) {
        undoText = text
        undoExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(Design.spring()) { self.undoText = nil }
            self.removedItems = []
            self.dropUnusedState()
        }
        undoExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.undoSeconds, execute: work)
    }

    /// Previews, details and bookmarks of items that are gone for good.
    private func dropUnusedState() {
        let live = Set(items.map(\.id)).union(removedItems.map(\.item.id))
        previews = previews.filter { live.contains($0.key) }
        info = info.filter { live.contains($0.key) }
        bookmarks = bookmarks.filter { live.contains($0.key) }
        previewStamps = previewStamps.filter { live.contains($0.key) }
    }

    // MARK: Selection

    func select(_ item: ShelfItem?, extending: Bool = false, range: Bool = false) {
        guard let item else { selectedIDs = []; selectedItemID = nil; return }
        if range, let anchor = items.firstIndex(where: { $0.id == selectedItemID }), let end = items.firstIndex(where: { $0.id == item.id }) {
            selectedIDs.formUnion(items[min(anchor, end)...max(anchor, end)].map(\.id))
        } else if extending {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
        } else { selectedIDs = [item.id] }
        selectedItemID = selectedIDs.contains(item.id) ? item.id : selectedItems.first?.id
    }

    func selectAll() { selectedIDs = Set(items.map(\.id)); selectedItemID = items.first?.id }

    func selectNext(_ offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedItemID } ?? (offset > 0 ? -1 : items.count)
        select(items[max(0, min(items.count - 1, current + offset))])
    }

    // MARK: Status

    private func report(_ message: String) {
        errorText = message
        errorExpiry?.cancel()
        guard !persistenceBlocked else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.persistenceBlocked else { return }
            withAnimation(Design.spring()) { self.errorText = nil }
        }
        errorExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func dismissError() { if !persistenceBlocked { errorText = nil } }

    private func announce(_ message: String) {
        withAnimation(Design.spring()) { notice = message }
        noticeExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation(Design.spring()) { self?.notice = nil } }
        noticeExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: File checks

    private struct Inspection: Sendable {
        let id: UUID
        let url: URL
        let state: TrayFileState
        let info: ShelfFileInfo?
        let bookmark: Data?
    }

    /// Checks every file on a background worker: moved files are followed,
    /// deleted or trashed ones leave the list (a quiet notice says so), files
    /// on a disconnected drive stay. Also refreshes details and thumbnails.
    func pruneMissingItems() {
        refreshNeeded = true
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while let self, self.refreshNeeded {
                self.refreshNeeded = false
                let snapshot = self.items.map { ($0, self.bookmarks[$0.id]) }
                let results = await Task.detached(priority: .utility) { () -> [Inspection] in
                    var results = snapshot.map { item, bookmark in Self.inspect(item, bookmark: bookmark) }
                    // A file can vanish for a moment while an app saves it;
                    // only one still missing a moment later is gone.
                    if results.contains(where: { $0.state == .gone }) {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        results = results.map { result in
                            guard result.state == .gone, let entry = snapshot.first(where: { $0.0.id == result.id }) else { return result }
                            return Self.inspect(entry.0, bookmark: entry.1)
                        }
                    }
                    return results
                }.value
                guard !Task.isCancelled else { break }
                self.apply(results)
            }
            self?.refreshTask = nil
        }
    }

    nonisolated private static func inspect(_ item: ShelfItem, bookmark: Data?) -> Inspection {
        let state = TrayFileState.inspect(item.url, bookmark: bookmark)
        switch state {
        case .present:
            return Inspection(id: item.id, url: item.url, state: state, info: .read(item.url),
                              bookmark: bookmark == nil ? TrayFiles.bookmark(for: item.url) : nil)
        case .moved(let url):
            return Inspection(id: item.id, url: item.url, state: state, info: .read(url), bookmark: TrayFiles.bookmark(for: url))
        case .offline, .gone:
            return Inspection(id: item.id, url: item.url, state: state, info: nil, bookmark: nil)
        }
    }

    private func apply(_ results: [Inspection]) {
        var changed = false
        var gone: [ShelfItem] = []
        var offline = offlineIDs
        for result in results {
            // Skip results for items removed or repointed since the check began.
            guard let item = items.first(where: { $0.id == result.id }), item.url == result.url else { continue }
            switch result.state {
            case .present:
                offline.remove(item.id)
            case .moved(let url):
                repoint(item.id, to: url)
                offline.remove(item.id); changed = true
            case .offline:
                offline.insert(item.id)
            case .gone:
                gone.append(item)
            }
            if let bookmark = result.bookmark { bookmarks[item.id] = bookmark; changed = true }
            if let fileInfo = result.info {
                if info[item.id] != fileInfo { info[item.id] = fileInfo }
                if let current = items.first(where: { $0.id == item.id }) { requestPreview(current, modified: fileInfo.modified) }
            }
        }
        if offlineIDs != offline { offlineIDs = offline }
        if !gone.isEmpty {
            let ids = Set(gone.map(\.id))
            withAnimation(Design.spring()) { items.removeAll { ids.contains($0.id) } }
            gone.forEach { stopSecurityScopedAccess(for: $0.url) }
            selectedIDs.subtract(ids)
            if let selectedItemID, ids.contains(selectedItemID) { self.selectedItemID = selectedItems.first?.id }
            offlineIDs.subtract(ids)
            dropUnusedState()
            announce(gone.count == 1 ? "\u{201C}\(gone[0].displayName)\u{201D} was deleted, so it left the Tray"
                                     : "\(gone.count) deleted files left the Tray")
            changed = true
        }
        if changed { save() }
    }

    private func repoint(_ id: UUID, to url: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        stopSecurityScopedAccess(for: items[index].url)
        items[index] = ShelfItem(id: id, url: url)
        startSecurityScopedAccess(for: url)
        bookmarks[id] = nil
        previewStamps[id] = nil
    }

    private func requestPreview(_ item: ShelfItem, modified: Date?) {
        let stamp = modified ?? .distantPast
        guard previews[item.id] == nil || previewStamps[item.id] != stamp else { return }
        previewStamps[item.id] = stamp
        let id = item.id, url = item.url
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task { [weak self] in
            guard let preview = await TrayThumbnails.shared.preview(for: url, modified: modified, scale: scale) else { return }
            guard let self, self.items.contains(where: { $0.id == id && $0.url == url }) else { return }
            withAnimation(Design.hoverAnimation) { self.previews[id] = preview }
        }
    }

#if DEBUG
    /// Waits for the saved list, file checks, thumbnails and disk writes.
    func waitForFileMetadata() async {
        await loadTask?.value
        while let task = refreshTask { await task.value }
        // Up to 10 s for every preview and its details: a shared CI Mac can take seconds.
        for _ in 0..<200 where items.contains(where: { (previews[$0.id] == nil || info[$0.id] == nil) && !offlineIDs.contains($0.id) }) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await withCheckedContinuation { continuation in ShelfDisk.queue.async { continuation.resume() } }
    }

    /// Local visual-QA data that never touches the persisted user shelf.
    func setPreviewItems(_ urls: [URL], selectedIndex: Int? = nil) {
        loadTask?.cancel(); isLoaded = true; savesDisabled = true
        items = urls.map { ShelfItem(url: $0) }
        if let selectedIndex, items.indices.contains(selectedIndex) {
            selectedItemID = items[selectedIndex].id
            selectedIDs = [items[selectedIndex].id]
        } else {
            selectedItemID = nil
        }
        pruneMissingItems()
    }

    /// QA: shows the Undo bar and a notice as they appear after a removal.
    func setPreviewStatus(undo: String?, notice: String?) {
        undoText = undo; self.notice = notice
    }
#endif

    // MARK: Persistence

    func recoverPersistence() {
        do {
            if FileManager.default.fileExists(atPath: persistenceURL.path) {
                let backup = persistenceURL.deletingLastPathComponent().appendingPathComponent(persistenceURL.lastPathComponent + ".recovery-" + UUID().uuidString)
                try FileManager.default.copyItem(at: persistenceURL, to: backup)
            }
            persistenceBlocked = false; errorText = nil; save()
        } catch { errorText = "Couldn't preserve the saved list: " + error.localizedDescription }
    }

    private func load() async {
        let file = persistenceURL
        let result = await withCheckedContinuation { continuation in
            ShelfDisk.queue.async { continuation.resume(returning: ShelfDisk.read(file)) }
        }
        guard !Task.isCancelled, !isLoaded else { return }
        isLoaded = true
        switch result {
        case .none: break
        case .damaged:
            persistenceBlocked = true
            errorText = "The saved list couldn't be read. Preserve a recovery copy before saving new changes."
        case .entries(let entries, let partial):
            if partial {
                persistenceBlocked = true
                errorText = "Some saved entries couldn't be read. Preserve a recovery copy before saving changes."
            }
            // Items added while the list loaded stay in front.
            let added = items
            let loaded = entries.filter { entry in !added.contains { $0.id == entry.id || $0.url == entry.url } }
            for entry in loaded {
                startSecurityScopedAccess(for: entry.url)
                if let bookmark = entry.bookmark { bookmarks[entry.id] = bookmark }
            }
            items = added + loaded.map { ShelfItem(id: $0.id, url: $0.url) }
        }
        if saveAfterLoad { saveAfterLoad = false; save() }
        pruneMissingItems()
    }

    private func save() {
        guard isLoaded else { saveAfterLoad = true; return }
        guard !persistenceBlocked, !savesDisabled else { return }
        let entries = items.map { ShelfDisk.Entry(id: $0.id, url: $0.url, bookmark: bookmarks[$0.id]) }
        let file = persistenceURL
        ShelfDisk.queue.async {
            if let message = ShelfDisk.write(entries, to: file) {
                Task { @MainActor [weak self] in self?.report("Couldn't save this list: " + message) }
            }
        }
    }

    private func startSecurityScopedAccess(for url: URL) {
        guard !securityScopedURLs.contains(url), url.startAccessingSecurityScopedResource() else { return }
        securityScopedURLs.insert(url)
    }

    private func stopSecurityScopedAccess(for url: URL) {
        guard securityScopedURLs.remove(url) != nil else { return }
        url.stopAccessingSecurityScopedResource()
    }
}

/// Reading and writing saved Tray and basket lists, in order, on one serial
/// worker (a reload always sees the last write).
enum ShelfDisk {
    static let queue = DispatchQueue(label: "dev.opensource.MacSpaces.tray-disk", qos: .utility)

    struct Entry: Sendable { let id: UUID; let url: URL; let bookmark: Data? }
    enum ReadResult: Sendable { case none, damaged, entries([Entry], partial: Bool) }

    private struct PersistedItem: Codable {
        let id: UUID
        let bookmark: Data?
        let fallbackPath: String
    }

    /// One malformed entry drops only itself, so the rest of the list survives.
    private struct DecodableItem: Decodable {
        let value: PersistedItem?

        init(from decoder: Decoder) throws {
            value = try? PersistedItem(from: decoder)
        }
    }

    /// Bookmarks follow files that moved while MacSpaces wasn't running; they
    /// never mount a volume, so a disconnected drive keeps its saved path.
    static func read(_ file: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: file.path) else { return .none }
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([DecodableItem].self, from: data) else { return .damaged }
        let entries = decoded.compactMap(\.value).map { saved -> Entry in
            let resolved = saved.bookmark.flatMap(TrayFiles.resolve)
            return Entry(id: saved.id, url: (resolved ?? URL(fileURLWithPath: saved.fallbackPath)).standardizedFileURL, bookmark: saved.bookmark)
        }
        return .entries(entries, partial: decoded.contains { $0.value == nil })
    }

    /// Returns an error message, or nil once written.
    static func write(_ entries: [Entry], to file: URL) -> String? {
        let persisted = entries.map { entry in
            PersistedItem(id: entry.id, bookmark: entry.bookmark ?? TrayFiles.bookmark(for: entry.url), fallbackPath: entry.url.path)
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(persisted).write(to: file, options: .atomic)
            return nil
        } catch { return error.localizedDescription }
    }
}

@MainActor
private final class ShelfPreview: ObservableObject {
    static let shared = ShelfPreview()
    @Published private(set) var urls: [URL] = []
    @Published var index = 0
    private var panel: ShelfPreviewWindow?
    func show(_ urls: [URL]) {
        if panel?.isVisible == true { panel?.orderOut(nil); return }
        self.urls = urls; index = 0
        guard !urls.isEmpty else { return }
        if panel == nil {
            let panel = ShelfPreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Quick Look"; panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width: 420, height: 320)
            panel.contentView = NSHostingView(rootView: ShelfPreviewContent(model: self))
            panel.center(); self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
    private final class ShelfPreviewWindow: NSPanel { override var canBecomeKey: Bool { true } }
}
private struct ShelfPreviewContent: View {
    @ObservedObject var model: ShelfPreview
    var body: some View {
        VStack(spacing: 0) {
            if model.urls.indices.contains(model.index) {
                HStack {
                    Text(model.urls[model.index].lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if model.urls.count > 1 {
                        Button { model.index -= 1 } label: { Image(systemName: "chevron.left") }.disabled(model.index == 0)
                        Text("\(model.index + 1) / \(model.urls.count)").font(.caption)
                        Button { model.index += 1 } label: { Image(systemName: "chevron.right") }.disabled(model.index == model.urls.count - 1)
                    }
                }.padding(12)
                Divider()
                PreviewFile(url: model.urls[model.index])
            }
        }
    }
    private struct PreviewFile: NSViewRepresentable {
        let url: URL
        func makeNSView(context: Context) -> QLPreviewView { QLPreviewView(frame: .zero, style: .normal)! }
        func updateNSView(_ view: QLPreviewView, context: Context) { view.autostarts = true; view.previewItem = url as NSURL }
        static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.close() }
    }
}
