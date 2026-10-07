import AppKit
import QuickLookThumbnailing
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }

    var name: String { url.lastPathComponent }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Finder-style kind and size, e.g. "PDF document · 2.4 MB".
    var details: String {
        let values = try? url.resourceValues(forKeys: [
            .localizedTypeDescriptionKey, .fileSizeKey, .isDirectoryKey
        ])
        var parts: [String] = []
        if let kind = values?.localizedTypeDescription {
            parts.append(kind)
        }
        if values?.isDirectory != true, let size = values?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

/// Holds files dropped onto the notch. Security-scoped bookmarks make the
/// tray survive relaunches while keeping the underlying files in place.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedItemID: UUID?
    @Published private(set) var selectedIDs: Set<UUID> = []
    @Published private(set) var unavailableIDs: Set<UUID> = []
    @Published private(set) var errorText: String?
    @Published private(set) var canUndoRemoval = false
    private var removedItems: [(Int, ShelfItem)] = []
    private var persistenceBlocked = false
    var needsRecovery: Bool { persistenceBlocked }
    /// Quick Look previews for images, PDFs, video and documents. Items
    /// without one (folders, apps) keep their Finder icon.
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    /// Items with a file operation, such as compression, still running.
    @Published private(set) var busyItemIDs: Set<UUID> = []

    /// URLs whose security-scoped access was successfully started on load.
    /// Each needs a balancing stop when its item leaves the tray.
    private var securityScopedURLs: Set<URL> = []

    private struct PersistedItem: Codable {
        let id: UUID
        let bookmark: Data?
        let fallbackPath: String
    }

    /// One malformed entry drops only itself, so the rest of the tray survives.
    private struct DecodableItem: Decodable {
        let value: PersistedItem?

        init(from decoder: Decoder) throws {
            value = try? PersistedItem(from: decoder)
        }
    }

    private let basketID: UUID?
    private var persistenceURL: URL {
        let root = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests"))
        let directory = root.appendingPathComponent("MacSpaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(basketID.map { "basket-" + $0.uuidString + ".json" } ?? "tray.json")
    }

    /// Deletes a removed basket's saved list. It holds references only, so the
    /// files themselves are untouched.
    func forgetSavedList() {
        guard basketID != nil else { return }
        try? FileManager.default.removeItem(at: persistenceURL)
    }

    init(basketID: UUID? = nil) {
        self.basketID = basketID
        load()
        items.forEach(requestThumbnail(for:))
    }

    deinit {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    @discardableResult
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    Task { @MainActor in
                        if let url { self.add(url: url) } else { self.errorText = error?.localizedDescription ?? "Couldn't read the dropped file." }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    let url = (item as? URL) ?? (item as? String).flatMap(URL.init(string:))
                        ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }.flatMap(URL.init(string:))
                    Task { @MainActor in if let url { self.stageLink(url) } else { self.errorText = "Couldn't read the dropped link." } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) ?? UTType.image.identifier) { data, _ in
                    Task { @MainActor in
                        if let data, let image = NSBitmapImageRep(data: data), let png = image.representation(using: .png, properties: [:]) {
                            self.stage(png, name: "Image", ext: "png")
                        } else { self.errorText = "Couldn't read the dropped image." }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    let text = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    Task { @MainActor in if let text { self.stage(Data(text.utf8), name: "Text", ext: "txt") } }
                }
            }
        }
        return accepted
    }

    func paste() {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.forEach { add(url: $0) }
        } else if let data = board.data(forType: .png) { stage(data, name: "Image", ext: "png") }
        else if let data = board.data(forType: .tiff), let image = NSBitmapImageRep(data: data), let png = image.representation(using: .png, properties: [:]) { stage(png, name: "Image", ext: "png") }
        else if let link = board.string(forType: .URL), let url = URL(string: link) { stageLink(url) }
        else if let text = board.string(forType: .string), !text.isEmpty { stage(Data(text.utf8), name: "Text", ext: "txt") }
        else { errorText = "Copy files, text, a link or an image, then paste into the Tray." }
    }

    private func stageLink(_ url: URL) {
        do { stage(try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0), name: "Link", ext: "webloc") }
        catch { errorText = error.localizedDescription }
    }

    private func stage(_ data: Data, name: String, ext: String) {
        do {
            let folder = persistenceURL.deletingLastPathComponent().appendingPathComponent("Staged", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name + "-" + UUID().uuidString.prefix(8)).appendingPathExtension(ext)
            try data.write(to: url, options: .atomic)
            add(url: url)
        } catch { errorText = "Couldn't stage content: " + error.localizedDescription }
    }

    func add(url: URL) {
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
        if !securityScopedURLs.contains(url), url.startAccessingSecurityScopedResource() { securityScopedURLs.insert(url) }
        withAnimation(Design.spring()) {
            items.insert(item, at: 0)
        }
        requestThumbnail(for: item)
        save()
    }

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

    var selectedItems: [ShelfItem] { items.filter { selectedIDs.contains($0.id) } }

    func run(_ action: FileConverter.Action, on files: [ShelfItem]? = nil) {
        let inputs = files ?? selectedItems
        guard !inputs.isEmpty else { errorText = "Select one or more files first."; return }
        guard !inputs.contains(where: { unavailableIDs.contains($0.id) }) else { errorText = "Locate or reconnect unavailable files first."; return }
        guard !inputs.contains(where: { busyItemIDs.contains($0.id) }) else { errorText = "These files are already being processed."; return }
        let ids = Set(inputs.map(\.id))
        busyItemIDs.formUnion(ids)
        ConverterJobs.shared.start(action, on: inputs.map(\.url)) { [weak self] outputs in
            guard let self else { return }
            self.busyItemIDs.subtract(ids)
            outputs.forEach { self.add(url: $0) }
        }
    }

    func remove(_ item: ShelfItem) { removeItems([item]) }
    func removeSelected() { removeItems(selectedItems) }
    private func removeItems(_ removed: [ShelfItem]) {
        let ids = Set(removed.map(\.id))
        removedItems = items.enumerated().filter { ids.contains($0.element.id) }.map { ($0.offset, $0.element) }
        canUndoRemoval = !removedItems.isEmpty
        withAnimation(Design.spring()) { items.removeAll { ids.contains($0.id) } }
        for item in removed { stopSecurityScopedAccess(for: item.url); thumbnails[item.id] = nil }
        selectedIDs.subtract(ids)
        if let selectedItemID, ids.contains(selectedItemID) { self.selectedItemID = selectedItems.first?.id }
        pruneMissingItems()
        save()
    }

    func undoRemoval() {
        for (index, item) in removedItems where !items.contains(where: { $0.id == item.id || $0.url == item.url }) {
            items.insert(item, at: min(index, items.count))
            if item.url.startAccessingSecurityScopedResource() { securityScopedURLs.insert(item.url) }
            requestThumbnail(for: item)
        }
        removedItems = []; canUndoRemoval = false
        pruneMissingItems(); save()
    }

    /// Offline volumes and deleted paths remain available for Locate or Reconnect.
    func pruneMissingItems() {
        unavailableIDs = Set(items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }.map(\.id))
    }

    func locate(_ item: ShelfItem) {
        let panel = NSOpenPanel()
        panel.message = "Locate " + item.name
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        stopSecurityScopedAccess(for: item.url)
        items[index] = ShelfItem(id: item.id, url: url)
        if url.startAccessingSecurityScopedResource() { securityScopedURLs.insert(url) }
        thumbnails[item.id] = nil
        requestThumbnail(for: items[index]); pruneMissingItems(); save()
    }

    func quickLook() {
        let files = selectedItems.filter { !unavailableIDs.contains($0.id) }.map(\.url)
        guard !files.isEmpty else { errorText = "Select an available file to preview."; return }
        ShelfPreview.shared.show(files)
    }

    func selectAll() { selectedIDs = Set(items.map(\.id)); selectedItemID = items.first?.id }
    func selectNext(_ offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedItemID } ?? (offset > 0 ? -1 : items.count)
        select(items[max(0, min(items.count - 1, current + offset))])
    }

    func recoverPersistence() {
        do {
            if FileManager.default.fileExists(atPath: persistenceURL.path) {
                let backup = persistenceURL.deletingLastPathComponent().appendingPathComponent(persistenceURL.lastPathComponent + ".recovery-" + UUID().uuidString)
                try FileManager.default.copyItem(at: persistenceURL, to: backup)
            }
            persistenceBlocked = false; errorText = nil; save()
        } catch { errorText = "Couldn't preserve the saved shelf: " + error.localizedDescription }
    }

    var selectedItem: ShelfItem? {
        items.first { $0.id == selectedItemID }
    }

    func select(_ item: ShelfItem?, extending: Bool = false, range: Bool = false) {
        guard let item else { selectedIDs = []; selectedItemID = nil; return }
        if range, let anchor = items.firstIndex(where: { $0.id == selectedItemID }), let end = items.firstIndex(where: { $0.id == item.id }) {
            selectedIDs.formUnion(items[min(anchor, end)...max(anchor, end)].map(\.id))
        } else if extending {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
        } else { selectedIDs = [item.id] }
        selectedItemID = selectedIDs.contains(item.id) ? item.id : selectedItems.first?.id
    }

    func removeAll() { removeItems(items) }

