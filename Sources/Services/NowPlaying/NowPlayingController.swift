import AppKit
import Combine

/// Facade over the available now-playing providers. Prefers the system-wide
/// MediaRemote provider and transparently falls back to AppleScript polling
/// of Music/Spotify, then supported browser tabs, when MediaRemote yields
/// nothing. Native players are checked before browsers because a running
/// browser is not evidence that its front tab owns the active audio session.
@MainActor
final class NowPlayingController: ObservableObject {
    @Published private(set) var info = NowPlayingInfo()
    @Published private(set) var hasCompletedInitialRefresh = false

    @Published var selectedSource: PlaybackSource {
        didSet {
            guard oldValue != selectedSource else { return }
            UserDefaults.standard.set(selectedSource.rawValue, forKey: "media.source")
            let wasActive = isActive
            stop()
            if wasActive { start() }
        }
    }
    @Published private(set) var commandError: String?
    @Published private(set) var isSending = false
    /// The state a play/pause press asked for, shown until the player
    /// confirms it or a short grace period passes. A rejected command
    /// therefore reverts on its own instead of claiming success.
    @Published private(set) var pendingIsPlaying: Bool?
    /// When `info.elapsed` was last read, for smooth progress between polls.
    @Published private(set) var elapsedReadAt = Date()
    private var pendingExpiry: DispatchWorkItem?
    private var contextID = UUID().uuidString
    private let actions: ActionRegistry
    private let music = AppleScriptProvider(preferredBundleID: "com.apple.Music")
    private let spotify = AppleScriptProvider(preferredBundleID: "com.spotify.client")

    init(actions: ActionRegistry? = nil) {
        self.actions = actions ?? ActionRegistry()
        selectedSource = PlaybackSource(rawValue: UserDefaults.standard.string(forKey: "media.source") ?? "") ?? .automatic
        registerActions()
    }

    private let mediaRemote = MediaRemoteProvider()
    private let appleScript = AppleScriptProvider()
    private lazy var browser = BrowserMediaProvider(transport: mediaRemote)
    private var timer: Timer?
    private var artworkObserver: NSObjectProtocol?
    private var isActive = false
    private var refreshInFlight = false
    private var refreshRequestedWhileInFlight = false
    private var refreshGeneration = 0
    private var artworkFallbackTrackKey: String?
    /// The track the album-lookup fallback was last scheduled for (once per track).
    private var lookupScheduledFor: String?
    private var artworkFallbackRetryAfter = Date.distantPast
    private var emptyResultCount = 0
    private var lastSuccessfulRefresh = Date.distantPast
    /// Which provider produced the last successful result (used for commands).
    private var activeProvider: NowPlayingProvider?

