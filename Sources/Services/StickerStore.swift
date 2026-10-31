import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

/// Fluent Emoji files for the Scenes lyric style. The curated subjects' pictures ship
/// in the app (`scene-<subject>`, instant and offline); any other emoji is downloaded
/// once from Microsoft's GitHub (only that emoji's file is requested, never the lyric),
/// downscaled to 192 px and kept in Caches/<bundle id>/stickers: the still as PNG and
/// Microsoft's animation as a HEIC sequence (APNG where HEIC can't be written) at no
/// more than 20 frames a second. The cache holds at most 80 MB; the least recently
/// shown go first. Downloads run two at a time off the main thread, each file once, with
/// no retries (a failure is remembered for ten minutes). A song's stickers are fetched
/// when its lyrics load and dropped when the song changes. Only the real app downloads;
/// Debug harnesses use the bundled pictures.
final class StickerStore: @unchecked Sendable {
    static let shared = StickerStore()

    static let side = 192
    static let cacheLimit = 80 * 1_024 * 1_024
    /// Most emoji fetched ahead for one song (stills first, then animations).
    static let songLimit = 24

    /// nil outside the real app: no cache and no downloads.
    let directory: URL?
    private let downloads: Downloads
    private let ready = OSAllocatedUnfairLock(initialState: false)
    private let song = OSAllocatedUnfairLock(initialState: 0)
    private static let worker = DispatchQueue(label: "dev.opensource.MacSpaces.stickers", qos: .utility)

    private init() {
        let real = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
        directory = real ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dev.opensource.MacSpaces", isDirectory: true)
            .appendingPathComponent("stickers", isDirectory: true) : nil
        downloads = Downloads(directory: directory)
    }

    // MARK: Catalog

