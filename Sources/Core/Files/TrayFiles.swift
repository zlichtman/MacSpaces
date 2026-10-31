import Foundation

/// Where a Tray reference stands on disk. Checked on a background worker; the
/// Tray repoints moved files, keeps files on a disconnected drive and drops
/// the rest (deleted, or moved to the Trash) without a per-file warning.
enum TrayFileState: Equatable, Sendable {
    case present
    /// Renamed or moved while the Tray held it; the bookmark found it here.
    case moved(URL)
    /// On a volume that isn't mounted, or an iCloud file not downloaded yet.
    case offline
    /// Deleted, or in the Trash: nothing left to hand to another app.
    case gone

    /// Inspects one reference. File I/O: never call it on the main thread.
    static func inspect(_ url: URL, bookmark: Data?, fileManager: FileManager = .default) -> TrayFileState {
        if fileManager.fileExists(atPath: url.path) {
            return TrayFiles.isInTrash(url, fileManager: fileManager) ? .gone : .present
        }
        if let bookmark, let resolved = TrayFiles.resolve(bookmark), resolved.standardizedFileURL != url.standardizedFileURL,
           fileManager.fileExists(atPath: resolved.path), !TrayFiles.isInTrash(resolved, fileManager: fileManager) {
            return .moved(resolved)
        }
        if TrayFiles.hasCloudPlaceholder(for: url, fileManager: fileManager) { return .offline }
        if let volume = TrayFiles.volumeRoot(of: url), !fileManager.fileExists(atPath: volume.path) { return .offline }
        return .gone
    }
}

enum TrayFiles {
    /// Security-scoped first (how the Tray saves them), then plain. Never
    /// mounts a volume or shows UI.
    static func resolve(_ bookmark: Data) -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        return try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    static func bookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    /// The user's Trash, any volume's `.Trashes`, or a `.Trash` folder.
    static func isInTrash(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        if components.contains(".Trash") || components.contains(".Trashes") { return true }
        var relationship: FileManager.URLRelationship = .other
        if (try? fileManager.getRelationship(&relationship, of: .trashDirectory, in: .userDomainMask, toItemAt: url)) != nil {
            return relationship == .contains
        }
        return false
    }

    /// `/Volumes/<name>` for files on another volume; nil on the startup disk.
    static func volumeRoot(of url: URL) -> URL? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count > 2, components[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/" + components[2], isDirectory: true)
    }

    /// macOS 13 replaces an evicted iCloud Drive file with `.<name>.icloud`.
    static func hasCloudPlaceholder(for url: URL, fileManager: FileManager = .default) -> Bool {
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        return fileManager.fileExists(atPath: placeholder.path)
    }

    /// The name a tile shows: no extension (the badge shows the type), and
    /// today's screenshots without the repeated date.
    static func displayName(_ fileName: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let ext = (fileName as NSString).pathExtension
        var base = ext.isEmpty || ext.count > 6 ? fileName : (fileName as NSString).deletingPathExtension
        if base.isEmpty { base = fileName }
        let stamp = Self.dateStamp(now, calendar: calendar)
        for joiner in [" " + stamp + " at ", " " + stamp + " "] {
            if let range = base.range(of: joiner), range.lowerBound > base.startIndex {
                base.replaceSubrange(range, with: " at ")
                break
            }
        }
        return base
    }

    /// The short type badge on a tile, e.g. "PDF", "PNG"; nil for folders and long extensions.
    static func badge(_ fileName: String, isDirectory: Bool) -> String? {
        let ext = (fileName as NSString).pathExtension
        guard !isDirectory, (1...5).contains(ext.count) else { return nil }
        return ext.uppercased()
    }

    /// Names for pasted or dropped content the Tray writes to disk: what it
    /// is and when, so it reads well in the Tray and in the app it lands in.
    static func stagedName(for kind: StagedKind, now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let when = formatter.string(from: now)
        switch kind {
        case .image: return "Pasted Image " + when
        case .text(let text):
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let cleaned = sanitized(line)
            return cleaned.isEmpty ? "Pasted Text " + when : String(cleaned.prefix(48)).trimmingCharacters(in: .whitespaces)
        case .link(let url):
            let host = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
            let cleaned = sanitized(host)
            return cleaned.isEmpty ? "Link " + when : cleaned
        }
    }

    enum StagedKind { case image, text(String), link(URL) }

    /// Strips characters Finder won't put in a name.
    private static func sanitized(_ text: String) -> String {
        String(text.map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 })
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
    }

    private static func dateStamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Puts removed entries back at their old positions, skipping any the list
    /// already holds (by id or by file), so items added since stay in place.
    static func restoring<Item>(_ removed: [(index: Int, item: Item)], into items: [Item],
                                same: (Item, Item) -> Bool) -> [Item] {
        var result = items
        for entry in removed.sorted(by: { $0.index < $1.index }) where !result.contains(where: { same($0, entry.item) }) {
            result.insert(entry.item, at: min(entry.index, result.count))
        }
        return result
    }

    /// "8 items · 24.3 MB" (sizes known so far; folders count as items only).
    static func summary(count: Int, bytes: Int64) -> String {
        let items = count == 1 ? "1 item" : "\(count) items"
        guard bytes > 0 else { return items }
        return items + " · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