    func start() {
        guard timer == nil else { return }
        isActive = true
        artworkObserver = NotificationCenter.default.addObserver(forName: NowPlayingInfo.artworkDidLoad, object: nil, queue: .main) { [weak self] notification in
            let source = notification.object as AnyObject?
            let delivered = notification.userInfo
            Task { @MainActor [weak self] in
                guard let self, self.isActive,
                      source === self.appleScript || source === self.music || source === self.spotify else { return }
                if let cover = delivered?["image"] as? NSImage, let title = delivered?["title"] as? String,
                   let artist = delivered?["artist"] as? String, self.info.title == title, self.info.artist == artist {
                    self.showCover(cover, title: title, artist: artist)
                    return
                }
                self.artworkFallbackRetryAfter = .distantPast
                self.refresh()
            }
        }
        mediaRemote.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        // Spotify says when the song changes: refresh at once, and its own cover for the
        // track (fetched in parallel from the notification) shows the moment it lands.
        let spotifyCovers = SpotifyCovers.shared
        spotifyCovers.onChange = { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        spotifyCovers.onCover = { [weak self] title, artist, cover in
            Task { @MainActor [weak self] in self?.showCover(cover, title: title, artist: artist) }
        }
        if Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" { spotifyCovers.start() }
        mediaRemote.startObserving()
        hasCompletedInitialRefresh = false
        refreshGeneration += 1
        refresh()
        let refreshTimer = Timer(timeInterval: mediaRemote.isAvailable ? 0.8 : 1.4, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        // Default-mode timers pause while menus, sliders, or drag gestures are
        // tracking. Common mode keeps music metadata live during interaction.
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
    }

    func stop() {
        isActive = false
        if let artworkObserver { NotificationCenter.default.removeObserver(artworkObserver) }
        artworkObserver = nil
        timer?.invalidate()
        timer = nil
        mediaRemote.onChange = nil
        mediaRemote.stopObserving()
        SpotifyCovers.shared.stop()
        activeProvider = nil
        contextID = UUID().uuidString
        commandError = nil
        isSending = false
        clearPendingPlayState()
        refreshGeneration += 1
        refreshInFlight = false
        refreshRequestedWhileInFlight = false
        artworkFallbackTrackKey = nil
        artworkFallbackRetryAfter = .distantPast
        emptyResultCount = 0
        lastSuccessfulRefresh = .distantPast
        hasCompletedInitialRefresh = false
        info = NowPlayingInfo()
    }

    private func refresh() {
        guard isActive else { return }
        guard !refreshInFlight else {
            refreshRequestedWhileInFlight = true
            return
        }
        refreshInFlight = true
        refreshRequestedWhileInFlight = false
        let generation = refreshGeneration

        if selectedSource == .music || selectedSource == .spotify {
            let provider = selectedSource == .music ? music : spotify
            provider.fetchNowPlaying { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.finish(result ?? NowPlayingInfo(), from: provider, generation: generation)
                }
            }
            return
        }
        if selectedSource == .browser { refreshViaBrowser(generation: generation); return }
        if selectedSource == .system && !mediaRemote.isAvailable {
            finish(NowPlayingInfo(), from: nil, generation: generation)
            return
        }
        if mediaRemote.isAvailable {
            mediaRemote.fetchNowPlaying { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.refreshGeneration == generation else { return }
                    if let result, result.hasTrack {
                        self.applyMediaRemote(result, generation: generation)
                    } else if self.selectedSource == .system {
                        self.finish(NowPlayingInfo(), from: nil, generation: generation)
                    } else {
                        self.refreshViaAppleScript(generation: generation)
                    }
                }
            }
        } else {
            refreshViaAppleScript(generation: generation)
        }
    }

    private func applyMediaRemote(_ result: NowPlayingInfo, generation: Int) {
        if result.artwork == nil,
           result.matchesArtworkTrack(info),
           let cachedArtwork = info.artwork {
            var cachedResult = result
            cachedResult.artwork = cachedArtwork
            finish(cachedResult, from: mediaRemote, generation: generation)
            return
        }

        // Metadata and playback state are the latency-sensitive path. Publish
        // them and release the refresh lock before optional artwork fallback.
        finish(result, from: mediaRemote, generation: generation)

        guard result.artwork == nil, appleScript.isAvailable else { return }
        let trackKey = "\(result.title)|\(result.artist)|\(result.album)"
        guard artworkFallbackTrackKey != trackKey
                || Date() >= artworkFallbackRetryAfter else { return }

        artworkFallbackTrackKey = trackKey
        artworkFallbackRetryAfter = .distantFuture
        appleScript.fetchNowPlaying { [weak self] supplemental in
            Task { @MainActor [weak self] in
                guard let self, self.refreshGeneration == generation else { return }
                guard self.info.matchesArtworkTrack(result) else {
                    self.artworkFallbackTrackKey = nil
                    self.artworkFallbackRetryAfter = .distantPast
                    return
                }
                var merged = self.info
                if let supplemental, supplemental.matchesArtworkTrack(result), let artwork = supplemental.artwork {
                    merged.artwork = artwork
                }
                self.artworkFallbackTrackKey = trackKey
                self.artworkFallbackRetryAfter = merged.artwork == nil
                    ? Date().addingTimeInterval(2)
                    : .distantFuture
                self.apply(merged, from: self.mediaRemote)
            }
        }
    }

