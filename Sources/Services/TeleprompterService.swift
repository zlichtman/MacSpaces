import Combine
import Foundation

private let teleprompterURLSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
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
    private struct TimedLine: Equatable {
        let start: TimeInterval
        let end: TimeInterval?
        let text: String
    }

    private struct LyricsRecord: Decodable {
        let trackName: String
        let artistName: String
        let duration: Double
        let plainLyrics: String?
        let syncedLyrics: String?
    }

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

    @Published private(set) var currentText = ""
    @Published private(set) var upcomingText = ""
    @Published private(set) var statusText = "Play a song or a captioned video"
    @Published private(set) var source: TeleprompterSource?
    @Published private(set) var isLoading = false

    private let nowPlaying: NowPlayingController
    private var cancellable: AnyCancellable?
    private var timer: Timer?
    private var dataTask: URLSessionDataTask?
    private var currentInfo = NowPlayingInfo()
    private var infoReceivedAt = Date()
    private var loadedKey = ""
    private var lines: [TimedLine] = []
    private var directSubtitle = ""

    init(nowPlaying: NowPlayingController) {
        self.nowPlaying = nowPlaying
    }

    func start() {
        guard cancellable == nil else { return }
        cancellable = nowPlaying.$info
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                self?.consume(info)
            }

        let updateTimer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateCurrentLine()
            }
        }
        RunLoop.main.add(updateTimer, forMode: .common)
        timer = updateTimer
        consume(nowPlaying.info)
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        timer?.invalidate()
        timer = nil
        dataTask?.cancel()
        dataTask = nil
        loadedKey = ""
        lines = []
        directSubtitle = ""
        currentText = ""
        upcomingText = ""
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
        currentText = current
        upcomingText = upcoming
        self.source = source
        statusText = ""
    }
