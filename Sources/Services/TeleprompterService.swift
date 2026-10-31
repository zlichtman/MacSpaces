import Combine
import Foundation

private let teleprompterURLSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 12
    return URLSession(configuration: configuration)
}()

enum TeleprompterSource: String {
    case lyrics = "Lyrics"
    case subtitles = "Subtitles"

    var systemImage: String {
        switch self {
        case .lyrics: return "quote.bubble.fill"
        case .subtitles: return "captions.bubble.fill"
        }
    }
}

/// Resolves synchronized lyrics or YouTube caption tracks for the active media
/// session and exposes only the current/upcoming line to the Nook.
@MainActor
final class TeleprompterService: ObservableObject {
    /// Identifies requests to lyrics and caption providers with the running version.
    nonisolated static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return "MacSpaces \(version) (https://github.com/zlichtman/MacSpaces)"
    }()

    private struct PlainLyricsPayload: Decodable {
        let lyrics: String?
    }

    private struct CaptionTrack: Decodable {
        struct Name: Decodable {
            let simpleText: String?
        }

        let baseUrl: String
        let languageCode: String?
        let kind: String?
        let name: Name?
    }

    private struct CaptionPayload: Decodable {
        struct Event: Decodable {
            struct Segment: Decodable {
                let utf8: String?
            }

            let tStartMs: Double?
            let dDurationMs: Double?
            let segs: [Segment]?
        }

        let events: [Event]?
    }

    // Each value publishes only when it changes: the Music page redraws per line,
    // not per tick.
    @Published private(set) var currentText = ""
    @Published private(set) var upcomingText = ""
    /// Counts line changes, a repeated line included, so styles replay their entrance.
    @Published private(set) var lineID = 0
    /// The current line's sung span in song time (timed lyrics only), from which
    /// Karaoke fills and Typewriter types.
    @Published private(set) var lineSpan: ClosedRange<TimeInterval>?
    /// Lyric motion follows the song: it holds while paused.
    @Published private(set) var isPlaying = false
    @Published private(set) var statusText = "Play a song or a captioned video"
    @Published private(set) var source: TeleprompterSource?
    @Published private(set) var isLoading = false
    /// This song has lyrics or captions to show (false while looking, or when none exist).
    @Published private(set) var hasLyrics = false
    /// The Music page centres the title: this song has no lyrics, or none came within
    /// `NoLyricsLayout.deadline`. A song change keeps the previous layout for
    /// `NoLyricsLayout.grace` while the lookup starts.
    @Published private(set) var showsNoLyrics = false
    /// The lyrics are timed lyrics (not captions or plain text), so their timing can be nudged.
    @Published private(set) var canNudgeTiming = false
    /// This song's own nudge (`LyricNudge`): positive shows lines sooner.
    @Published private(set) var timingNudge: TimeInterval = 0

    private let nowPlaying: NowPlayingController
    private var cancellable: AnyCancellable?
    /// Fires at the next line change, exactly; nothing ticks between lines.
    private var switchTimer: Timer?
    private var visiblePresentations: Set<UUID> = []
    /// Lookups may start before the page shows (the Nook is about to open).
    private var prefetchUntil = Date.distantPast
    private var loadTask: Task<Void, Never>?
    private var currentInfo = NowPlayingInfo()
    private var loadedKey = ""
    /// The song length the current lookup started with (`Lyrics.lengthCorrected`).
    private var lookupDuration: TimeInterval = 0
    private var timeline = LyricTimeline() {
        didSet {
            if hasLyrics != !timeline.lines.isEmpty { hasLyrics = !timeline.lines.isEmpty }
            let nudgeable = timeline.timed && !timeline.lines.isEmpty && source == .lyrics
            if canNudgeTiming != nudgeable { canNudgeTiming = nudgeable }
        }
    }
    /// The song time the lyrics are shown for: the nudge applies only to timed lyrics.
    private var lyricOffset: TimeInterval { timeline.timed && source == .lyrics ? timingNudge : 0 }
    private var shownIndex: Int?
    /// Where the scrubber is (lyrics follow it while it's dragged). After release it
    /// holds until the player reports the seek, at most `scrubHoldUntil`.
    private var scrubPosition: TimeInterval?
    private var scrubHoldUntil = Date.distantPast
    private var scrubTimer: Timer?
    private var directSubtitle = ""
    private let cache: LyricsCache
    /// This song's lookup, for the no-lyrics layout (`NoLyricsLayout`).
    private var answer = NoLyricsLayout.Answer.idle
    private var lookupStarted = Date.distantPast
    private var heldLayout = false
    private var layoutTimer: Timer?

    init(nowPlaying: NowPlayingController, cache: LyricsCache = .shared) {
        self.nowPlaying = nowPlaying
        self.cache = cache
    }

    func start() {
        guard cancellable == nil else { return }
        cancellable = nowPlaying.$info
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.consume(info)
            }

        consume(nowPlaying.info)
    }

    func setPresentationVisible(_ visible: Bool, id: UUID) {
        if visible { visiblePresentations.insert(id) } else { visiblePresentations.remove(id) }
        if cancellable != nil { consume(nowPlaying.info) }
    }

    /// The Nook is about to open on a dock with Music: look the song up now so its
    /// lyrics are ready when the page shows. Nothing advances until it does.
    func prefetch(for seconds: TimeInterval) {
        prefetchUntil = Date().addingTimeInterval(seconds)
        if cancellable != nil { consume(nowPlaying.info) }
    }

    private var isVisible: Bool { !visiblePresentations.isEmpty }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        switchTimer?.invalidate()
        switchTimer = nil
        loadTask?.cancel()
        loadTask = nil
        loadedKey = ""
        StickerChoice.prefetch([])
        timeline = LyricTimeline()
        directSubtitle = ""
        show(nil, current: "", upcoming: "", span: nil)
        source = nil
        isLoading = false
        statusText = "Play a song or a captioned video"
        setAnswer(.idle)
    }

