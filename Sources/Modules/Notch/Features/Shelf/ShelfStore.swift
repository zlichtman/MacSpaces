import AppKit
import QuickLookThumbnailing
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
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedItemID: UUID?
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

    private static var persistenceURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacSpaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tray.json")
    }

    init() {
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
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self.add(url: url)
                }
            }
        }
        return accepted
    }

    func add(url: URL) {
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
        withAnimation(Design.spring()) {
            items.insert(item, at: 0)
        }
        requestThumbnail(for: item)
        save()
    }

    func remove(_ item: ShelfItem) {
        withAnimation(Design.spring()) {
            items.removeAll { $0.id == item.id }
        }
        stopSecurityScopedAccess(for: item.url)
        thumbnails[item.id] = nil
        if selectedItemID == item.id {
            selectedItemID = nil
        }
        save()
    }

    /// Files moved or deleted since they were staged leave the tray rather
    /// than lingering as dead tiles.
    func pruneMissingItems() {
        let missing = items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        guard !missing.isEmpty else { return }
        let missingIDs = Set(missing.map(\.id))
        withAnimation(Design.spring()) {
            items.removeAll { missingIDs.contains($0.id) }
        }
        for item in missing {
            stopSecurityScopedAccess(for: item.url)
            thumbnails[item.id] = nil
        }
        if let selectedItemID, missingIDs.contains(selectedItemID) {
            self.selectedItemID = nil
        }
        save()
    }

    var selectedItem: ShelfItem? {
        items.first { $0.id == selectedItemID }
    }

    func select(_ item: ShelfItem?) {
        selectedItemID = item?.id
    }

    func removeAll() {
        withAnimation(Design.spring()) {
            items.removeAll()
        }
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs.removeAll()
        thumbnails.removeAll()
        selectedItemID = nil
        save()
    }

#if DEBUG
    /// Local visual-QA data that never touches the persisted user shelf.
    func setPreviewItems(_ urls: [URL], selectedIndex: Int? = nil) {
        items = urls.map { ShelfItem(url: $0) }
        if let selectedIndex, items.indices.contains(selectedIndex) {
            selectedItemID = items[selectedIndex].id
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

    /// Puts the file itself on the pasteboard so it pastes into Finder,
    /// Mail or Messages like a Finder copy.
    func copyToPasteboard(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
    }

    /// Creates a Finder-compatible ZIP next to the original (or in Downloads
    /// when that folder is read-only) and stages the archive in the tray.
    func compress(_ item: ShelfItem) {
        guard !busyItemIDs.contains(item.id) else { return }
        let source = item.url
        let sourceFolder = source.deletingLastPathComponent()
        let folder = FileManager.default.isWritableFile(atPath: sourceFolder.path)
            ? sourceFolder
            : FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = Self.availableURL(
            folder.appendingPathComponent(source.lastPathComponent).appendingPathExtension("zip")
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, destination.path]
        let itemID = item.id
        process.terminationHandler = { [weak self] process in
            let succeeded = process.terminationStatus == 0
            Task { @MainActor [weak self, itemID, destination, succeeded] in
                guard let self else { return }
                self.busyItemIDs.remove(itemID)
                guard succeeded else { return }
                self.add(url: destination)
                self.selectedItemID = self.items.first(where: { $0.url == destination })?.id
            }
        }
        do {
            try process.run()
            busyItemIDs.insert(itemID)
        } catch {
            return
        }
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
        guard let data = try? Data(contentsOf: Self.persistenceURL),
              let decoded = try? JSONDecoder().decode([DecodableItem].self, from: data) else {
            return
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
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            if url.startAccessingSecurityScopedResource() {
                securityScopedURLs.insert(url)
            }
            return ShelfItem(id: saved.id, url: url)
        }
    }

    private func save() {
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
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: Self.persistenceURL, options: .atomic)
    }
}
