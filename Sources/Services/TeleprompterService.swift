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
    private var timeline = LyricTimeline()
    private var shownIndex: Int?
    private var directSubtitle = ""
    private let cache: LyricsCache

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
        timeline = LyricTimeline()
        directSubtitle = ""
        show(nil, current: "", upcoming: "", span: nil)
        source = nil
        isLoading = false
        statusText = "Play a song or a captioned video"
    }

#if DEBUG
    func setPreview(
        current: String,
        upcoming: String,
        source: TeleprompterSource
    ) {
        if current != currentText { lineID &+= 1 }
        currentText = current
        upcomingText = upcoming
        self.source = source
        statusText = ""
    }
#endif

    private func consume(_ info: NowPlayingInfo) {
        currentInfo = info
        if isPlaying != info.isPlaying { isPlaying = info.isPlaying }
        guard isVisible || Date() < prefetchUntil else {
            switchTimer?.invalidate()
            return
        }
        directSubtitle = info.subtitleText
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

        guard key != loadedKey else {
            updateCurrentLine()
            return
        }
        loadedKey = key
        loadTask?.cancel()
        timeline = LyricTimeline(duration: info.duration)
        updateCurrentLine()
        isLoading = true
        statusText = info.sourceURL == nil ? "Finding lyrics…" : "Finding subtitles…"

        if let sourceURL = info.sourceURL, isYouTubeURL(sourceURL) {
            source = .subtitles
            loadTask = Task { [weak self] in await self?.loadCaptions(pageURL: sourceURL, key: key) }
        } else {
            source = .lyrics
            loadTask = Task { [weak self] in await self?.loadLyrics(info: info, key: key) }
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

    private func loadLyrics(info: NowPlayingInfo, key: String) async {
        guard !info.title.isEmpty, !info.artist.isEmpty else {
            finishUnavailable(key: key, message: "Lyrics unavailable for this source")
            return
        }
        let cached = await cache.entry(for: key)
        guard loadedKey == key, !Task.isCancelled else { return }
        if let cached {
            if !cached.lines.isEmpty { applyLyrics(cached.lines, timed: cached.timed, key: key) }
            if !cached.isStale() {
                if cached.lines.isEmpty { finishUnavailable(key: key, message: "Lyrics unavailable") }
                return
            }
        }

        // LRCLIB is a volunteer service that can be busy for seconds at a time.
        // A busy answer is asked again (1.5, 3, 6, 12 s apart) instead of settling
        // for untimed lyrics, which would show lines at the wrong moments; plain
        // text stands in only after the first few tries, until timed lyrics arrive.
        var showedPlain = cached?.lines.isEmpty == false
        for attempt in 0..<5 {
            let lookup = await lookUpLRCLIB(info: info)
            guard loadedKey == key, !Task.isCancelled else { return }
            switch lookup {
            case .found(let record):
                await apply(record, info: info, key: key)
                return
            case .noMatch:
                await loadPlainLyrics(info: info, key: key, definitive: true)
                return
            case .unavailable:
                if attempt == 1, !showedPlain {
                    showedPlain = await loadPlainLyrics(info: info, key: key, definitive: false)
                }
                guard attempt < 4 else { break }
                try? await Task.sleep(nanoseconds: UInt64(1.5 * pow(2, Double(attempt)) * 1_000_000_000))
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
        var lines = Lyrics.lines(from: record, fallbackDuration: info.duration)
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
        for request in requests {
            var components = URLComponents(string: request.exact ? "https://lrclib.net/api/get" : "https://lrclib.net/api/search")
            components?.queryItems = request.items
            guard let url = components?.url else { continue }
            guard let (data, status) = await fetch(url) else { return .unavailable }
            if status == 404 { continue }
            guard (200..<300).contains(status) else { return .unavailable }
            let records = request.exact ? Lyrics.decodeRecord(data).map { [$0] } ?? [] : Lyrics.decodeRecords(data)
            if let best = Lyrics.best(records, title: title, artist: artist, duration: info.duration) {
                return .found(best)
            }
        }
        return .noMatch
    }

    /// LRCLIB is the preferred source because it has synchronized LRC data. When
    /// it has nothing (or stays unreachable), a no-key plain-lyrics provider keeps
    /// the page useful. Returns whether lyrics were shown.
    @discardableResult
    private func loadPlainLyrics(info: NowPlayingInfo, key: String, definitive: Bool) async -> Bool {
        let result = await plainLyrics(info: info)
        guard loadedKey == key, !Task.isCancelled else { return false }
        let lines = Lyrics.lines(fromPlain: result.text, duration: info.duration)
        if !lines.isEmpty {
            applyLyrics(lines, timed: false, key: key)
            if definitive { await cache.store(.init(lines: lines, timed: false, saved: Date()), for: key) }
            return true
        }
        if definitive {
            if result.answered { await cache.store(.init(lines: [], timed: false, saved: Date()), for: key) }
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
        guard loadedKey == key else { return }
        isLoading = false
        timeline = LyricTimeline(lines: lines, timed: timed, duration: currentInfo.duration)
        if !statusText.isEmpty { statusText = "" }
        updateCurrentLine()
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
        let elapsed = nowPlaying.estimatedElapsed(at: Date())
        let position = timeline.position(at: elapsed)
        show(position.index, current: position.current, upcoming: position.upcoming, span: position.span)
        guard nowPlaying.displayIsPlaying, let next = timeline.nextChange(after: elapsed) else { return }
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

    /// The song's position now, on the same clock as the line changes.
    func elapsed(at date: Date) -> TimeInterval { nowPlaying.estimatedElapsed(at: date) }

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
    }

    private func finishUnavailable(key: String, message: String) {
        guard loadedKey == key else { return }
        isLoading = false
        timeline = LyricTimeline(duration: currentInfo.duration)
        statusText = directSubtitle.isEmpty ? message : ""
        updateCurrentLine()
    }

    private func trackKey(for info: NowPlayingInfo) -> String {
        if let sourceURL = info.sourceURL {
            return "url|\(sourceURL.absoluteString)"
        }
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
        loadTask?.cancel()
    }
}