#endif

    private func consume(_ info: NowPlayingInfo) {
        currentInfo = info
        infoReceivedAt = Date()
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
            source = .subtitles
            statusText = ""
        }

        guard key != loadedKey else {
            updateCurrentLine()
            return
        }
        loadedKey = key
        lines = []
        currentText = directSubtitle
        upcomingText = ""
        isLoading = true
        statusText = info.sourceURL == nil ? "Finding lyrics…" : "Finding subtitles…"
        dataTask?.cancel()

        if let sourceURL = info.sourceURL, isYouTubeURL(sourceURL) {
            source = .subtitles
            fetchYouTubeCaptions(pageURL: sourceURL, key: key)
        } else {
            source = .lyrics
            fetchLyrics(info: info, key: key)
        }
    }

    private func fetchLyrics(info: NowPlayingInfo, key: String) {
        guard !info.title.isEmpty, !info.artist.isEmpty else {
            finishUnavailable(key: key, message: "Lyrics unavailable for this source")
            return
        }
        fetchSynchronizedLyrics(info: info, key: key)
    }

    private func fetchSynchronizedLyrics(info: NowPlayingInfo, key: String) {
        let searchTitle = Self.cleanedTrackTitle(info.title)
        let searchArtist = Self.cleanedArtist(info.artist)
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: searchTitle),
            URLQueryItem(name: "artist_name", value: searchArtist),
        ]
        guard let url = components?.url else {
            fetchPlainLyrics(info: info, key: key)
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "MacSpaces 1.1 (https://github.com/zlichtman/MacSpaces)",
            forHTTPHeaderField: "User-Agent"
        )
        dataTask = teleprompterURLSession.dataTask(with: request) {
            [weak self] data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let records = data.flatMap {
                try? JSONDecoder().decode([LyricsRecord].self, from: $0)
            } ?? []
            let best = Self.bestLyricsRecord(
                records,
                title: searchTitle,
                artist: searchArtist,
                duration: info.duration
            )
            let parsed = best.map {
                Self.lines(from: $0, fallbackDuration: info.duration)
            } ?? []
            Task { @MainActor [weak self] in
                guard let self, self.loadedKey == key else { return }
                if error == nil,
                   statusCode.map({ (200..<300).contains($0) }) != false,
                   !parsed.isEmpty {
                    self.applyLyrics(parsed, key: key)
                } else {
                    self.fetchPlainLyrics(info: info, key: key)
                }
            }
        }
        dataTask?.resume()
    }

    /// LRCLIB is the preferred source because it can return synchronized LRC
    /// data. Some networks block its host, however, so a no-key plain-lyrics
    /// provider keeps Spotify useful instead of leaving the strip empty.
    private func fetchPlainLyrics(info: NowPlayingInfo, key: String) {
        let candidates = Self.plainLyricsCandidates(
            title: info.title,
            artist: info.artist
        )
        fetchPlainLyricsCandidate(
            candidates,
            index: 0,
            duration: info.duration,
            key: key
        )
    }

    private func fetchPlainLyricsCandidate(
        _ candidates: [(artist: String, title: String)],
        index: Int,
        duration: TimeInterval,
        key: String
    ) {
        guard loadedKey == key else { return }
        guard index < candidates.count else {
            finishUnavailable(key: key, message: "Lyrics unavailable")
            return
        }

        let candidate = candidates[index]
        guard let url = Self.plainLyricsURL(
            artist: candidate.artist,
            title: candidate.title
        ) else {
            fetchPlainLyricsCandidate(
                candidates,
                index: index + 1,
                duration: duration,
                key: key
            )
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "MacSpaces 1.1 (https://github.com/zlichtman/MacSpaces)",
            forHTTPHeaderField: "User-Agent"
        )
        dataTask = teleprompterURLSession.dataTask(with: request) {
            [weak self] data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let payload = data.flatMap {
                try? JSONDecoder().decode(PlainLyricsPayload.self, from: $0)
            }
            let parsed = Self.lines(
                fromPlainLyrics: payload?.lyrics,
                duration: duration
            )
            Task { @MainActor [weak self] in
                guard let self, self.loadedKey == key else { return }
                if error == nil,
                   statusCode.map({ (200..<300).contains($0) }) != false,
                   !parsed.isEmpty {
                    self.applyLyrics(parsed, key: key)
                } else {
                    self.fetchPlainLyricsCandidate(
                        candidates,
                        index: index + 1,
                        duration: duration,
                        key: key
                    )
                }
            }
        }
        dataTask?.resume()
    }

    private func applyLyrics(_ parsed: [TimedLine], key: String) {
        guard loadedKey == key else { return }
        isLoading = false
        lines = parsed
        statusText = ""
        updateCurrentLine()
    }

    private func fetchYouTubeCaptions(pageURL: URL, key: String) {
        var request = URLRequest(url: pageURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        dataTask = teleprompterURLSession.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let page = String(data: data, encoding: .utf8),
                  let tracksData = Self.captionTracksJSON(in: page),
                  let tracks = try? JSONDecoder().decode([CaptionTrack].self, from: tracksData),
                  let track = Self.preferredCaptionTrack(in: tracks),
                  let captionURL = Self.captionURL(from: track.baseUrl) else {
                Task { @MainActor [weak self] in
                    self?.finishUnavailable(
                        key: key,
                        message: "Turn on captions in YouTube"
                    )
                }
                return
            }

            var captionRequest = URLRequest(url: captionURL)
            captionRequest.setValue(
                "MacSpaces 1.0 (https://github.com/zlichtman/MacSpaces)",
                forHTTPHeaderField: "User-Agent"
            )
            let captionTask = teleprompterURLSession.dataTask(
                with: captionRequest
            ) { [weak self] captionData, _, _ in
                let payload = captionData.flatMap {
                    try? JSONDecoder().decode(CaptionPayload.self, from: $0)
                }
                let parsed = Self.lines(from: payload)
                Task { @MainActor [weak self] in
                    guard let self, self.loadedKey == key else { return }
                    self.isLoading = false
                    let canSynchronize =
                        self.currentInfo.duration > 0
                        || self.currentInfo.elapsed > 0
                        || !self.directSubtitle.isEmpty
                    self.lines = canSynchronize ? parsed : []
                    self.statusText = self.lines.isEmpty
                        ? "Turn on captions in YouTube"
                        : ""
                    self.updateCurrentLine()
                }
            }
            captionTask.resume()
        }
        dataTask?.resume()
    }

    private func updateCurrentLine() {
        if !directSubtitle.isEmpty {
            currentText = directSubtitle
            upcomingText = ""
            statusText = ""
            return
        }
        guard !lines.isEmpty else {
            currentText = ""
            upcomingText = ""
            return
        }

        let elapsed = currentInfo.elapsed
            + (currentInfo.isPlaying ? Date().timeIntervalSince(infoReceivedAt) : 0)
        let index = lines.lastIndex(where: { $0.start <= elapsed }) ?? 0
        currentText = lines[index].text
        upcomingText = index + 1 < lines.count ? lines[index + 1].text : ""
    }

    private func clear(status: String) {
        dataTask?.cancel()
        dataTask = nil
        lines = []
        directSubtitle = ""
        currentText = ""
        upcomingText = ""
        source = nil
        isLoading = false
        statusText = status
    }

    private func finishUnavailable(key: String, message: String) {
        guard loadedKey == key else { return }
        isLoading = false
        lines = []
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

    nonisolated private static func bestLyricsRecord(
        _ records: [LyricsRecord],
        title: String,
        artist: String,
        duration: TimeInterval
    ) -> LyricsRecord? {
        let normalizedTitle = normalized(title)
        let normalizedArtist = normalized(artist)
        return records.max { lhs, rhs in
            score(
                lhs,
                title: normalizedTitle,
                artist: normalizedArtist,
                duration: duration
            ) < score(
                rhs,
                title: normalizedTitle,
                artist: normalizedArtist,
                duration: duration
            )
        }
    }

    nonisolated private static func score(
        _ record: LyricsRecord,
        title: String,
        artist: String,
        duration: TimeInterval
    ) -> Double {
        var value = 0.0
        if normalized(record.trackName) == title { value += 4 }
        if normalized(record.artistName).contains(artist)
            || artist.contains(normalized(record.artistName)) {
            value += 3
        }
        if record.syncedLyrics?.isEmpty == false { value += 3 }
        if duration > 0 {
            value += max(0, 2 - abs(record.duration - duration) / 8)
        }
        return value
    }

    nonisolated private static func normalized(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    nonisolated private static func cleanedTrackTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"\s*[\(\[]\s*(?:feat\.?|featuring|with)\b.*?[\)\]]\s*"#,
            #"\s*[\(\[][^\)\]]*(?:remaster|radio edit|single edit|live|acoustic|mono|stereo|version|mix)[^\)\]]*[\)\]]\s*"#,
            #"\s+[-–—]\s+.*(?:remaster|radio edit|single edit|live|acoustic|mono|stereo|version|mix).*$"#,
            #"\s+(?:feat\.?|featuring)\s+.+$"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func cleanedArtist(_ artist: String) -> String {
        var result = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"\s+(?:feat\.?|featuring)\s+.+$"#
        result = result.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func primaryArtist(_ artist: String) -> String {
        let cleaned = cleanedArtist(artist)
        let separators = [",", ";", " x ", " X "]
        for separator in separators {
            if let range = cleaned.range(of: separator) {
                let first = cleaned[..<range.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty {
                    return first
                }
            }
        }
        return cleaned
    }

    nonisolated private static func plainLyricsCandidates(
        title: String,
        artist: String
    ) -> [(artist: String, title: String)] {
        let cleanedTitle = cleanedTrackTitle(title)
        let cleanedArtist = cleanedArtist(artist)
        let primary = primaryArtist(artist)
        let raw = [
            (artist: cleanedArtist, title: cleanedTitle),
            (artist: primary, title: cleanedTitle),
            (artist: artist, title: cleanedTitle),
            (artist: artist, title: title),
        ]
        var seen = Set<String>()
        return raw.filter { candidate in
            guard !candidate.artist.isEmpty, !candidate.title.isEmpty else {
                return false
            }
            let key = "\(normalized(candidate.artist))|\(normalized(candidate.title))"
            return seen.insert(key).inserted
        }
    }

    nonisolated private static func plainLyricsURL(
        artist: String,
        title: String
    ) -> URL? {
        guard var components = URLComponents(string: "https://api.lyrics.ovh") else {
            return nil
        }
        components.path = "/v1/\(artist)/\(title)"
        return components.url
    }

    nonisolated private static func lines(
        from record: LyricsRecord,
        fallbackDuration: TimeInterval
    ) -> [TimedLine] {
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let expression = try? NSRegularExpression(
                pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#
            )
            var parsed: [TimedLine] = []
            for rawLine in synced.components(separatedBy: .newlines) {
                let range = NSRange(rawLine.startIndex..., in: rawLine)
                let matches = expression?.matches(in: rawLine, range: range) ?? []
                guard let last = matches.last else {
                    continue
                }
                let textStart = last.range.location + last.range.length
                let text = (rawLine as NSString)
                    .substring(from: textStart)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                for match in matches {
                    guard match.numberOfRanges >= 3,
                          let minuteRange = Range(match.range(at: 1), in: rawLine),
                          let secondRange = Range(match.range(at: 2), in: rawLine),
                          let minutes = Double(rawLine[minuteRange]),
                          let seconds = Double(rawLine[secondRange]) else {
                        continue
                    }
                    parsed.append(
                        TimedLine(
                            start: minutes * 60 + seconds,
                            end: nil,
                            text: text
                        )
                    )
                }
            }
            return parsed.sorted { $0.start < $1.start }
        }

        let plain = record.plainLyrics?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        guard !plain.isEmpty else { return [] }
        let duration = fallbackDuration > 0 ? fallbackDuration : record.duration
        let step = duration > 0 ? duration / Double(plain.count) : 4
        return plain.enumerated().map { index, text in
            TimedLine(start: Double(index) * step, end: nil, text: text)
        }
    }

    nonisolated private static func lines(
        fromPlainLyrics lyrics: String?,
        duration: TimeInterval
    ) -> [TimedLine] {
        let plain = lyrics?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        guard !plain.isEmpty else { return [] }
        let step = duration > 0 ? duration / Double(plain.count) : 4
        return plain.enumerated().map { index, text in
            TimedLine(start: Double(index) * step, end: nil, text: text)
        }
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

    nonisolated private static func lines(from payload: CaptionPayload?) -> [TimedLine] {
        payload?.events?.compactMap { event in
            guard let start = event.tStartMs else { return nil }
            let text = event.segs?
                .compactMap(\.utf8)
                .joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return TimedLine(
                start: start / 1000,
                end: event.dDurationMs.map { (start + $0) / 1000 },
                text: text
            )
        } ?? []
    }

    deinit {
        timer?.invalidate()
        dataTask?.cancel()
    }
}