    private func refreshViaBrowser(generation: Int) {
        guard browser.isAvailable else {
            finish(NowPlayingInfo(), from: nil, generation: generation)
            return
        }
        browser.fetchNowPlaying { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.refreshGeneration == generation else { return }
                if let result, result.hasTrack {
                    self.finish(result, from: self.browser, generation: generation)
                } else {
                    self.finish(NowPlayingInfo(), from: nil, generation: generation)
                }
            }
        }
    }

    private func refreshViaAppleScript(generation: Int) {
        guard appleScript.isAvailable else {
            refreshViaBrowser(generation: generation)
            return
        }
        appleScript.fetchNowPlaying { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.refreshGeneration == generation else { return }
                if let result, result.hasTrack {
                    self.finish(result, from: self.appleScript, generation: generation)
                } else {
                    self.refreshViaBrowser(generation: generation)
                }
            }
        }
    }

    private func finish(
        _ result: NowPlayingInfo,
        from provider: NowPlayingProvider?,
        generation: Int
    ) {
        guard refreshGeneration == generation else { return }
        refreshInFlight = false
        if result.hasTrack {
            emptyResultCount = 0
            lastSuccessfulRefresh = Date()
            apply(result, from: provider)
        } else {
            emptyResultCount += 1
            let shouldKeepCurrent =
                info.hasTrack
                && emptyResultCount < 4
                && Date().timeIntervalSince(lastSuccessfulRefresh) < 4.5
            if !shouldKeepCurrent {
                apply(result, from: provider)
            }
        }
        hasCompletedInitialRefresh = true
        runQueuedRefreshIfNeeded()
    }

    private func runQueuedRefreshIfNeeded() {
        guard refreshRequestedWhileInFlight, isActive else { return }
        refreshRequestedWhileInFlight = false
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    /// A cover that arrived on its own (Spotify's, or a downloaded artwork link) goes
    /// straight onto the matching track, without another round trip to the player.
    private func showCover(_ cover: NSImage, title: String, artist: String) {
        guard info.hasTrack, info.title == title, info.artist == artist else { return }
        var updated = info
        updated.artwork = cover
        info = updated
    }

    /// The player gave no cover: use one already found for this album, or look it
    /// up once (iTunes Search, artist and album only) and add it if the track hasn't changed.
    private func lookUpArtwork(for track: inout NowPlayingInfo) {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        let lookup = ArtworkLookup.shared
        if let cover = lookup.cached(artist: track.artist, album: track.album, title: track.title) {
            track.artwork = cover
            return
        }
        let target = track
        let trackKey = "\(track.title)|\(track.artist)|\(track.album)"
        guard lookupScheduledFor != trackKey else { return }
        lookupScheduledFor = trackKey
        // The player's own cover usually lands within a second; search only if it hasn't.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.info.artwork == nil, self.info.matchesArtworkTrack(target) else { return }
            lookup.fetch(artist: target.artist, album: target.album, title: target.title) { [weak self] cover in
                Task { @MainActor [weak self] in
                    guard let self, let cover, self.info.artwork == nil, self.info.matchesArtworkTrack(target) else { return }
                    var updated = self.info
                    updated.artwork = cover
                    self.info = updated
                }
            }
        }
    }

    private func apply(_ incoming: NowPlayingInfo, from provider: NowPlayingProvider?) {
        var newInfo = incoming
        if !newInfo.duration.isFinite || newInfo.duration < 0 { newInfo.duration = 0; newInfo.capabilities.remove(.seek) }
        if !newInfo.elapsed.isFinite || newInfo.elapsed < 0 { newInfo.elapsed = 0 }
        if newInfo.artwork == nil,
           newInfo.matchesArtworkTrack(info) {
            newInfo.artwork = info.artwork
        }
        if newInfo.artwork == nil, newInfo.hasTrack,
           let cover = SpotifyCovers.shared.cached(title: newInfo.title, artist: newInfo.artist) {
            newInfo.artwork = cover
        }
        if newInfo.artwork == nil, newInfo.hasTrack { lookUpArtwork(for: &newInfo) }
        if newInfo.title != info.title || newInfo.artist != info.artist || newInfo.sourceName != info.sourceName {
            contextID = UUID().uuidString
            commandError = nil
        }
        activeProvider = provider
        // The estimate anchors on the stored elapsed time, so the read time moves
        // only with it. (Equality tolerates 0.5 s of drift; resetting the clock
        // while keeping an older elapsed value would pull the position back.)
        if newInfo != info {
            info = newInfo
            elapsedReadAt = min(newInfo.elapsedAt ?? Date(), Date())
        }
        if let pending = pendingIsPlaying, pending == newInfo.isPlaying || !newInfo.hasTrack {
            clearPendingPlayState()
        }
    }

    var displayIsPlaying: Bool { pendingIsPlaying ?? info.isPlaying }

    /// Elapsed time advanced by the wall clock while playing, capped at the duration.
    func estimatedElapsed(at date: Date) -> TimeInterval {
        guard info.isPlaying, pendingIsPlaying != false else { return info.elapsed }
        let advanced = info.elapsed + max(0, date.timeIntervalSince(elapsedReadAt)) / Design.demoTimeScale
        return info.duration > 0 ? min(advanced, info.duration) : advanced
    }

    private func clearPendingPlayState() {
        pendingExpiry?.cancel()
        pendingExpiry = nil
        pendingIsPlaying = nil
    }

    // MARK: - Transport

    func supports(_ capability: PlaybackCapability) -> Bool {
        info.hasTrack && info.capabilities.contains(capability)
    }
    /// Brings the playing app forward. Sources without a known app stay inert.
    var canOpenSource: Bool { info.hasTrack && info.sourceBundleID != nil }
    func openSource() {
        guard let bundleID = info.sourceBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        app.activate()
    }
    func togglePlayPause() {
        guard supports(.playPause), !isSending else { return }
        pendingIsPlaying = !displayIsPlaying
        pendingExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in self?.clearPendingPlayState() }
        pendingExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: expiry)
        submit("media.playPause")
    }
    func nextTrack() { submit("media.next") }
    func previousTrack() { submit("media.previous") }
    func seek(to elapsed: TimeInterval) {
        guard let value = PlaybackValidation.seek(elapsed, duration: info.duration) else { return }
        submit("media.seek", number: value)
    }

    private func submit(_ action: String, number: Double? = nil) {
        guard !isSending else { return }
        let request = ActionRequest(action: action, contextID: contextID, number: number)
        Task { [weak self] in
            guard let self else { return }
            do { _ = try await self.actions.execute(request) }
            catch {
                if action == "media.playPause" { self.clearPendingPlayState() }
                guard request.contextID == self.contextID else { return }
                self.commandError = error.localizedDescription
            }
        }
    }

    private func registerActions() {
        let commands: [(String, String, PlaybackCapability)] = [
            ("media.playPause", "Play or pause", .playPause),
            ("media.previous", "Previous track", .previous),
            ("media.next", "Next track", .next),
            ("media.seek", "Seek", .seek)
        ]
        for (id, title, capability) in commands {
            actions.register(id, entry: .init(feature: .media, title: title, available: { [weak self] in
                guard let self else { return false }
                return self.isActive && !self.isSending && self.supports(capability)
            }, perform: { [weak self] request in
                guard let self, request.contextID == self.contextID else { throw PlaybackCommandError.changedSource }
                guard !self.isSending, self.supports(capability), let provider = self.activeProvider else {
                    throw PlaybackCommandError.unavailable
                }
                let command: NowPlayingCommand
                switch capability {
                case .playPause: command = .togglePlayPause
                case .previous: command = .previousTrack
                case .next: command = .nextTrack
                case .seek:
                    guard let number = request.number, let position = PlaybackValidation.seek(number, duration: self.info.duration) else {
                        throw PlaybackCommandError.unavailable
                    }
                    command = .seek(to: position)
                }
                self.isSending = true
                self.commandError = nil
                let generation = self.refreshGeneration
                defer { if generation == self.refreshGeneration { self.isSending = false } }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    provider.send(command) { result in
                        switch result {
                        case .success: continuation.resume()
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                }
                // Wait for the provider's actual state; rejected commands must
                // never show an optimistic playback change as successful.
                if generation == self.refreshGeneration { self.refresh() }
                return ActionResult(message: "Playback command submitted")
            }))
        }
    }

#if DEBUG
    func setPreviewInfo(_ preview: NowPlayingInfo) { info = preview }
#endif
}
