import AppKit

/// Lightweight browser fallback for media sites that macOS no longer exposes
/// through the process-accessible MediaRemote API. It intentionally reads only
/// the active tab's title and URL; page contents and browsing history never
/// leave the Mac.
final class BrowserMediaProvider: NowPlayingProvider {
    private struct Browser {
        let bundleID: String
        let appName: String
        let scriptBody: String
    }

    private let browsers = [
        Browser(
            bundleID: "com.apple.Safari",
            appName: "Safari",
            scriptBody: """
                if (count of windows) is 0 then return ""
                set mediaTab to current tab of front window
                set playbackData to ""
                try
                    set playbackData to do JavaScript "(function(){const v=document.querySelector('video');if(!v)return '';const c=Array.from(document.querySelectorAll('.ytp-caption-segment')).map(e=>e.textContent||'').join(' ').replace(/[|\\\\r\\\\n]+/g,' ');return[(v.paused?'paused':'playing'),v.duration||0,v.currentTime||0,c].join('|||')})()" in mediaTab
                end try
                return (name of mediaTab) & "<<<MACSPACES>>>" & (URL of mediaTab) & "<<<MACSPACES>>>" & playbackData
                """
        ),
        Browser(
            bundleID: "com.google.Chrome",
            appName: "Google Chrome",
            scriptBody: """
                if (count of windows) is 0 then return ""
                set mediaTab to active tab of front window
                set playbackData to ""
                try
                    set playbackData to execute mediaTab javascript "(function(){const v=document.querySelector('video');if(!v)return '';const c=Array.from(document.querySelectorAll('.ytp-caption-segment')).map(e=>e.textContent||'').join(' ').replace(/[|\\\\r\\\\n]+/g,' ');return[(v.paused?'paused':'playing'),v.duration||0,v.currentTime||0,c].join('|||')})()"
                end try
                return (title of mediaTab) & "<<<MACSPACES>>>" & (URL of mediaTab) & "<<<MACSPACES>>>" & playbackData
                """
        ),
        Browser(
            bundleID: "com.microsoft.edgemac",
            appName: "Microsoft Edge",
            scriptBody: """
                if (count of windows) is 0 then return ""
                set mediaTab to active tab of front window
                set playbackData to ""
                try
                    set playbackData to execute mediaTab javascript "(function(){const v=document.querySelector('video');if(!v)return '';const c=Array.from(document.querySelectorAll('.ytp-caption-segment')).map(e=>e.textContent||'').join(' ').replace(/[|\\\\r\\\\n]+/g,' ');return[(v.paused?'paused':'playing'),v.duration||0,v.currentTime||0,c].join('|||')})()"
                end try
                return (title of mediaTab) & "<<<MACSPACES>>>" & (URL of mediaTab) & "<<<MACSPACES>>>" & playbackData
                """
        ),
    ]

