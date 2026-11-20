import AppKit
import UniformTypeIdentifiers

/// A place in the Folio page's sidebar: everything, the Tray (the inbox), the clipboard's
/// history, File Tools, a smart folder over every list, one basket (a collection), or one
/// watched folder's new files.
enum FolioPlace: Hashable {
    case all, tray, clipboard, tools, trash, colors, links
    case smart(FolioSmartFolder)
    case basket(UUID)
    case watched(UUID)

    var isWatched: Bool { if case .watched = self { return true } else { return false } }

    /// The place's own id, which keeps its board (`FolioBoards`).
    var key: String {
        switch self {
        case .all: return "all"
        case .tray: return "tray"
        case .clipboard: return "clipboard"
        case .tools: return "tools"
        case .trash: return "trash"
        case .colors: return "colors"
        case .links: return "links"
        case .smart(let folder): return "smart:" + folder.rawValue
        case .basket(let id): return "basket:" + id.uuidString
        case .watched(let id): return "watched:" + id.uuidString
        }
    }

    /// Places that show files, so they have views and boards.
    var showsFiles: Bool { self != .clipboard && self != .tools && self != .colors && self != .links }
}

/// Folio's own small files, beside the Tray's lists in Application Support (a temporary folder
/// for the check harnesses, which run under their own bundle identifiers).
enum FolioStorage {
    static var folder: URL {
        let root = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests"))
        return root.appendingPathComponent("MacSpaces", isDirectory: true)
    }

    static func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

    /// Reads a small JSON on the disk worker: nil when there's none; a damaged one is kept
    /// beside it (`.damaged`) so it's never written over unseen.
    static func read<Value: Decodable>(_ type: Value.Type, from file: URL) -> Value? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        if let value = try? JSONDecoder().decode(type, from: data) { return value }
        let keep = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".damaged")
        try? FileManager.default.removeItem(at: keep)
        try? FileManager.default.copyItem(at: file, to: keep)
        return nil
    }

    /// Writes a small JSON on the disk worker.
    static func write<Value: Encodable>(_ value: Value, to file: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Folders that fill themselves from what Folio knows about each file (Liked from your likes).
enum FolioSmartFolder: String, CaseIterable, Hashable {
    case liked, pictures, pdfs, withText

    var title: String {
        switch self {
        case .liked: return "Liked"
        case .pictures: return "Pictures"
        case .pdfs: return "PDFs"
        case .withText: return "With Text"
        }
    }

    var symbol: String {
        switch self {
        case .liked: return "heart"
        case .pictures: return "photo"
        case .pdfs: return "doc.richtext"
        case .withText: return "text.viewfinder"
        }
    }

    @MainActor func holds(_ item: ShelfItem, info: ShelfFileInfo?, library: FolioIndex) -> Bool {
        switch self {
        case .liked: return library.isLiked(item.url)
        case .pictures: return info?.isImage == true
        case .pdfs: return UTType(filenameExtension: item.url.pathExtension)?.conforms(to: .pdf) == true
        case .withText: return !(library.record(for: item.url)?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}

/// One file shown on the Folio page, with the list it belongs to.
struct FolioEntry: Identifiable {
    let store: ShelfStore
    let item: ShelfItem
    var id: UUID { item.id }
}

@MainActor
enum FolioPlaces {
    /// The files a place shows, in order, narrowed by the filter. A file held by several lists
    /// shows once in All and the smart folders (the Tray's, else the first basket's). `baskets` is
    /// every list after the Tray: the baskets, then watched folders.
    static func entries(_ place: FolioPlace, tray: ShelfStore, baskets: [ShelfStore], filter: FolioFilter,
                        library: FolioIndex) -> [FolioEntry] {
        let stores: [ShelfStore]
        switch place {
        case .clipboard, .tools, .colors, .links: return []
        case .tray: stores = [tray]
        case .trash: stores = [FolioTrash.shared.store]
        case .basket(let id): stores = baskets.filter { $0.listID == id }
        case .watched(let id): stores = baskets.filter { $0.watchedID == id }
        case .all, .smart: stores = [tray] + baskets
        }
        var seen = Set<String>()
        var result: [FolioEntry] = []
        for store in stores {
            let matching = filter.matches(in: store, library)
            for item in store.items {
                if let matching, !matching.contains(item.id) { continue }
                if case .smart(let folder) = place, !folder.holds(item, info: store.info[item.id], library: library) { continue }
                if stores.count > 1, !seen.insert(item.url.standardizedFileURL.path).inserted { continue }
                result.append(FolioEntry(store: store, item: item))
            }
        }
        return result
    }
}

/// Folio's justified rows: pictures keep their shape, each full row fills the width at close
/// to `target` high, and the last row stays at `target`, aligned left.
enum FolioRows {
    static func layout(aspects: [CGFloat], width: CGFloat, target: CGFloat, gap: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let usable = max(1, width)
        var frames: [CGRect] = []
        frames.reserveCapacity(aspects.count)
        var y: CGFloat = 0, row: [CGFloat] = [], sum: CGFloat = 0
        func place(_ row: [CGFloat], height: CGFloat) {
            var x: CGFloat = 0
            for aspect in row {
                frames.append(CGRect(x: x, y: y, width: aspect * height, height: height))
                x += aspect * height + gap
            }
            y += height + gap
        }
        for raw in aspects {
            let aspect = max(0.4, min(3, raw.isFinite && raw > 0 ? raw : 1))
            row.append(aspect); sum += aspect
            let height = (usable - CGFloat(row.count - 1) * gap) / sum
            if height <= target { place(row, height: height); row.removeAll(keepingCapacity: true); sum = 0 }
        }
        // The last row at the target height, unless that would overflow (one very wide picture).
        if !row.isEmpty { place(row, height: min(target, (usable - CGFloat(row.count - 1) * gap) / sum)) }
        return (frames, max(0, y - gap))
    }
}