#if DEBUG
    func setPreview(
        current: String,
        upcoming: String,
        source: TeleprompterSource,
        playing: Bool = false
    ) {
        isPlaying = playing
        if current != currentText { lineID &+= 1 }
        currentText = current
        upcomingText = upcoming
        self.source = source
        hasLyrics = !current.isEmpty
        statusText = ""
        setAnswer(current.isEmpty ? .none : .lyrics)
    }
#endif

    private func consume(_ info: NowPlayingInfo) {
        currentInfo = info
        if isPlaying != info.isPlaying { isPlaying = info.isPlaying }
        guard isVisible || Date() < prefetchUntil else {
            switchTimer?.invalidate()
            return
        }
        let hadSubtitle = !directSubtitle.isEmpty
        directSubtitle = info.subtitleText
        if hadSubtitle != !directSubtitle.isEmpty { updateLayout() }
        let key = trackKey(for: info)

        guard info.hasTrack else {
            if loadedKey != key {
                clear(status: "Play a song or a captioned video")
                loadedKey = key
            }
            return
        }

        if !directSubtitle.isEmpty {
            if source != .subtitles { source = .subtitles }
            if !statusText.isEmpty { statusText = "" }
        }

        // A skip's first reading can carry the previous song's length under the new song's
        // key: once the real length arrives, the song is looked up again with it.
        let relook = key == loadedKey && info.sourceURL == nil
            && Lyrics.lengthCorrected(lookedUpWith: lookupDuration, now: info.duration,
                                      showingTimed: timeline.timed && !timeline.lines.isEmpty)
        guard key != loadedKey || relook else {
            updateCurrentLine()
            return
        }
        loadedKey = key
        lookupDuration = info.duration
        loadTask?.cancel()
        StickerChoice.prefetch([])
        scrubPosition = nil
        let nudge = LyricNudge.value(in: UserDefaults.standard.dictionary(forKey: LyricNudge.storageKey), key: key)
        if timingNudge != nudge { timingNudge = nudge }
        timeline = LyricTimeline(duration: info.duration)
        updateCurrentLine()
        isLoading = true
        heldLayout = showsNoLyrics
        lookupStarted = Date()
        setAnswer(.looking)
        statusText = info.sourceURL == nil ? "Finding lyrics…" : "Finding subtitles…"

        if let sourceURL = info.sourceURL, isYouTubeURL(sourceURL) {
            source = .subtitles
            loadTask = Task { [weak self] in await self?.loadCaptions(pageURL: sourceURL, key: key) }
        } else {
            source = .lyrics
            loadTask = Task { [weak self] in await self?.loadLyrics(info: info, key: key, fresh: relook) }
        }
    }

    // MARK: - Lyrics lookup

    private enum Lookup {
        case found(Lyrics.Record)
        /// LRCLIB answered and has nothing for this song.
        case noMatch
        /// Busy (503/429), failing or unreachable: worth asking again.
        case unavailable
    }

    /// `fresh` skips the cache: what it holds for this key may be the answer of a lookup
    /// made with the wrong length (`Lyrics.lengthCorrected`), and is replaced.
    private func loadLyrics(info: NowPlayingInfo, key: String, fresh: Bool = false) async {
        guard !info.title.isEmpty, !info.artist.isEmpty else {
            finishUnavailable(key: key, message: "Lyrics unavailable for this source")
            return
        }
        let cached = fresh ? nil : await cache.entry(for: key)
        guard loadedKey == key, !Task.isCancelled else { return }
        // A cached answer shows at once, "none" included (even one due to be checked again,
        // which happens below): the page never waits on the network for a song it knows.
        if let cached {
            if cached.lines.isEmpty {
                finishUnavailable(key: key, message: "Lyrics unavailable")
            } else {
                applyLyrics(cached.lines, timed: cached.timed, key: key)
            }
        }
        // A song played from a file: lyrics saved in the file itself win (they're timed to
        // that very cut), when the local-files switch allows reading it. They're read fresh
        // each time, so editing the file's tags shows next play.
        if let local = info.localTrack, LocalCovers.isEnabled,
           let embedded = await withCheckedContinuation({ continuation in
               LocalCovers.shared.lyrics(for: local) { continuation.resume(returning: $0) }
           }) {
            guard loadedKey == key, !Task.isCancelled else { return }
            let found = Lyrics.embeddedLines(embedded.text, synced: embedded.synced.map { ($0.start, $0.text) }, duration: info.duration)
            if !found.lines.isEmpty {
                applyLyrics(found.lines, timed: found.timed, key: key)
                return
            }
        }
        guard loadedKey == key, !Task.isCancelled else { return }
        if let cached, !cached.isStale() { return }

        // LRCLIB is a volunteer service that can be busy for seconds, or minutes, at a time.
        // A busy answer is asked again (1.5, 3, 6, 12, 24 s apart, then every 30 s for about
        // five minutes while the song plays) instead of settling for untimed lyrics, which
        // would show lines at the wrong moments; plain text stands in only after the first
        // few tries, until timed lyrics arrive.
        var showedPlain = cached?.lines.isEmpty == false
        let attempts = 14
        for attempt in 0..<attempts {
            let lookup = await lookUpLRCLIB(info: info)
            guard loadedKey == key, !Task.isCancelled else { return }
            switch lookup {
            case .found(let record):
                await apply(record, info: info, key: key)
                return
            case .noMatch:
                await loadPlainLyrics(info: info, key: key, definitive: true, showing: cached?.lines.isEmpty == false)
                return
            case .unavailable:
                if attempt == 1, !showedPlain {
                    showedPlain = await loadPlainLyrics(info: info, key: key, definitive: false)
                }
                // Past the quick tries the page stops waiting; lyrics found later still show.
                if attempt == 4, !showedPlain { finishUnavailable(key: key, message: "Lyrics service busy, trying again") }
                guard attempt < attempts - 1 else { break }
                try? await Task.sleep(nanoseconds: UInt64(min(30, 1.5 * pow(2, Double(attempt))) * 1_000_000_000))
                guard loadedKey == key, !Task.isCancelled else { return }
            }
        }
        if !showedPlain { finishUnavailable(key: key, message: "Lyrics unavailable") }
    }

    private func apply(_ record: Lyrics.Record, info: NowPlayingInfo, key: String) async {
        if record.instrumental == true {
            await cache.store(.init(lines: [], timed: true, saved: Date()), for: key)
            finishUnavailable(key: key, message: "Instrumental")
            return
        }
        // Parsing the LRC (a regular expression per line) stays off the main actor.
        let duration = info.duration
        var lines = await Task.detached(priority: .userInitiated) { Lyrics.lines(from: record, fallbackDuration: duration) }.value
        let timed = record.isSynced
        guard !lines.isEmpty else { await loadPlainLyrics(info: info, key: key, definitive: true); return }
        applyLyrics(lines, timed: timed, key: key)
        // LRCLIB's community lyrics sometimes blank out words ("masochistic -",
        // "b******t"). MacSpaces doesn't censor: it fills them back in from the
        // full text at lyrics.ovh, keeping LRCLIB's timing.
        if lines.contains(where: { Lyrics.isCensored($0.text) }),
           let text = await plainLyrics(info: info).text {
            let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard loadedKey == key, !Task.isCancelled, !words.isEmpty else { return }
            lines = lines.map { line in
                Lyrics.isCensored(line.text) ? LyricLine(start: line.start, end: line.end, text: Lyrics.uncensor(line.text, using: words)) : line
            }
            applyLyrics(lines, timed: timed, key: key)
        }
        await cache.store(.init(lines: lines, timed: timed, saved: Date()), for: key)
    }

    /// LRCLIB's exact lookup first (fast, by title, artist, album and length),
    /// then three searches: title and artist, free text (which finds titles whose
    /// punctuation differs) and the title alone (artists spelled another way, such
    /// as "Vtoroi Ka" for "Второй Ка"). Only a record that is really this song counts.
    private func lookUpLRCLIB(info: NowPlayingInfo) async -> Lookup {
        let title = Lyrics.cleanedTrackTitle(info.title)
        let artist = Lyrics.cleanedArtist(info.artist)
        var requests: [(exact: Bool, items: [URLQueryItem])] = []
        if info.duration > 0 {
            requests.append((true, [URLQueryItem(name: "track_name", value: title),
                                    URLQueryItem(name: "artist_name", value: artist),
                                    URLQueryItem(name: "album_name", value: info.album),
                                    URLQueryItem(name: "duration", value: String(Int(info.duration.rounded())))]))
        }
        requests.append((false, [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]))
        requests.append((false, [URLQueryItem(name: "q", value: "\(Lyrics.primaryArtist(info.artist)) \(title)")]))
        requests.append((false, [URLQueryItem(name: "track_name", value: title)]))
        // A file's lookup goes on past a record that only gave words (its timing fit no
        // upload so far): a later search may hold an upload as long as the file.
        var untimed: Lyrics.Record?
        for request in requests {
            var components = URLComponents(string: request.exact ? "https://lrclib.net/api/get" : "https://lrclib.net/api/search")
            components?.queryItems = request.items
            guard let url = components?.url else { continue }
            guard let (data, status) = await fetch(url) else { return untimed.map(Lookup.found) ?? .unavailable }
            if status == 404 { continue }
            guard (200..<300).contains(status) else { return untimed.map(Lookup.found) ?? .unavailable }
            // Up to 20 full lyrics, decoded and scored (transliteration included) off the main actor.
            // A file on this Mac is often another cut than the release LRCLIB timed: its
            // timing counts only when it fits the file (`Lyrics.fittingFile`).
            let exact = request.exact, local = info.localTrack != nil
            let duration = info.duration > 0 ? info.duration : TimeInterval(info.localTrack?.seconds ?? 0)
            let best = await Task.detached(priority: .userInitiated) {
                let records = exact ? Lyrics.decodeRecord(data).map { [$0] } ?? [] : Lyrics.decodeRecords(data)
                return Lyrics.best(records, title: title, artist: artist, duration: duration, strictTiming: local)
            }.value
            guard let best else { continue }
            if local, !best.isSynced, best.instrumental != true {
                if untimed == nil { untimed = best }
                continue
            }
            return .found(best)
        }
        return untimed.map(Lookup.found) ?? .noMatch
    }

    /// LRCLIB is the preferred source because it has synchronized LRC data. When
    /// it has nothing (or stays unreachable), a no-key plain-lyrics provider keeps
    /// the page useful. Returns whether lyrics were shown.
    @discardableResult
    private func loadPlainLyrics(info: NowPlayingInfo, key: String, definitive: Bool, showing: Bool = false) async -> Bool {
        let result = await plainLyrics(info: info)
        guard loadedKey == key, !Task.isCancelled else { return false }
        // Re-checking cached plain lyrics while lyrics.ovh is down: keep them, store nothing.
        if showing, !result.answered, result.text == nil { return true }
        let lines = Lyrics.lines(fromPlain: result.text, duration: info.duration)
        if !lines.isEmpty {
            applyLyrics(lines, timed: false, key: key)
            if definitive { await cache.store(.init(lines: lines, timed: false, saved: Date()), for: key) }
            return true
        }
        if definitive {
            // LRCLIB said no; lyrics.ovh not answering only shortens how long that's kept.
            let now = Date()
            await cache.store(.init(lines: [], timed: false, saved: now,
                                    recheck: result.answered ? nil : now.addingTimeInterval(LyricsCache.partialRecheck)), for: key)
            finishUnavailable(key: key, message: "Lyrics unavailable")
        }
        return false
    }

    /// lyrics.ovh's text for the song, and whether every request got a real answer.
    private func plainLyrics(info: NowPlayingInfo) async -> (text: String?, answered: Bool) {
        var answered = true
        for candidate in Lyrics.plainCandidates(title: info.title, artist: info.artist) {
            guard var components = URLComponents(string: "https://api.lyrics.ovh") else { continue }
            components.path = "/v1/\(candidate.artist)/\(candidate.title)"
            guard let url = components.url else { continue }
            guard let (data, status) = await fetch(url) else { answered = false; continue }
            if status == 404 { continue }
            guard (200..<300).contains(status) else { answered = false; continue }
            if let text = (try? JSONDecoder().decode(PlainLyricsPayload.self, from: data))?.lyrics,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (text, true)
            }
        }
        return (nil, answered)
    }

    /// The body and status, or nil when the request failed outright (offline, timeout).
    nonisolated private func fetch(_ url: URL, userAgent: String = TeleprompterService.userAgent) async -> (Data, Int)? {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await teleprompterURLSession.data(for: request) else { return nil }
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    private func applyLyrics(_ lines: [LyricLine], timed: Bool, key: String) {
        guard loadedKey == key, !Task.isCancelled else { return }
        isLoading = false
        setAnswer(lines.isEmpty ? .none : .lyrics)
        timeline = LyricTimeline(lines: lines, timed: timed, duration: currentInfo.duration)
        if !statusText.isEmpty { statusText = "" }
        updateCurrentLine()
        // Scenes: fetch the song's stickers now, so each is ready when its line arrives.
        StickerChoice.prefetch(lines.map(\.text))
        MoodSentiment.prefetch(lines.map(\.text))
    }

    // MARK: - YouTube captions

    private func loadCaptions(pageURL: URL, key: String) async {
        guard let (data, _) = await fetch(pageURL, userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Safari/605.1.15"),
              let page = String(data: data, encoding: .utf8),
              let tracksData = Self.captionTracksJSON(in: page),
              let tracks = try? JSONDecoder().decode([CaptionTrack].self, from: tracksData),
              let track = Self.preferredCaptionTrack(in: tracks),
              let captionURL = Self.captionURL(from: track.baseUrl) else {
            finishUnavailable(key: key, message: "Turn on captions in YouTube")
            return
        }
        let payload = await fetch(captionURL).flatMap { try? JSONDecoder().decode(CaptionPayload.self, from: $0.0) }
        guard loadedKey == key, !Task.isCancelled else { return }
        let parsed = Self.lines(from: payload)
        let canSynchronize = currentInfo.duration > 0 || currentInfo.elapsed > 0 || !directSubtitle.isEmpty
        guard canSynchronize, !parsed.isEmpty else {
            finishUnavailable(key: key, message: "Turn on captions in YouTube")
            return
        }
        applyLyrics(parsed, timed: true, key: key)
    }

    // MARK: - Showing the current line

    /// Shows the line for this moment and sets one timer for the next change.
    /// Line changes land on time instead of up to a poll interval late.
    private func updateCurrentLine() {
        switchTimer?.invalidate()
        switchTimer = nil
        if !directSubtitle.isEmpty {
            show(nil, current: directSubtitle, upcoming: "", span: nil)
            if !statusText.isEmpty { statusText = "" }
            return
        }
        guard isVisible, !timeline.lines.isEmpty else {
            show(nil, current: "", upcoming: "", span: nil)
            return
        }
        let clock = nowPlaying.estimatedElapsed(at: Date())
        if let target = scrubPosition, scrubHoldUntil != .distantFuture,
           Date() >= scrubHoldUntil || abs(clock - target) <= 1 {
            scrubPosition = nil
        }
        let elapsed = (scrubPosition ?? clock) + lyricOffset
        let position = timeline.position(at: elapsed)
        show(position.index, current: position.current, upcoming: position.upcoming, span: position.span)
        guard scrubPosition == nil, nowPlaying.displayIsPlaying, let next = timeline.nextChange(after: elapsed) else { return }
        // The song clock runs slower in website captures (Design.demoTimeScale).
        let delay = max(0.01, (next - elapsed) * Design.demoTimeScale)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateCurrentLine() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        switchTimer = timer
    }

    private func show(_ index: Int?, current: String, upcoming: String, span: ClosedRange<TimeInterval>?) {
        if index != shownIndex || current != currentText {
            shownIndex = index
            lineID &+= 1
        }
        if currentText != current { currentText = current }
        if upcomingText != upcoming { upcomingText = upcoming }
        if lineSpan != span { lineSpan = span }
    }

    /// The song's position now, on the same clock as the line changes (the scrubber's
    /// while it's dragged).
    func elapsed(at date: Date) -> TimeInterval { (scrubPosition ?? nowPlaying.estimatedElapsed(at: date)) + lyricOffset }

    /// Moves this song's lyrics `delta` seconds sooner (negative: later), or back to their
    /// own timing (nil), and remembers it for the song.
    func nudgeTiming(by delta: TimeInterval?) {
        guard canNudgeTiming, !loadedKey.isEmpty else { return }
        let defaults = UserDefaults.standard
        let saved = LyricNudge.adjusted(defaults.dictionary(forKey: LyricNudge.storageKey) ?? [:], key: loadedKey, by: delta)
        defaults.set(saved, forKey: LyricNudge.storageKey)
        timingNudge = LyricNudge.value(in: saved, key: loadedKey)
        updateCurrentLine()
    }

    /// The scrubber moved (a position) or was let go (nil). Lyrics follow the drag;
    /// after release they keep the target until the player reports the seek, so the
    /// old line never flashes back.
    func scrub(to position: TimeInterval?) {
        scrubTimer?.invalidate()
        scrubTimer = nil
        if let position {
            scrubHoldUntil = .distantFuture
            guard scrubPosition != position else { return }
            scrubPosition = position
        } else {
            guard scrubPosition != nil else { return }
            scrubHoldUntil = Date().addingTimeInterval(2)
            let timer = Timer(timeInterval: 2.05, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateCurrentLine() }
            }
            RunLoop.main.add(timer, forMode: .common)
            scrubTimer = timer
        }
        updateCurrentLine()
    }

    private func clear(status: String) {
        loadTask?.cancel()
        loadTask = nil
        timeline = LyricTimeline()
        directSubtitle = ""
        show(nil, current: "", upcoming: "", span: nil)
        switchTimer?.invalidate()
        source = nil
        isLoading = false
        statusText = status
        setAnswer(.idle)
    }

    private func finishUnavailable(key: String, message: String) {
        guard loadedKey == key, !Task.isCancelled else { return }
        isLoading = false
        setAnswer(.none)
        timeline = LyricTimeline(duration: currentInfo.duration)
        statusText = directSubtitle.isEmpty ? message : ""
        updateCurrentLine()
    }

    // MARK: - The no-lyrics layout

    private func setAnswer(_ new: NoLyricsLayout.Answer) {
        answer = new
        updateLayout()
    }

    /// Applies `NoLyricsLayout` now and sets one timer for the moment it would next change
    /// (the grace period's end, then the deadline), only while the lookup runs.
    private func updateLayout() {
        layoutTimer?.invalidate()
        layoutTimer = nil
        // Captions from the player itself are lyrics enough.
        let current = directSubtitle.isEmpty ? answer : .lyrics
        let elapsed = Date().timeIntervalSince(lookupStarted)
        let centred = NoLyricsLayout.centred(current, elapsed: elapsed, held: heldLayout)
        if showsNoLyrics != centred { showsNoLyrics = centred }
        guard let wait = NoLyricsLayout.nextChange(current, elapsed: elapsed) else { return }
        let timer = Timer(timeInterval: wait + 0.01, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateLayout() }
        }
        RunLoop.main.add(timer, forMode: .common)
        layoutTimer = timer
    }

    private func trackKey(for info: NowPlayingInfo) -> String {
        if let sourceURL = info.sourceURL {
            return "url|\(sourceURL.absoluteString)"
        }
        // A file's ID carries its length, so a replaced file (another cut) is looked up again.
        if let local = info.localTrack { return "local|\(local.id)" }
        return "track|\(info.title)|\(info.artist)|\(info.album)"
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "youtu.be" || host.hasSuffix("youtube.com")
    }

    nonisolated private static func captionTracksJSON(in page: String) -> Data? {
        guard let keyRange = page.range(of: #""captionTracks":"#),
              let opening = page[keyRange.upperBound...].firstIndex(of: "[") else {
            return nil
        }

        var depth = 0
        var inString = false
        var escaped = false
        var cursor = opening
        while cursor < page.endIndex {
            let character = page[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        let end = page.index(after: cursor)
                        return String(page[opening..<end]).data(using: .utf8)
                    }
                }
            }
            cursor = page.index(after: cursor)
        }
        return nil
    }

    nonisolated private static func preferredCaptionTrack(
        in tracks: [CaptionTrack]
    ) -> CaptionTrack? {
        tracks.first {
            $0.kind != "asr" && $0.languageCode?.hasPrefix("en") == true
        } ?? tracks.first {
            $0.languageCode?.hasPrefix("en") == true
        } ?? tracks.first { $0.kind != "asr" } ?? tracks.first
    }

    nonisolated private static func captionURL(from rawURL: String) -> URL? {
        let decoded = rawURL.replacingOccurrences(of: "&amp;", with: "&")
        guard var components = URLComponents(string: decoded) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "fmt" }
        items.append(URLQueryItem(name: "fmt", value: "json3"))
        components.queryItems = items
        return components.url
    }

    nonisolated private static func lines(from payload: CaptionPayload?) -> [LyricLine] {
        payload?.events?.compactMap { event in
            guard let start = event.tStartMs else { return nil }
            let text = event.segs?
                .compactMap(\.utf8)
                .joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return LyricLine(
                start: start / 1000,
                end: event.dDurationMs.map { (start + $0) / 1000 },
                text: text
            )
        } ?? []
    }

    deinit {
        switchTimer?.invalidate()
        layoutTimer?.invalidate()
        loadTask?.cancel()
    }
}
