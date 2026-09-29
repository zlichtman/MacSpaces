import AppKit

/// Fallback now-playing provider that polls Music and Spotify over AppleScript.
/// Only queries apps that are already running so it never launches a player.
final class AppleScriptProvider: NowPlayingProvider {
    private struct Player {
        let bundleID: String
        let appName: String
    }

    private struct Snapshot {
        var info: NowPlayingInfo
        var artworkURL: URL?
    }

    private let players = [
        Player(bundleID: "com.spotify.client", appName: "Spotify"),
        Player(bundleID: "com.apple.Music", appName: "Music"),
    ]
    private let artworkCache = NSCache<NSString, NSImage>()
    private let musicArtworkCache = NSCache<NSString, NSImage>()
    private let stateLock = NSLock()
    private var activePlayerBundleID: String?
    private let artworkLock = NSLock()
    private var pendingArtworkKeys = Set<String>()

    /// Provider work is serialized, while every actual script execution goes
    /// through AppleScriptRunner's app-wide queue. This prevents browser,
    /// shortcut, and media scripts from racing NSAppleScript's shared state.
    private static let workQueue = DispatchQueue(label: "opensource.nowplaying.applescript-provider")

    /// Artwork fetches use a bounded timeout so a stalled request cannot
    /// leave the now-playing UI waiting on a completion that never fires.
    private static let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    var isAvailable: Bool { !runningPlayers().isEmpty }

    private func runningPlayers() -> [Player] {
        players.filter { player in
            NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty == false
        }
    }

    func fetchNowPlaying(_ completion: @escaping (NowPlayingInfo?) -> Void) {
        let runningPlayers = runningPlayers()
        guard !runningPlayers.isEmpty else {
            completion(nil)
            return
        }

        Self.workQueue.async { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            // More than one player may be open. Prefer the player that is
            // actually playing; retain the first paused track only as a
            // fallback. A denied or stale player must not hide another one.
            var pausedCandidate: (Snapshot, Player)?
            var selected: (Snapshot, Player)?
            for player in runningPlayers {
                guard let snapshot = self.fetchSnapshot(for: player) else { continue }
                if snapshot.info.isPlaying {
                    selected = (snapshot, player)
                    break
                }
                if pausedCandidate == nil {
                    pausedCandidate = (snapshot, player)
                }
            }

            guard let (snapshot, player) = selected ?? pausedCandidate else {
                completion(nil)
                return
            }
            self.setActivePlayer(player.bundleID)
            self.publish(snapshot, player: player, completion: completion)
        }
    }

    private func setActivePlayer(_ bundleID: String) {
        stateLock.lock()
        activePlayerBundleID = bundleID
        stateLock.unlock()
    }

    private func activePlayer(from candidates: [Player]) -> Player? {
        stateLock.lock()
        let bundleID = activePlayerBundleID
        stateLock.unlock()
        return candidates.first(where: { $0.bundleID == bundleID }) ?? candidates.first
    }

    private func fetchSnapshot(for player: Player) -> Snapshot? {

        let artworkURLScript = player.bundleID == "com.spotify.client"
            ? """
                try
                    set artworkAddress to artwork url of current track
                end try
              """
            : ""
        let durationScript = player.bundleID == "com.spotify.client"
            ? "set durationValue to (duration of current track) / 1000"
            : "set durationValue to duration of current track"

        // Emits "state|||title|||artist|||album|||duration|||position|||artworkURL".
        let source = """
        tell application "\(player.appName)"
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set stateText to (player state as text)
                \(durationScript)
                set positionValue to player position
                set artworkAddress to ""
                \(artworkURLScript)
                return stateText & "|||" & trackName & "|||" & artistName & "|||" & albumName & "|||" & durationValue & "|||" & positionValue & "|||" & artworkAddress
            end if
            return ""
        end tell
        """

        let scriptResult = AppleScriptRunner.runSynchronously(source)
        let result = scriptResult.descriptor?.stringValue ?? ""

        let parts = result.components(separatedBy: "|||")
        guard !scriptResult.failed, parts.count >= 6 else { return nil }

        var info = NowPlayingInfo()
        info.isPlaying = parts[0] == "playing"
        info.title = parts[1]
        info.artist = parts[2]
        info.album = parts[3]
        info.duration = Double(parts[4]) ?? 0
        info.elapsed = Double(parts[5]) ?? 0
        let artworkURL: URL?
        if parts.count > 6,
           !parts[6].isEmpty,
           parts[6] != "missing value" {
            artworkURL = URL(string: parts[6])
        } else {
            artworkURL = nil
        }
        return info.hasTrack ? Snapshot(info: info, artworkURL: artworkURL) : nil
    }