    private static let workQueue = DispatchQueue(label: "dev.opensource.macspaces.browser-media")
    private static let artworkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        return URLSession(configuration: configuration)
    }()

    private let transport: MediaRemoteProvider
    private let artworkCache = NSCache<NSString, NSImage>()
    private var pendingArtworkURLs = Set<String>()
    private let artworkLock = NSLock()

    init(transport: MediaRemoteProvider) {
        self.transport = transport
    }

    var isAvailable: Bool {
        !activeBrowsers().isEmpty
    }

    func fetchNowPlaying(_ completion: @escaping (NowPlayingInfo?) -> Void) {
        let candidates = activeBrowsers()
        guard !candidates.isEmpty else {
            completion(nil)
            return
        }

        Self.workQueue.async { [weak self] in
            for browser in candidates {
                let source = """
                tell application "\(browser.appName)"
                    \(browser.scriptBody)
                end tell
                """
                let scriptResult = AppleScriptRunner.runSynchronously(source)
                let result = scriptResult.descriptor?.stringValue ?? ""
                let parts = result.components(separatedBy: "<<<MACSPACES>>>")
                guard parts.count >= 2,
                      let url = URL(string: parts[1]),
                      Self.isSupportedMediaURL(url) else {
                    continue
                }

                var info = NowPlayingInfo()
                info.title = Self.cleanTitle(parts[0], for: url)
                info.artist = Self.sourceLabel(for: url, browserName: browser.appName)
                info.sourceURL = url
                // A supported active tab is the best public signal browsers expose
                // without requiring Accessibility or JavaScript-from-Apple-Events.
                // Transport commands still go through MediaRemote.
                info.isPlaying = true
                if parts.count > 2 {
                    let playback = parts[2].components(separatedBy: "|||")
                    if playback.count >= 3 {
                        info.isPlaying = playback[0] == "playing"
                        info.duration = Double(playback[1]) ?? 0
                        info.elapsed = Double(playback[2]) ?? 0
                        if playback.count > 3 {
                            info.subtitleText = playback[3]
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }

                if let artworkURL = Self.artworkURL(for: url) {
                    let key = artworkURL.absoluteString as NSString
                    info.artwork = self?.artworkCache.object(forKey: key)
                    if info.artwork == nil {
                        self?.prefetchArtwork(from: artworkURL)
                    }
                }
                completion(info)
                return
            }
            completion(nil)
        }
    }

    func send(_ command: NowPlayingCommand) {
        transport.send(command)
    }

    private func activeBrowsers() -> [Browser] {
        browsers.filter { browser in
            !NSRunningApplication
                .runningApplications(withBundleIdentifier: browser.bundleID)
                .isEmpty
        }
    }

    private func prefetchArtwork(from url: URL) {
        let key = url.absoluteString
        artworkLock.lock()
        guard pendingArtworkURLs.insert(key).inserted else {
            artworkLock.unlock()
            return
        }
        artworkLock.unlock()

        Self.artworkSession.dataTask(with: url) { [weak self] data, _, _ in
            defer {
                self?.artworkLock.lock()
                self?.pendingArtworkURLs.remove(key)
                self?.artworkLock.unlock()
            }
            guard let data, let image = NSImage(data: data) else { return }
            self?.artworkCache.setObject(image, forKey: key as NSString)
        }
        .resume()
    }

    private static func isSupportedMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be"
            || host.hasSuffix("youtube.com")
            || host.hasSuffix("music.youtube.com")
            || host.hasSuffix("soundcloud.com")
            || host.hasSuffix("bandcamp.com")
            || host.hasSuffix("vimeo.com")
            || host.hasSuffix("twitch.tv")
    }

    private static func cleanTitle(_ rawTitle: String, for url: URL) -> String {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [
            " - YouTube",
            " | YouTube Music",
            " on SoundCloud",
            " | Bandcamp",
            " - Twitch",
        ]
        for suffix in suffixes where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
        }
        if title.isEmpty {
            return url.host ?? "Browser media"
        }
        return title
    }

    private static func sourceLabel(for url: URL, browserName: String) -> String {
        let host = url.host?.lowercased() ?? ""
        let service: String
        if host.contains("youtube") || host == "youtu.be" {
            service = host.contains("music.") ? "YouTube Music" : "YouTube"
        } else if host.contains("soundcloud") {
            service = "SoundCloud"
        } else if host.contains("bandcamp") {
            service = "Bandcamp"
        } else if host.contains("vimeo") {
            service = "Vimeo"
        } else if host.contains("twitch") {
            service = "Twitch"
        } else {
            service = browserName
        }
        return "\(service) · \(browserName)"
    }

    private static func artworkURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "youtu.be"
                || host.hasSuffix("youtube.com")
                || host.hasSuffix("music.youtube.com") else {
            return nil
        }

        let videoID: String?
        if host == "youtu.be" {
            videoID = url.pathComponents.dropFirst().first
        } else {
            videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value
        }
        guard let videoID, !videoID.isEmpty else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }
}
