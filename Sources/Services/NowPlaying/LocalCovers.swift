import AppKit
import AVFoundation
import os

/// Covers and lyrics for songs Spotify plays from files on this Mac ("spotify:local:…"
/// tracks), whose covers it shares neither over AppleScript nor oEmbed. Off unless
/// Settings → Appearance → Album covers → Show covers and lyrics from your local music
/// files is on. Turning it on asks for the folder with the music in an open panel
/// (`chooseFolder`), and only files inside that folder are read: choosing it there is
/// what grants access, so macOS asks nothing even when it sits in iCloud Drive,
/// Documents or another protected place. Someone who turned the switch on before the
/// folder existed (switch on, no folder kept) still reads the folders Spotify names.
///
/// The track is matched to its file through Spotify's own index of local files
/// (`SpotifyLocalFiles`), or by name in the chosen folder; the cover is the one
/// embedded in the file (ID3 or MP4 artwork through AVFoundation), decoded and scaled
/// off the main thread on one worker. Covers are cached by the local track's ID; no match
/// or no embedded cover keeps the placeholder. The file's own lyrics (`lyrics(for:)`) are
/// read the same way, for `TeleprompterService` to prefer. Nothing is sent anywhere.
final class LocalCovers {
    static let shared = LocalCovers()

    /// Settings → Appearance → Album covers. Off by default.
    static let enabledKey = "media.localFileCovers"

    /// The folder chosen for that switch, as a security-scoped bookmark. Unset with the
    /// switch on means the folders Spotify names are read, as before the folder existed.
    static let folderKey = "media.localMusicFolder"

