import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import os

/// A file's picture in the Tray: a Quick Look thumbnail of its content where
/// one exists (images, screenshots, PDFs, video, documents), else its icon.
struct TrayPreview: @unchecked Sendable {
    let image: NSImage
    /// A content thumbnail, not the file's icon.
    let isContent: Bool
}

/// Quick Look thumbnails for the Tray, baskets and the closed-notch screenshot,
/// generated off the main thread and kept in a bounded cache keyed by file and
/// modification date (an edited file gets a new thumbnail).
final class TrayThumbnails: @unchecked Sendable {
    static let shared = TrayThumbnails()
    /// Points; tiles draw at most this large.
    static let size = CGSize(width: 132, height: 96)

    private final class Entry { let preview: TrayPreview; init(_ preview: TrayPreview) { self.preview = preview } }
    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 240
        cache.totalCostLimit = 48 << 20
        return cache
    }()
    /// One generation per key at a time; later callers wait for it.
    private let inFlight = OSAllocatedUnfairLock(initialState: [String: Task<TrayPreview?, Never>]())

    func cached(for url: URL, modified: Date?) -> TrayPreview? {
        cache.object(forKey: Self.key(url, modified) as NSString)?.preview
    }

    func preview(for url: URL, modified: Date?, scale: CGFloat = 2) async -> TrayPreview? {
        let key = Self.key(url, modified)
        if let hit = cache.object(forKey: key as NSString) { return hit.preview }
        let task = inFlight.withLock { running -> Task<TrayPreview?, Never> in
            if let task = running[key] { return task }
            let task = Task.detached(priority: .utility) { await Self.generate(url, scale: scale) }
            running[key] = task
            return task
        }
        let preview = await task.value
        inFlight.withLock { _ = $0.removeValue(forKey: key) }
        if let preview {
            let pixels = preview.image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
            cache.setObject(Entry(preview), forKey: key as NSString, cost: max(pixels, 1) * 4)
        }
        return preview
    }

    private static func generate(_ url: URL, scale: CGFloat) async -> TrayPreview? {
        // A short text file's thumbnail is a near-blank white page at tile
        // size; its icon says more. Rich documents (PDF, RTF, Pages) keep theirs.
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        let plain = type.map { $0.conforms(to: .text) && !$0.conforms(to: .rtf) && !$0.conforms(to: .html) } ?? false
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale,
                                                   representationTypes: plain ? .icon : [.icon, .thumbnail])
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return TrayPreview(image: representation.nsImage, isContent: representation.type == .thumbnail)
    }

    private static func key(_ url: URL, _ modified: Date?) -> String {
        url.standardizedFileURL.path + "|" + String(modified?.timeIntervalSinceReferenceDate ?? 0)
    }
}
