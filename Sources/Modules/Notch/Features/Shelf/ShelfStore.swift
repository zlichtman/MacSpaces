import AppKit
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
}

/// Holds files dropped onto the notch. Security-scoped bookmarks make the
/// tray survive relaunches while keeping the underlying files in place.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var selectedItemID: UUID?

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
        guard !items.contains(where: { $0.url == url }) else { return }
        withAnimation(Design.spring()) {
            items.insert(ShelfItem(url: url), at: 0)
        }
        save()
    }

    func remove(_ item: ShelfItem) {
        withAnimation(Design.spring()) {
            items.removeAll { $0.id == item.id }
        }
        stopSecurityScopedAccess(for: item.url)
        if selectedItemID == item.id {
            selectedItemID = nil
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