#if DEBUG
    /// Local visual-QA data that never touches the persisted user shelf.
    func setPreviewItems(_ urls: [URL], selectedIndex: Int? = nil) {
        items = urls.map { ShelfItem(url: $0) }
        items.forEach(requestThumbnail)
        if let selectedIndex, items.indices.contains(selectedIndex) {
            selectedItemID = items[selectedIndex].id
            selectedIDs = [items[selectedIndex].id]
        } else {
            selectedItemID = nil
        }
    }
#endif

    private func stopSecurityScopedAccess(for url: URL) {
        guard securityScopedURLs.remove(url) != nil else { return }
        url.stopAccessingSecurityScopedResource()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func airDrop(_ item: ShelfItem) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: [item.url])
    }

    /// OCR uses the same visible, cancellable result cards as other file actions.
    func copyText(_ item: ShelfItem) {
        run(FileConverter.Action(id: "tool.ocr", title: "Copy Text", symbol: "text.viewfinder"), on: [item])
    }

    /// Every file here in one AirDrop.
    func airDropAll() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: items.map(\.url))
    }

    /// Puts the file itself on the pasteboard so it pastes into Finder,
    /// Mail or Messages like a Finder copy.
    func copyToPasteboard(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
    }

    /// Stages the ZIP and reports failures through the shared job cards.
    func compress(_ item: ShelfItem) {
        run(FileConverter.Action(id: "zip", title: "ZIP", symbol: "doc.zipper"), on: [item])
    }

    /// "Name.zip", then "Name 2.zip", matching Finder's collision naming.
    private static func availableURL(_ proposed: URL) -> URL {
        let folder = proposed.deletingLastPathComponent()
        let base = proposed.deletingPathExtension().lastPathComponent
        let pathExtension = proposed.pathExtension
        var candidate = proposed
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(index)").appendingPathExtension(pathExtension)
            index += 1
        }
        return candidate
    }

    private func requestThumbnail(for item: ShelfItem) {
        guard thumbnails[item.id] == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 44, height: 44),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        let itemID = item.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor [weak self, itemID, image] in
                guard let self, self.items.contains(where: { $0.id == itemID }) else { return }
                self.thumbnails[itemID] = image
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        let decoded: [DecodableItem]
        do { decoded = try JSONDecoder().decode([DecodableItem].self, from: Data(contentsOf: persistenceURL)) }
        catch {
            persistenceBlocked = true
            errorText = "The saved shelf couldn't be read. Preserve a recovery copy before saving new changes."
            return
        }
        if decoded.contains(where: { $0.value == nil }) {
            persistenceBlocked = true
            errorText = "Some saved entries couldn't be read. Preserve a recovery copy before saving changes."
        }
        let persisted = decoded.compactMap(\.value)

        items = persisted.compactMap { saved in
            var resolvedURL: URL?
            if let bookmark = saved.bookmark {
                var isStale = false
                resolvedURL = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            }
            let url = resolvedURL ?? URL(fileURLWithPath: saved.fallbackPath)
            if url.startAccessingSecurityScopedResource() {
                securityScopedURLs.insert(url)
            }
            return ShelfItem(id: saved.id, url: url)
        }
        pruneMissingItems()
    }

    private func save() {
        guard !persistenceBlocked else { return }
        let persisted = items.map { item in
            let bookmark = try? item.url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return PersistedItem(
                id: item.id,
                bookmark: bookmark,
                fallbackPath: item.url.path
            )
        }
        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: persistenceURL, options: .atomic)
        } catch { errorText = "Couldn't save this shelf: " + error.localizedDescription }
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
