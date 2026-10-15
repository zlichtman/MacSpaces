import AppKit

/// Spotify announces every song change at once (the distributed notification
/// "com.spotify.client.PlaybackStateChanged", with the track's ID). Listening to it
/// lets the Nook refresh immediately instead of waiting for its next poll, and start
/// fetching Spotify's own cover for that exact track straight away: Spotify's public
/// oEmbed endpoint turns the track ID into its cover image (no account or key).
final class SpotifyCovers {
    static let shared = SpotifyCovers()

    /// A song or play state changed in Spotify.
    var onChange: (() -> Void)?
    /// A cover arrived for (title, artist).
    var onCover: ((String, String, NSImage) -> Void)?

    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var pending = Set<String>()
    private var observer: NSObjectProtocol?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        return URLSession(configuration: configuration)
    }()

    static func key(title: String, artist: String) -> String { "\(title)|\(artist)" }

    func cached(title: String, artist: String) -> NSImage? {
        cache.object(forKey: Self.key(title: title, artist: artist) as NSString)
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let info = note.userInfo ?? [:]
            if let title = info["Name"] as? String, let artist = info["Artist"] as? String,
               let trackID = info["Track ID"] as? String {
                self.fetch(trackID: trackID, title: title, artist: artist)
            }
            self.onChange?()
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    /// The oEmbed request for a track ID ("spotify:track:…" or an open.spotify.com link).
    static func oEmbedURL(trackID: String) -> URL? {
        guard trackID.hasPrefix("spotify:track:") || trackID.contains("open.spotify.com/track/") else { return nil }
        var components = URLComponents(string: "https://open.spotify.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: trackID)]
        return components?.url
    }

    /// oEmbed's thumbnail is 300 px; Spotify serves the same image at 640 px under another size code.
    static func largeCover(_ thumbnail: String) -> URL? {
        URL(string: thumbnail.replacingOccurrences(of: "ab67616d00001e02", with: "ab67616d0000b273"))
    }

    func fetch(trackID: String, title: String, artist: String) {
        let key = Self.key(title: title, artist: artist)
        if let image = cache.object(forKey: key as NSString) { onCover?(title, artist, image); return }
        lock.lock()
        let started = pending.insert(key).inserted
        lock.unlock()
        guard started, let url = Self.oEmbedURL(trackID: trackID) else { return }
        session.dataTask(with: url) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            guard let self, let thumbnail = json?["thumbnail_url"] as? String, let small = URL(string: thumbnail) else {
                self?.done(key, nil, title, artist, final: true); return
            }
            // The 300 px thumbnail is usually cached at the CDN and arrives in ~0.1 s, so it
            // shows first; the 640 px copy replaces it when it lands.
            let large = Self.largeCover(thumbnail).flatMap { $0 == small ? nil : $0 }
            self.session.dataTask(with: small) { [weak self] data, _, _ in
                self?.done(key, data.flatMap(NSImage.init(data:)), title, artist, final: large == nil)
            }.resume()
            if let large {
                self.session.dataTask(with: large) { [weak self] data, _, _ in
                    self?.done(key, data.flatMap(NSImage.init(data:)), title, artist, final: true)
                }.resume()
            }
        }.resume()
    }

    private func done(_ key: String, _ image: NSImage?, _ title: String, _ artist: String, final: Bool) {
        lock.lock()
        let upgrade = image != nil && !final && cache.object(forKey: key as NSString) != nil
        if final { pending.remove(key) }
        lock.unlock()
        // A late 300 px copy never replaces the 640 px one.
        guard let image, !upgrade else { return }
        cache.setObject(image, forKey: key as NSString)
        DispatchQueue.main.async { [weak self] in self?.onCover?(title, artist, image) }
    }
}