    private func publish(
        _ snapshot: Snapshot,
        player: Player,
        completion: @escaping (NowPlayingInfo?) -> Void
    ) {
        var info = snapshot.info
        let trackKey = "\(player.bundleID)|\(info.title)|\(info.artist)|\(info.album)"

        if player.bundleID == "com.apple.Music" {
            if let cached = musicArtworkCache.object(forKey: trackKey as NSString) {
                info.artwork = cached
            } else {
                prefetchMusicArtwork(trackKey: trackKey)
            }
        }

        if info.artwork == nil, let artworkURL = snapshot.artworkURL {
            let cacheKey = artworkURL.absoluteString as NSString
            if let cached = artworkCache.object(forKey: cacheKey) {
                info.artwork = cached
            } else {
                prefetchArtwork(from: artworkURL)
            }
        }

        // Metadata is never held hostage by artwork I/O. Periodic polling
        // picks up the cached image as soon as the asynchronous fetch lands.
        completion(info)
    }

    private func prefetchMusicArtwork(trackKey: String) {
        let pendingKey = "music|\(trackKey)"
        guard beginArtworkRequest(pendingKey) else { return }
        AppleScriptRunner.run(
            "tell application \"Music\" to get data of artwork 1 of current track"
        ) { [weak self] result in
            defer { self?.endArtworkRequest(pendingKey) }
            guard let artworkData = result.descriptor?.data,
                  let artwork = NSImage(data: artworkData) else { return }
            self?.musicArtworkCache.setObject(artwork, forKey: trackKey as NSString)
        }
    }

    private func prefetchArtwork(from url: URL) {
        let pendingKey = url.absoluteString
        guard beginArtworkRequest(pendingKey) else { return }
        loadArtwork(from: url) { [weak self] _ in
            self?.endArtworkRequest(pendingKey)
        }
    }

    private func beginArtworkRequest(_ key: String) -> Bool {
        artworkLock.lock()
        defer { artworkLock.unlock() }
        return pendingArtworkKeys.insert(key).inserted
    }

    private func endArtworkRequest(_ key: String) {
        artworkLock.lock()
        pendingArtworkKeys.remove(key)
        artworkLock.unlock()
    }

    private func loadArtwork(from url: URL, completion: @escaping (NSImage?) -> Void) {
        let key = url.absoluteString as NSString
        if let cached = artworkCache.object(forKey: key) {
            completion(cached)
            return
        }

        Self.artworkSession.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else {
                completion(nil)
                return
            }
            self?.artworkCache.setObject(image, forKey: key)
            completion(image)
        }
        .resume()
    }

    func send(_ command: NowPlayingCommand) {
        guard let player = activePlayer(from: runningPlayers()) else { return }

        let verb: String
        switch command {
        case .togglePlayPause: verb = "playpause"
        case .nextTrack: verb = "next track"
        case .previousTrack: verb = "previous track"
        case .seek(let elapsed): verb = "set player position to \(elapsed)"
        }

        let source = "tell application \"\(player.appName)\" to \(verb)"
        AppleScriptRunner.run(source)
    }
}
