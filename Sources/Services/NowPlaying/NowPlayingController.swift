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

    private let mediaRemote = MediaRemoteProvider()
    private let appleScript = AppleScriptProvider()
    private lazy var browser = BrowserMediaProvider(transport: mediaRemote)
    private var timer: Timer?
    private var isActive = false
    private var refreshInFlight = false
    private var refreshRequestedWhileInFlight = false
    private var refreshGeneration = 0
    private var artworkFallbackTrackKey: String?
    private var artworkFallbackRetryAfter = Date.distantPast
    private var emptyResultCount = 0
    private var lastSuccessfulRefresh = Date.distantPast
    /// Which provider produced the last successful result (used for commands).
    private var activeProvider: NowPlayingProvider?

    func start() {
        guard timer == nil else { return }
        isActive = true
        mediaRemote.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
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
        timer?.invalidate()
        timer = nil
        mediaRemote.onChange = nil
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

        if mediaRemote.isAvailable {
            mediaRemote.fetchNowPlaying { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.refreshGeneration == generation else { return }
                    if let result, result.hasTrack {
                        self.applyMediaRemote(result, generation: generation)
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
           result.title == info.title,
           result.artist == info.artist,
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
                guard self.info.title == result.title,
                      self.info.artist.isEmpty
                        || result.artist.isEmpty
                        || self.info.artist == result.artist else {
                    self.artworkFallbackTrackKey = nil
                    self.artworkFallbackRetryAfter = .distantPast
                    return
                }
                var merged = self.info
                if let supplemental,
                   supplemental.title == result.title,
                   supplemental.artist.isEmpty
                    || result.artist.isEmpty
                    || supplemental.artist == result.artist {
                    merged.artwork = supplemental.artwork
                }
                self.artworkFallbackTrackKey = trackKey
                self.artworkFallbackRetryAfter = supplemental?.artwork == nil
                    ? Date().addingTimeInterval(10)
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

    private func apply(_ incoming: NowPlayingInfo, from provider: NowPlayingProvider?) {
        var newInfo = incoming
        if newInfo.artwork == nil,
           newInfo.title == info.title,
           newInfo.artist == info.artist {
            newInfo.artwork = info.artwork
        }
        activeProvider = provider
        if newInfo != info {
            info = newInfo
        }
    }

    // MARK: - Transport

    func togglePlayPause() { send(.togglePlayPause) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }
    func seek(to elapsed: TimeInterval) {
        guard info.duration > 0 else { return }
        let clamped = min(max(elapsed, 0), info.duration)
        info.elapsed = clamped
        send(.seek(to: clamped))
    }

#if DEBUG
    /// Deterministic data injection used only by the local visual-QA renderer.
    func setPreviewInfo(_ preview: NowPlayingInfo) {
        info = preview
    }
#endif

    private func send(_ command: NowPlayingCommand) {
        let provider = activeProvider ?? (mediaRemote.isAvailable ? mediaRemote : appleScript)
        provider.send(command)

        // Optimistically flip the play state for a snappy UI, then re-poll.
        if command == .togglePlayPause, info.hasTrack {
            info.isPlaying.toggle()
        }
        // Players often expose the old track for one short beat after a
        // command. A fast refresh plus a queued confirmation keeps the UI
        // immediate without losing an update to an in-flight poll.
        for delay in [0.12, 0.55] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }
}