    /// Decoded once, on first use (a thread-safe lazy static).
    private static let catalog: StickerIndex? = {
        guard let url = Bundle.main.url(forResource: "sticker-index", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? StickerIndex(data: data)
    }()

    /// The catalog, loading it if needed. Blocks, so never on the main thread.
    var index: StickerIndex? {
        let index = Self.catalog
        ready.withLock { $0 = true }
        return index
    }

    /// The catalog if it has loaded; otherwise nil while it loads in the background.
    var indexIfLoaded: StickerIndex? {
        if ready.withLock({ $0 }) { return Self.catalog }
        Self.worker.async { [self] in _ = index }
        return nil
    }

    // MARK: Files

    /// The bundled picture of a curated subject.
    static func bundledURL(_ name: String) -> URL? {
        guard let subject = StickerMatch.bundledSubject[name] else { return nil }
        let file = "scene-\(subject.rawValue)"
        return Bundle.main.url(forResource: file, withExtension: "webp") ?? Bundle.main.url(forResource: file, withExtension: "png")
    }

    /// The best file there is for an emoji now: bundled, else its cached animation, else
    /// its cached still; nil when it hasn't been downloaded. Touches the cached file so
    /// the cache keeps what's shown. Reads the disk, so off the main thread.
    func localFile(_ name: String) -> URL? {
        if let bundled = Self.bundledURL(name) { return bundled }
        guard let directory else { return nil }
        let manager = FileManager.default
        for file in Self.files(name).reversed() {
            let url = directory.appendingPathComponent(file)
            guard manager.fileExists(atPath: url.path) else { continue }
            try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return url
        }
        return nil
    }

    /// Cached file names: the still, then the animation (HEIC sequence or APNG).
    static func files(_ name: String) -> [String] {
        let slug = String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return ["\(slug).png", "\(slug)-animated.png", "\(slug).heics"]
    }

    /// Starts this emoji's download now (ahead of a song's queue) and waits up to
    /// `seconds` for a file to show. nil when it isn't ready by then; the download
    /// carries on for the next time.
    func request(_ name: String, waitingUpTo seconds: Double) async -> URL? {
        if let bundled = Self.bundledURL(name) { return bundled }
        guard directory != nil, let index, let item = index.named(name) else { return nil }
        await downloads.enqueue(Self.jobs([item], in: index), front: true)
        await downloads.wait(for: Self.files(name)[0], seconds: seconds)
        return localFile(name)
    }

    /// A new song: what was queued for the last one is dropped. Call before
    /// `prefetch(_:song:)`; the token keeps a late prefetch from an older song out.
    func beginSong() -> Int { song.withLock { $0 += 1; return $0 } }

    /// Fetches these emoji ahead of their lines: every still first, then the animations.
    /// Loads the catalog if needed, so off the main thread.
    func prefetch(_ names: [String], song token: Int) {
        guard directory != nil, song.withLock({ $0 == token }), let index else { return }
        let items = names.compactMap(index.named).filter { Self.bundledURL($0.name) == nil }.prefix(Self.songLimit)
        let stills = Self.jobs(Array(items), in: index).filter { !$0.animated }
        let animations = Self.jobs(Array(items), in: index).filter(\.animated)
        Task { await downloads.replaceSong(stills + animations, song: token) }
    }

    /// Stops fetching for the current song.
    func cancelSong() {
        let token = beginSong()
        Task { await downloads.replaceSong([], song: token) }
    }

    fileprivate struct Job: Sendable {
        let url: URL
        let file: String
        let animated: Bool
    }

    private static func jobs(_ items: [StickerIndex.Emoji], in index: StickerIndex) -> [Job] {
        items.flatMap { item -> [Job] in
            let files = Self.files(item.name)
            var jobs: [Job] = []
            if let still = index.stillURL(item) { jobs.append(Job(url: still, file: files[0], animated: false)) }
            if let moving = index.animatedURL(item) { jobs.append(Job(url: moving, file: files[2], animated: true)) }
            return jobs
        }
    }

    // MARK: Downloads

    /// The download queue: at most two at once, each file once, queued work for an old
    /// song dropped, failures remembered rather than retried.
    private actor Downloads {
        private let directory: URL?
        private var queue: [(job: Job, song: Int?)] = []
        private var running: [String: (task: Task<Void, Never>, song: Int?)] = [:]
        private var waiters: [String: [UUID: CheckedContinuation<Void, Never>]] = [:]
        private var failed: [String: Date] = [:]
        private var written = 0
        private static let limit = 2

        private static let session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            configuration.timeoutIntervalForResource = 30
            configuration.httpMaximumConnectionsPerHost = 2
            configuration.waitsForConnectivity = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            return URLSession(configuration: configuration)
        }()

        init(directory: URL?) { self.directory = directory }

        func enqueue(_ jobs: [Job], front: Bool, song: Int? = nil) {
            let fresh = jobs.filter(wanted)
            queue.removeAll { entry in fresh.contains { $0.file == entry.job.file } }
            let entries = fresh.map { (job: $0, song: song) }
            queue = front ? entries + queue : queue + entries
            pump()
        }

        func replaceSong(_ jobs: [Job], song: Int) {
            let files = Set(jobs.map(\.file))
            queue.removeAll { $0.song != nil }
            for (file, entry) in running where entry.song != nil && !files.contains(file) {
                entry.task.cancel()
            }
            enqueue(jobs, front: false, song: song)
        }

        /// Not on disk, not already on its way, not failed lately.
        private func wanted(_ job: Job) -> Bool {
            guard let directory, running[job.file] == nil else { return false }
            if let date = failed[job.file], Date().timeIntervalSince(date) < 600 { return false }
            return !FileManager.default.fileExists(atPath: directory.appendingPathComponent(job.file).path)
                && !(job.animated && FileManager.default.fileExists(atPath: directory.appendingPathComponent(
                    job.file.replacingOccurrences(of: ".heics", with: "-animated.png")).path))
        }

        private func pump() {
            while running.count < Self.limit, !queue.isEmpty {
                let (job, song) = queue.removeFirst()
                guard running[job.file] == nil, let directory else { continue }
                let task = Task.detached(priority: .utility) { [self, job, directory] in
                    let ok = await Self.fetch(job, into: directory)
                    await self.finished(job, ok: ok, cancelled: Task.isCancelled)
                }
                running[job.file] = (task, song)
            }
        }

        private func finished(_ job: Job, ok: Bool, cancelled: Bool) {
            running[job.file] = nil
            if ok { written += 1 } else if !cancelled { failed[job.file] = Date() }
            for continuation in (waiters.removeValue(forKey: job.file) ?? [:]).values { continuation.resume() }
            if ok, written % 8 == 1, let directory { StickerStore.worker.async { Self.trim(directory) } }
            pump()
        }

        /// Returns when the file is written or failed, or after `seconds`.
        func wait(for file: String, seconds: Double) async {
            guard running[file] != nil || queue.contains(where: { $0.job.file == file }) else { return }
            let id = UUID()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waiters[file, default: [:]][id] = continuation
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                    await self?.timeOut(file, id: id)
                }
            }
        }

        private func timeOut(_ file: String, id: UUID) {
            waiters[file]?.removeValue(forKey: id)?.resume()
        }

        /// Downloads one file from Microsoft's GitHub and writes the 192 px copy.
        private static func fetch(_ job: Job, into directory: URL) async -> Bool {
            var request = URLRequest(url: job.url)
            request.setValue(TeleprompterService.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request), !Task.isCancelled,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let host = http.url?.host, StickerIndex.hosts.contains(host),
                  data.count < 8 * 1_024 * 1_024 else { return false }
            return await withCheckedContinuation { continuation in
                StickerStore.worker.async {
                    let ok = autoreleasepool { StickerStore.write(data, job: job, into: directory) }
                    continuation.resume(returning: ok)
                }
            }
        }

        /// Keeps the cache under its limit, dropping the least recently shown.
        nonisolated private static func trim(_ directory: URL) {
            let manager = FileManager.default
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
            var entries = files.compactMap { url -> (URL, Date, Int)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
            }
            var total = entries.reduce(0) { $0 + $1.2 }
            guard total > StickerStore.cacheLimit else { return }
            entries.sort { $0.1 < $1.1 }
            for (url, _, size) in entries where total > StickerStore.cacheLimit * 4 / 5 {
                try? manager.removeItem(at: url)
                total -= size
            }
        }
    }

    // MARK: Downscaling

    /// Writes the still as a 192 px PNG, or the animation as a 192 px HEIC sequence
    /// (APNG where HEIC can't be written) at no more than 20 frames a second.
    fileprivate static func write(_ data: Data, job: Job, into directory: URL) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(job.file)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: side, kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        func frame(_ index: Int) -> CGImage? { CGImageSourceCreateThumbnailAtIndex(source, index, options) }

        guard job.animated else {
            guard let still = frame(0), still.width >= 32,
                  let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { return false }
            CGImageDestinationAddImage(destination, still, nil)
            return CGImageDestinationFinalize(destination) && move(temporary, to: target)
        }
        // Keep a frame each 1/20 s, holding it for the delays of the frames dropped.
        let count = min(CGImageSourceGetCount(source), 400)
        var kept: [(index: Int, delay: Double)] = []
        var pending = 0.0
        for index in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let raw = (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (png?[kCGImagePropertyAPNGDelayTime] as? NSNumber)?.doubleValue ?? 0.05
            let delay = raw.isFinite && raw > 0 ? raw : 0.05
            if kept.isEmpty || pending >= 0.05 - 0.001 {
                kept.append((index, delay)); pending = delay
            } else {
                kept[kept.count - 1].delay += delay; pending += delay
            }
        }
        guard kept.count > 1 else { return false }
        func encode(_ type: UTType, into url: URL) -> Bool {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, kept.count, nil)
            else { return false }
            if type == .png {
                CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: 1]] as CFDictionary)
            }
            for (index, delay) in kept {
                guard let image = autoreleasepool(invoking: { frame(index) }) else { return false }
                let timing: [CFString: Any] = type == .png
                    ? [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]]
                    : [kCGImagePropertyHEICSDictionary: [kCGImagePropertyHEICSDelayTime: delay],
                       kCGImageDestinationLossyCompressionQuality: 0.75]
                CGImageDestinationAddImage(destination, image, timing as CFDictionary)
            }
            return CGImageDestinationFinalize(destination)
        }
        if let heics = UTType("public.heics"), encode(heics, into: temporary) { return move(temporary, to: target) }
        try? FileManager.default.removeItem(at: temporary)
        let apng = directory.appendingPathComponent(job.file.replacingOccurrences(of: ".heics", with: "-animated.png"))
        return encode(.png, into: temporary) && move(temporary, to: apng)
    }

    private static func move(_ from: URL, to target: URL) -> Bool {
        try? FileManager.default.removeItem(at: target)
        return (try? FileManager.default.moveItem(at: from, to: target)) != nil
    }
}