    static var isEnabled: Bool {
        Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" && UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// The chosen folder's name and path, read from the bookmark itself (nothing is opened).
    static func folderInfo(_ bookmark: Data) -> (name: String, path: String)? {
        guard let values = URL.resourceValues(forKeys: [.localizedNameKey, .nameKey, .pathKey], fromBookmarkData: bookmark),
              let path = values.path else { return nil }
        return (values.localizedName ?? values.name ?? URL(fileURLWithPath: path).lastPathComponent, path)
    }

    /// An open panel for the music folder (Settings runs it as a sheet), starting in the
    /// chosen folder, else the one Spotify watches, else Music.
    static func folderPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder with your music"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        let current = UserDefaults.standard.data(forKey: folderKey).flatMap(folderInfo)?.path
        panel.directoryURL = URL(fileURLWithPath: current ?? shared.sourceFolders(checked: false).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music").path, isDirectory: true)
        return panel
    }

    /// Keeps the folder chosen in `folderPanel` as a security-scoped bookmark; false if it
    /// couldn't be made, which keeps what was there.
    static func keepFolder(_ url: URL) -> Bool {
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope],
                                                   includingResourceValuesForKeys: [.localizedNameKey, .nameKey, .pathKey],
                                                   relativeTo: nil) else { return false }
        UserDefaults.standard.set(bookmark, forKey: folderKey)
        shared.folderChanged()
        return true
    }

    /// Forgets the chosen folder and turns the switch off, so nothing falls back to the
    /// folders Spotify names.
    static func removeFolder() {
        UserDefaults.standard.removeObject(forKey: folderKey)
        UserDefaults.standard.set(false, forKey: enabledKey)
        shared.folderChanged()
    }

    /// Spotify's support folder; only its `Users/*-user/local-files.bnk` and `watch-sources.bnk` are read.
    private let spotifyFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Spotify/Users", isDirectory: true)

    private let cache: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.countLimit = 32; return cache }()
    private struct State {
        var pending = Set<String>()
        /// Track IDs with no file or no cover, and when to try again.
        var misses: [String: Date] = [:]
        /// The newest request: an older one that finishes later is dropped.
        var latest: String?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let worker = DispatchQueue(label: "dev.opensource.MacSpaces.local-covers", qos: .utility)

    // Worker-only state.
    private var index: (stamp: [String: Date], entries: [SpotifyLocalFiles.Entry]) = ([:], [])
    private var listings: [String: (at: Date, paths: [String])] = [:]
    /// The chosen folder, opened under its security scope while its bookmark stays the same.
    private var scope: (bookmark: Data, url: URL, opened: Bool, prefixes: [String])?

    /// Where files may be read from: the folders Spotify names (switched on before the
    /// folder existed), the chosen folder, or nowhere (the folder is gone).
    private enum Reach {
        case spotifyFolders
        case chosen(root: String, prefixes: [String])
        case nowhere

        func allows(_ path: String) -> Bool {
            switch self {
            case .spotifyFolders: return true
            case .nowhere: return false
            case let .chosen(_, prefixes):
                return prefixes.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            }
        }
    }

    func cached(_ track: SpotifyLocalTrack) -> NSImage? {
        cache.object(forKey: track.id as NSString)
    }

    /// Calls back on the main queue with the file's cover, or nil when none is found, the
    /// request was superseded or is already running, or the setting is off.
    func fetch(_ track: SpotifyLocalTrack, completion: @escaping (NSImage?) -> Void) {
        guard Self.isEnabled else { completion(nil); return }
        let key = track.id
        if let image = cache.object(forKey: key as NSString) { completion(image); return }
        let start = state.withLock { state -> Bool in
            state.latest = key
            if let retry = state.misses[key], retry > Date() { return false }
            return state.pending.insert(key).inserted
        }
        guard start else { completion(nil); return }
        worker.async { [weak self] in
            guard let self else { return }
            let current = self.state.withLock { $0.latest == key }
            let image = current ? self.readCover(track) : nil
            self.state.withLock { state in
                state.pending.remove(key)
                if image == nil, current { state.misses[key] = Date().addingTimeInterval(120) }
            }
            if let image { self.cache.setObject(image, forKey: key as NSString) }
            let stillWanted = self.state.withLock { $0.latest == key }
            DispatchQueue.main.async { completion(stillWanted ? image : nil) }
        }
    }

    /// The switch was turned on. With no folder chosen (switched on before the folder
    /// existed) the folders Spotify plays local files from are opened now, as they always
    /// were; a chosen folder needs nothing opened ahead.
    func switchedOn() {
        guard Self.isEnabled else { return }
        state.withLock { $0.misses.removeAll() }
        worker.async { [weak self] in
            guard let self else { return }
            self.listings.removeAll()
            guard case .spotifyFolders = self.reach() else { return }
            let folders = Set(self.loadIndex().map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path })
                .union(self.sourceFolders())
            for folder in folders.sorted().prefix(16) {
                _ = try? FileManager.default.contentsOfDirectory(atPath: folder)
            }
        }
    }

    /// A folder was chosen or removed: forget what came from the old one.
    func folderChanged() {
        state.withLock { $0.misses.removeAll() }
        cache.removeAllObjects()
        worker.async { [weak self] in
            guard let self else { return }
            self.closeScope()
            _ = self.reach()
        }
    }

    // MARK: Worker

    /// Opens the chosen folder's bookmark when it changes (refreshing a stale one).
    private func reach() -> Reach {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.folderKey) else {
            closeScope()
            return .spotifyFolders
        }
        if let scope, scope.bookmark == bookmark {
            return .chosen(root: scope.url.path, prefixes: scope.prefixes)
        }
        closeScope()
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return .nowhere }
        let opened = url.startAccessingSecurityScopedResource()
        var kept = bookmark
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope],
                                                    includingResourceValuesForKeys: [.localizedNameKey, .nameKey, .pathKey],
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.folderKey)
            kept = fresh
        }
        let prefixes = Array(Set([url.standardizedFileURL.path, url.resolvingSymlinksInPath().path]))
        scope = (kept, url, opened, prefixes)
        return .chosen(root: url.path, prefixes: prefixes)
    }

    private func closeScope() {
        guard let old = scope else { return }
        if old.opened { old.url.stopAccessingSecurityScopedResource() }
        scope = nil
        listings.removeAll()
    }

    private func readCover(_ track: SpotifyLocalTrack) -> NSImage? {
        let reach = reach()
        if case .nowhere = reach { return nil }
        if let entry = SpotifyLocalFiles.match(track, in: loadIndex().filter { reach.allows($0.path) }),
           let image = embeddedCover(at: URL(fileURLWithPath: entry.path), expectedSeconds: nil) {
            return image
        }
        // Not in the index (yet): look for it by name in the chosen folder (or the ones
        // Spotify watches), and trust the file only if its length agrees.
        guard let path = pathByName(track, reach) else { return nil }
        return embeddedCover(at: URL(fileURLWithPath: path), expectedSeconds: track.seconds)
    }

    private func pathByName(_ track: SpotifyLocalTrack, _ reach: Reach) -> String? {
        let folders: [String]
        switch reach {
        case .spotifyFolders: folders = sourceFolders()
        case let .chosen(root, _): folders = [root]
        case .nowhere: return nil
        }
        return SpotifyLocalFiles.matchPath(track, in: folders.flatMap(listing(of:)))
    }

    /// False for a file iCloud hasn't downloaded (a dataless placeholder): reading it would
    /// wait for the download, so iCloud is asked to fetch it instead, and the miss's retry
    /// two minutes later finds it on disk.
    private func isOnDisk(_ url: URL) -> Bool {
        var info = stat()
        let dataless: UInt32 = 0x4000_0000 // SF_DATALESS
        var waiting = lstat(url.path, &info) == 0 && info.st_flags & dataless != 0
        if !waiting, let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
            waiting = true
        }
        if waiting { try? FileManager.default.startDownloadingUbiquitousItem(at: url) }
        return !waiting
    }

    // MARK: Lyrics

    /// Lyrics saved in the file a local track plays from: an MP4 `©lyr` tag or an ID3
    /// `USLT` frame (plain or LRC text), and an ID3 `SYLT` frame's timed lines.
    struct EmbeddedLyrics: Sendable {
        var text: String?
        var synced: [LyricLine] = []
    }

    /// The file's own lyrics, read on the same worker and behind the same switch as covers.
    /// Calls back (on the worker) with nil when the switch is off, the file isn't found or
    /// it has none.
    func lyrics(for track: SpotifyLocalTrack, completion: @escaping @Sendable (EmbeddedLyrics?) -> Void) {
        guard Self.isEnabled else { completion(nil); return }
        worker.async { [weak self] in
            completion(self?.readLyrics(track))
        }
    }

    private func readLyrics(_ track: SpotifyLocalTrack) -> EmbeddedLyrics? {
        let reach = reach()
        if case .nowhere = reach { return nil }
        if let entry = SpotifyLocalFiles.match(track, in: loadIndex().filter { reach.allows($0.path) }) {
            return embeddedLyrics(at: URL(fileURLWithPath: entry.path), expectedSeconds: nil)
        }
        guard let path = pathByName(track, reach) else { return nil }
        return embeddedLyrics(at: URL(fileURLWithPath: path), expectedSeconds: track.seconds)
    }

    /// Waits at most 8 s and skips a file iCloud hasn't downloaded, like a cover; text over
    /// 256 KB is ignored.
    private func embeddedLyrics(at url: URL, expectedSeconds: Int?) -> EmbeddedLyrics? {
        guard FileManager.default.isReadableFile(atPath: url.path), isOnDisk(url) else { return nil }
        let result = OSAllocatedUnfairLock<EmbeddedLyrics?>(initialState: nil)
        let done = DispatchSemaphore(value: 0)
        let task = Task.detached(priority: .utility) {
            defer { done.signal() }
            let asset = AVURLAsset(url: url)
            if let expectedSeconds, expectedSeconds > 0 {
                guard let duration = try? await asset.load(.duration), duration.seconds.isFinite,
                      abs(Int(duration.seconds.rounded()) - expectedSeconds) <= SpotifyLocalFiles.secondsTolerance else { return }
            }
            let items = (try? await asset.load(.metadata)) ?? []
            var found = EmbeddedLyrics()
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .id3MetadataSynchronizedLyric).prefix(2) {
                guard !Task.isCancelled else { return }
                if let data = try? await item.load(.dataValue), data.count <= 256 << 10,
                   let lines = Lyrics.parseSYLT(data) {
                    found.synced = lines.map { LyricLine(start: $0.start, end: nil, text: $0.text) }
                    break
                }
            }
            let texts = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataLyrics)
                + AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .id3MetadataUnsynchronizedLyric)
            for item in texts.prefix(2) {
                guard !Task.isCancelled else { return }
                if let text = try? await item.load(.stringValue), !text.isEmpty, text.utf8.count <= 256 << 10 {
                    found.text = text
                    break
                }
            }
            let read = found
            if read.text != nil || !read.synced.isEmpty { result.withLock { $0 = read } }
        }
        if done.wait(timeout: .now() + 8) == .timedOut { task.cancel(); return nil }
        return result.withLock { $0 }
    }

    private func spotifyUserFolders() -> [URL] {
        let users = (try? FileManager.default.contentsOfDirectory(at: spotifyFolder, includingPropertiesForKeys: nil)) ?? []
        return users.filter { $0.lastPathComponent.hasSuffix("-user") }
    }

    /// Every account's index, read again only when one of the files changes (Spotify
    /// rewrites it as it rescans). Files over 8 MB are skipped.
    private func loadIndex() -> [SpotifyLocalFiles.Entry] {
        var stamp: [String: Date] = [:]
        let files = spotifyUserFolders().map { $0.appendingPathComponent("local-files.bnk") }
        for file in files {
            if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
               let modified = values.contentModificationDate, (values.fileSize ?? 0) <= 8 << 20 {
                stamp[file.path] = modified
            }
        }
        if stamp == index.stamp { return index.entries }
        var seen = Set<String>()
        let entries = stamp.keys.sorted().flatMap { path -> [SpotifyLocalFiles.Entry] in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
            return SpotifyLocalFiles.entries(inIndex: data)
        }.filter { seen.insert($0.path).inserted }
        index = (stamp, entries)
        return entries
    }

    /// The folders `watch-sources.bnk` lists. `checked` keeps only those that exist; the open
    /// panel's starting folder skips that, since looking inside iCloud Drive or Documents is
    /// what makes macOS ask. Touches no worker state, so the main thread may call it.
    private func sourceFolders(checked: Bool = true) -> [String] {
        var folders: [String] = []
        for user in spotifyUserFolders() {
            let file = user.appendingPathComponent("watch-sources.bnk")
            guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 1 << 20,
                  let data = try? Data(contentsOf: file),
                  let payload = SpotifyLocalFiles.deflatePayload(inBnk: data),
                  let inflated = try? (payload as NSData).decompressed(using: .zlib) as Data,
                  inflated.count <= 8 << 20 else { continue }
            for folder in SpotifyLocalFiles.sourceFolders(inWatchSources: inflated) where !folders.contains(folder) {
                var isDirectory: ObjCBool = false
                if !checked || (FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue) {
                    folders.append(folder)
                }
            }
        }
        return folders
    }

    /// The audio files under a folder, at most 20,000 and five levels deep, kept ten minutes.
    private func listing(of folder: String) -> [String] {
        if let cached = listings[folder], Date().timeIntervalSince(cached.at) < 600 { return cached.paths }
        var paths: [String] = []
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            var visited = 0
            for case let url as URL in walker {
                visited += 1
                if visited > 20_000 { break }
                if walker.level > 5 { walker.skipDescendants(); continue }
                if SpotifyLocalFiles.audioExtensions.contains(url.pathExtension.lowercased()) { paths.append(url.path) }
            }
        }
        listings[folder] = (Date(), paths)
        return paths
    }

    /// The first embedded picture (iTunes `covr` or ID3 `APIC`), at most 16 MB, scaled to
    /// `NowPlayingInfo.coverPixels`. Waits at most 8 s; a file iCloud hasn't downloaded is
    /// skipped (and fetched) rather than read.
    private func embeddedCover(at url: URL, expectedSeconds: Int?) -> NSImage? {
        guard FileManager.default.isReadableFile(atPath: url.path), isOnDisk(url) else { return nil }
        let result = OSAllocatedUnfairLock<Data?>(initialState: nil)
        let done = DispatchSemaphore(value: 0)
        let task = Task.detached(priority: .utility) {
            defer { done.signal() }
            let asset = AVURLAsset(url: url)
            if let expectedSeconds, expectedSeconds > 0 {
                guard let duration = try? await asset.load(.duration), duration.seconds.isFinite,
                      abs(Int(duration.seconds.rounded()) - expectedSeconds) <= SpotifyLocalFiles.secondsTolerance else { return }
            }
            var items = (try? await asset.load(.commonMetadata)) ?? []
            var pictures = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork)
            if pictures.isEmpty {
                items = (try? await asset.load(.metadata)) ?? []
                pictures = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataCoverArt)
                    + AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .id3MetadataAttachedPicture)
            }
            for picture in pictures.prefix(2) {
                guard !Task.isCancelled else { return }
                if let data = try? await picture.load(.dataValue), !data.isEmpty, data.count <= 16 << 20 {
                    result.withLock { $0 = data }
                    return
                }
            }
        }
        if done.wait(timeout: .now() + 8) == .timedOut { task.cancel(); return nil }
        return result.withLock { $0 }.flatMap(NowPlayingInfo.cover(from:))
    }
}
