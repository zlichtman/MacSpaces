import AppKit
import CryptoKit
import Network
import Security

/// Your Spotify listening and library, through your own Spotify developer app: its Client ID
/// is all MacSpaces needs (sign-in uses PKCE, so there's no secret). The sign-in comes back
/// to a one-off listener on this Mac (127.0.0.1) and is kept in the Keychain. Feeds the Music
/// page's Stats (your top songs and artists over 4 weeks, 6 months and a year) and Backups
/// (Liked Songs and your playlists as CSV files, now or every week).
@MainActor
final class SpotifyLibrary: ObservableObject {
    static let shared = SpotifyLibrary()

    static let port: UInt16 = 43821
    static let redirectURI = "http://127.0.0.1:43821/callback"
    static let clientIDKey = "spotify.clientID"
    static let weeklyKey = "spotify.backupWeekly"
    static let dashboard = URL(string: "https://developer.spotify.com/dashboard")!
    private static let scopes = "user-top-read user-library-read playlist-read-private playlist-read-collaborative"

    enum Range: String, CaseIterable, Codable, Identifiable {
        case short = "short_term", medium = "medium_term", long = "long_term"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .short: return "4 weeks"
            case .medium: return "6 months"
            case .long: return "Year"
            }
        }
    }

    struct Song: Codable, Hashable {
        var title: String
        var artists: String
        var album: String
        var image: URL?
        var link: URL?
    }

    struct Artist: Codable, Hashable {
        var name: String
        var image: URL?
        var link: URL?
    }

    struct Top: Codable, Equatable {
        var songs: [String: [Song]] = [:]
        var artists: [String: [Artist]] = [:]
        var fetched = Date.distantPast
    }

    /// What the Music page's Shelf shows: Liked Songs or one of your playlists.
    struct ShelfSource: Hashable, Identifiable {
        /// Every playlist in one row, Liked Songs first and then by name.
        static let all = ShelfSource(id: "all", name: "All")
        static let liked = ShelfSource(id: "liked", name: SpotifyBackupDiff.likedSongs)
        var id: String
        var name: String
        var image: URL?
        var total: Int?
        /// Spotify's version of a playlist: unchanged means its songs needn't be read again.
        var snapshot: String?

        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// One place on the shelf: a playlist's divider or one of its songs.
    enum ShelfRow: Identifiable {
        case divider(ShelfSource)
        case song(Song, in: ShelfSource, number: Int)

        var id: String {
            switch self {
            case .divider(let source): return "divider:\(source.id)"
            case .song(_, let source, let number): return "\(source.id):\(number)"
            }
        }
        var source: ShelfSource {
            switch self {
            case .divider(let source), .song(_, let source, _): return source
            }
        }
    }

    /// A playlist on the All shelf, as far as it has been read.
    private struct ShelfSection {
        var source: ShelfSource
        var songs: [Song] = []
        var next: String?
        var read = false
        var readAt = Date.distantPast
        var state: SongShelfSection { SongShelfSection(songs: songs.count, read: read, more: next != nil) }
    }

    /// One backup folder's summary (`summary.json` inside it).
    struct Backup: Codable, Hashable, Identifiable {
        var date: Date
        var likedSongs: Int
        var playlists: Int
        var playlistSongs: Int
        var followed: Int
        var folder: String = ""
        /// Each playlist's file name and Spotify ID, so a renamed playlist is still the same one.
        var playlistIDs: [String: String]?
        var id: String { folder }
        var files: Int { 1 + playlists + (followed > 0 ? 1 : 0) }
        var songs: Int { likedSongs + playlistSongs }
    }

    @Published private(set) var account: String?
    @Published private(set) var connecting = false
    @Published var problem: String?
    @Published private(set) var top: Top?
    @Published private(set) var loadingTop = false
    @Published private(set) var progress: String?
    @Published private(set) var backups: [Backup] = []
    @Published private(set) var shelfSources: [ShelfSource] = [.all, .liked]
    @Published private(set) var shelfSource = ShelfSource.all
    @Published private(set) var shelfRows: [ShelfRow] = []
    @Published private(set) var shelfLoading = false
    /// Spotify asked for a pause, so the All shelf is holding off until it's over.
    @Published private(set) var shelfWaiting = false

    var clientID: String {
        get { UserDefaults.standard.string(forKey: Self.clientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.clientIDKey); objectWillChange.send() }
    }
    var isConnected: Bool { account != nil }

    /// Where backups go: one dated folder each.
    nonisolated static var folder: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("MacSpaces Backups", isDirectory: true)
    }

    private var listener: NWListener?
    /// The sign-in attempt waiting on the redirect, so an older attempt's timeout leaves a newer one alone.
    private var attempt = 0
    /// One token refresh at a time: Spotify may rotate the refresh token, so a second
    /// refresh with the old one would fail.
    private var refreshing: Task<Token, Error>?
    private var topTask: Task<Void, Never>?
    private var weeklyTimer: Timer?
    private var previewing = false
    private var shelfTask: Task<Void, Never>?
    /// Watches for Spotify coming forward just after a song is played from here.
    private var focusGuard: NSObjectProtocol?
    /// Watches the backups folder while the Backups view shows, so changes in Finder appear.
    private var backupsWatcher: DispatchSourceFileSystemObject?
    /// Songs already read this run, by source, and when, so reopening the Nook is instant.
    private var shelfCache: [String: (songs: [Song], read: Date)] = [:]
    private var shelfSections: [ShelfSection] = []
    private var shelfSourcesRead = Date.distantPast
    /// The one request the All shelf has out at a time, and the row it's reading around.
    private var shelfSectionTask: Task<Void, Never>?
    private var shelfFocus = 0

    private init() {
        if let token = Token.load() { account = token.name }
        top = Self.loadTop()
        backups = Self.scanBackups()
    }

    // MARK: Connecting

    func connect() {
        let client = clientID
        guard !client.isEmpty else { problem = "Paste your app's Client ID first."; return }
        guard !connecting else { return }
        problem = nil
        connecting = true
        let verifier = Self.randomString(64)
        let state = Self.randomString(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: client), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge), .init(name: "scope", value: Self.scopes),
            .init(name: "state", value: state),
        ]
        attempt += 1
        let current = attempt
        let busy = "Port \(Self.port) is busy, so Spotify can't hand the sign-in back. Quit what's using it and try again."
        do {
            try listen(state: state, failed: { [weak self] in
                guard let self, self.attempt == current, self.connecting else { return }
                self.connecting = false
                self.problem = busy
            }) { [weak self] code in
                guard let self else { return }
                Task { await self.finishConnecting(code: code, verifier: verifier, client: client) }
            }
        } catch {
            connecting = false
            problem = busy
            return
        }
        NSWorkspace.shared.open(components.url!)
        // Gives up after three minutes so a closed browser tab doesn't leave it waiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self] in
            guard let self, self.attempt == current, self.connecting else { return }
            self.stopListening()
            self.connecting = false
            self.problem = "Spotify didn't hand the sign-in back. Try again."
        }
    }

    func disconnect() {
        Token.delete()
        account = nil
        top = nil
        try? FileManager.default.removeItem(at: Self.topURL)
        forgetShelf()
    }

    /// Another account's songs must never show after a sign-out.
    private func forgetShelf() {
        shelfTask?.cancel()
        shelfSectionTask?.cancel()
        shelfSectionTask = nil
        shelfSections = []
        shelfCache = [:]
        shelfRows = []
        shelfSources = [.all, .liked]
        shelfSource = .all
        shelfSourcesRead = .distantPast
        shelfFocus = 0
        shelfLoading = false
    }

    private func finishConnecting(code: String?, verifier: String, client: String) async {
        defer { connecting = false }
        guard let code else { problem = "Spotify didn't allow the sign-in."; return }
        do {
            let json = try await Self.tokenRequest([
                "grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI,
                "client_id": client, "code_verifier": verifier,
            ])
            var token = try Token(json: json, previous: nil)
            Token.save(token)
            let me = try await get("https://api.spotify.com/v1/me")
            token.name = (me["display_name"] as? String) ?? (me["id"] as? String) ?? "Spotify"
            token.user = me["id"] as? String
            Token.save(token)
            account = token.name
            problem = nil
            await loadTop(force: true)
        } catch {
            problem = (error as? SpotifyError)?.message ?? "Spotify's sign-in didn't finish. Check the Client ID and the redirect URI."
        }
    }

    /// A one-off HTTP listener on 127.0.0.1 for Spotify's redirect; it answers once and stops.
    /// A port already taken shows up as the listener failing, after it starts (`failed`).
    private func listen(state: String, failed: @escaping @MainActor () -> Void, completion: @escaping (String?) -> Void) throws {
        stopListening()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] update in
            guard case .failed = update else { return }
            Task { @MainActor in
                self?.stopListening()
                failed()
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let items = URLComponents(string: "http://127.0.0.1" + target)?.queryItems ?? []
                guard target.hasPrefix("/callback") else {
                    connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                                    completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
                let code = items.first { $0.name == "code" }?.value
                let matches = items.first { $0.name == "state" }?.value == state
                let body = matches && code != nil
                    ? "<h2 style='font-family:-apple-system'>Connected. You can close this tab and go back to MacSpaces.</h2>"
                    : "<h2 style='font-family:-apple-system'>Spotify didn't connect. Go back to MacSpaces and try again.</h2>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                Task { @MainActor in
                    self?.stopListening()
                    completion(matches ? code : nil)
                }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func stopListening() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Stats

    /// Starts a stats load that isn't tied to a view: leaving Stats doesn't cancel it, and it
    /// lands whenever it's done. Kept for an hour.
    func refreshTop(force: Bool = false) {
        guard topTask == nil else { return }
        topTask = Task { [weak self] in
            await self?.loadTop(force: force)
            self?.topTask = nil
        }
    }

    /// Spotify's own top songs and artists for each range, the three ranges asked for at once.
    func loadTop(force: Bool = false) async {
        guard isConnected, !loadingTop, !previewing else { return }
        // Saved stats from before artists were ranked from songs load again at once.
        let missingArtists = top.map { $0.artists.values.allSatisfy(\.isEmpty) && $0.songs.values.contains { !$0.isEmpty } } ?? false
        if !force, !missingArtists, let top, Date().timeIntervalSince(top.fetched) < 3600 { return }
        loadingTop = true
        defer { loadingTop = false }
        do {
            var fresh = Top()
            try await withThrowingTaskGroup(of: (String, [Song], [Artist]).self) { group in
                for range in Range.allCases {
                    group.addTask { @MainActor [self] in
                        let songs = try await get("https://api.spotify.com/v1/me/top/tracks?time_range=\(range.rawValue)&limit=50")
                        // Spotify can refuse top artists to a development app while it answers top
                        // songs; that leaves them to be ranked from the songs, not a failed load.
                        let artists = try? await get("https://api.spotify.com/v1/me/top/artists?time_range=\(range.rawValue)&limit=50")
                        let songItems = songs["items"] as? [[String: Any]] ?? []
                        let ranked = (artists?["items"] as? [[String: Any]] ?? []).compactMap(Self.artist)
                        return (range.rawValue, songItems.compactMap(Self.song), ranked.isEmpty ? Self.artists(fromSongs: songItems) : ranked)
                    }
                }
                for try await (range, songs, artists) in group {
                    fresh.songs[range] = songs
                    fresh.artists[range] = artists
                }
            }
            fresh.fetched = Date()
            top = fresh
            Self.saveTop(fresh)
            problem = nil
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            problem = (error as? SpotifyError)?.message ?? "Spotify's stats didn't load. Try again in a moment."
        }
    }

    // MARK: Backups

    /// Liked Songs, each playlist you own or collaborate on (Spotify only returns those
    /// songs), and a list of the playlists you follow, as CSV files in a dated folder.
    func backUp() async {
        guard isConnected, progress == nil, !previewing else { return }
        progress = "Reading Liked Songs"
        defer { progress = nil }
        var backupFolder: URL?
        do {
            let me = Token.load()?.user
            let liked = try await paged("https://api.spotify.com/v1/me/tracks?limit=50")
            let likedRows = liked.compactMap { Self.songRow(($0["item"] ?? $0["track"]) as? [String: Any], added: $0["added_at"] as? String) }
            let playlists = try await paged("https://api.spotify.com/v1/me/playlists?limit=50")
            let mine = playlists.filter { ($0["owner"] as? [String: Any])?["id"] as? String == me || $0["collaborative"] as? Bool == true }
            let followed = playlists.filter { item in !mine.contains { $0["id"] as? String == item["id"] as? String } }

            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH.mm"; formatter.locale = Locale(identifier: "en_US_POSIX")
            // Each run gets its own folder, so one that fails removes only what it made.
            let stamp = formatter.string(from: Date())
            var folder = Self.folder.appendingPathComponent(stamp, isDirectory: true)
            var attempt = 2
            while FileManager.default.fileExists(atPath: folder.path) {
                folder = Self.folder.appendingPathComponent("\(stamp) \(attempt)", isDirectory: true)
                attempt += 1
            }
            backupFolder = folder
            let lists = folder.appendingPathComponent("Playlists", isDirectory: true)
            try FileManager.default.createDirectory(at: lists, withIntermediateDirectories: true)
            try SpotifyCSV.document(header: SpotifyCSV.songHeader, rows: likedRows)
                .write(to: folder.appendingPathComponent("Liked Songs.csv"), atomically: true, encoding: .utf8)

            var playlistSongs = 0
            var used = Set<String>()
            var playlistIDs: [String: String] = [:]
            for (index, playlist) in mine.enumerated() {
                guard let id = playlist["id"] as? String else { continue }
                let name = playlist["name"] as? String ?? "Untitled"
                progress = "Backing up playlist \(index + 1) of \(mine.count)"
                let items = try await paged("https://api.spotify.com/v1/playlists/\(id)/items?limit=100")
                let rows = items.compactMap { Self.songRow(($0["item"] ?? $0["track"]) as? [String: Any], added: $0["added_at"] as? String) }
                playlistSongs += rows.count
                var file = SpotifyCSV.fileName(name)
                while used.contains(file.lowercased()) { file += " (\(id.prefix(4)))" }
                used.insert(file.lowercased())
                playlistIDs[file] = id
                try SpotifyCSV.document(header: SpotifyCSV.songHeader, rows: rows)
                    .write(to: lists.appendingPathComponent(file + ".csv"), atomically: true, encoding: .utf8)
            }
            if !followed.isEmpty {
                let rows = followed.map { item -> [String] in
                    let owner = item["owner"] as? [String: Any]
                    let count = ((item["items"] ?? item["tracks"]) as? [String: Any])?["total"] as? Int
                    return [item["name"] as? String ?? "", owner?["display_name"] as? String ?? owner?["id"] as? String ?? "",
                            count.map(String.init) ?? "", ((item["external_urls"] as? [String: Any])?["spotify"] as? String) ?? ""]
                }
                try SpotifyCSV.document(header: SpotifyCSV.playlistHeader, rows: rows)
                    .write(to: folder.appendingPathComponent("Playlists you follow.csv"), atomically: true, encoding: .utf8)
            }
            let summary = Backup(date: Date(), likedSongs: likedRows.count, playlists: mine.count,
                                 playlistSongs: playlistSongs, followed: followed.count, playlistIDs: playlistIDs)
            try JSONEncoder().encode(summary).write(to: folder.appendingPathComponent("summary.json"))
            backups = Self.scanBackups()
            problem = nil
        } catch {
            // A backup that stopped part-way leaves nothing behind (it has no summary, so it isn't listed).
            if let backupFolder { try? FileManager.default.removeItem(at: backupFolder) }
            problem = (error as? SpotifyError)?.message ?? "The backup stopped: \(error.localizedDescription)"
        }
    }

    var weekly: Bool {
        get { UserDefaults.standard.object(forKey: Self.weeklyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.weeklyKey); objectWillChange.send() }
    }

    /// Checks twice a day whether a weekly backup is due (only once connected).
    func startWeekly() {
        guard weeklyTimer == nil else { return }
        let check = { [weak self] in
            Task { @MainActor in
                guard let self, self.weekly, self.isConnected else { return }
                if let last = self.backups.first?.date, Date().timeIntervalSince(last) < 7 * 86_400 { return }
                await self.backUp()
            }
        }
        let timer = Timer(timeInterval: 12 * 3600, repeats: true) { _ in check() }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        weeklyTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { check() }
    }

    /// Opens a song or artist in the Spotify app (open.spotify.com/track/ID → spotify:track:ID),
    /// or on the web when the app isn't installed.
    static func openInApp(_ link: URL) {
        // Path components come back decoded; a search's words are encoded again for the URI.
        let parts = link.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
            .map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }
        if parts.count >= 2, let app = URL(string: "spotify:" + parts.prefix(2).joined(separator: ":")),
           NSWorkspace.shared.urlForApplication(toOpen: app) != nil {
            NSWorkspace.shared.open(app)
            // A song also plays: opening its link only shows it. The ID is letters and digits.
            if parts[0] == "track", parts[1].allSatisfy({ $0.isLetter || $0.isNumber }) {
                let uri = "spotify:track:" + parts[1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    AppleScriptRunner.run("tell application \"Spotify\" to play track \"\(uri)\"")
                }
            }
        } else {
            NSWorkspace.shared.open(link)
        }
    }

    /// Every song a finished backup holds, read from its CSV files. Call it off the main thread.
    /// A file that's missing or short is an error: a partial read must never look like songs removed.
    nonisolated static func songs(in backup: Backup) throws -> [SpotifyBackupSong] {
        let root = folder.appendingPathComponent(backup.folder, isDirectory: true)
        var songs = SpotifyBackupSong.rows(csv: try String(contentsOf: root.appendingPathComponent("Liked Songs.csv"), encoding: .utf8),
                                           playlist: SpotifyBackupDiff.likedSongs)
        let lists = root.appendingPathComponent("Playlists", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: lists, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "csv" {
            let name = file.deletingPathExtension().lastPathComponent
            songs += SpotifyBackupSong.rows(csv: try String(contentsOf: file, encoding: .utf8), playlist: name, playlistID: backup.playlistIDs?[name])
        }
        guard songs.count == backup.songs else {
            throw SpotifyError(message: "This backup's files don't match what it saved, so it can't be compared.")
        }
        return songs
    }

    /// What changed in a backup since the one before it, on a background thread.
    nonisolated static func changes(from previous: Backup, to current: Backup) async throws -> SpotifyBackupDiff {
        try await Task.detached(priority: .userInitiated) {
            SpotifyBackupDiff(current: try songs(in: current), previous: try songs(in: previous))
        }.value
    }

    // MARK: Shelf

    /// Shows a source's songs, reading any that aren't recent page by page, so the shelf fills as they arrive.
    func loadShelf(_ source: ShelfSource) {
        guard isConnected, !previewing else { return }
        if source == .all { loadAllShelf(); return }
        let changed = source != shelfSource
        if !changed, !shelfRows.isEmpty, shelfLoading { return }
        shelfTask?.cancel()
        shelfSource = source
        if shelfSources.count <= 2 { refreshShelfSources() }
        if let cached = shelfCache[source.id], Date().timeIntervalSince(cached.read) < 3600 {
            shelfRows = Self.rows(cached.songs, in: source)
            shelfLoading = false
            return
        }
        if changed { shelfRows = [] }
        shelfLoading = true
        shelfTask = Task { [weak self, source] in
            guard let self else { return }
            var songs: [Song] = []
            var next: String? = Self.firstPage(of: source)
            do {
                while let page = next, !Task.isCancelled {
                    let json = try await self.get(page)
                    songs += Self.songs(in: json)
                    next = json["next"] as? String
                    guard !Task.isCancelled else { return }
                    self.shelfRows = Self.rows(songs, in: source)
                }
                guard !Task.isCancelled else { return }
                self.shelfCache[source.id] = (songs, Date())
            } catch {
                guard !Task.isCancelled else { return }
                self.problem = (error as? SpotifyError)?.message ?? "Couldn't read your songs: \(error.localizedDescription)"
            }
            self.shelfLoading = false
        }
    }

    private static func firstPage(of source: ShelfSource) -> String {
        source == .liked ? "https://api.spotify.com/v1/me/tracks?limit=50" : "https://api.spotify.com/v1/playlists/\(source.id)/items?limit=100"
    }

    private static func songs(in page: [String: Any]) -> [Song] {
        (page["items"] as? [[String: Any]] ?? []).compactMap { shelfSong(($0["item"] ?? $0["track"]) as? [String: Any]) }
    }

    private static func rows(_ songs: [Song], in source: ShelfSource) -> [ShelfRow] {
        songs.enumerated().map { .song($1, in: source, number: $0 + 1) }
    }

    // MARK: The All shelf

    /// Every playlist in a row, read only as you reach it. The list itself takes a request or two
    /// an hour; covers come from Spotify's image servers rather than its API.
    private func loadAllShelf() {
        if shelfSource == .all, shelfLoading, shelfSectionTask == nil, shelfSections.isEmpty { return }
        shelfTask?.cancel()
        shelfSource = .all
        rebuildAllShelf()
        guard Date().timeIntervalSince(shelfSourcesRead) >= 3600 || shelfSections.isEmpty else {
            pumpAllShelf()
            return
        }
        shelfLoading = true
        shelfTask = Task { [weak self] in
            guard let self else { return }
            do {
                let sources = try await self.readShelfSources()
                guard !Task.isCancelled else { return }
                self.shelfSources = [.all, .liked] + sources
                self.shelfSourcesRead = Date()
                self.setSections([.liked] + sources)
            } catch {
                guard !Task.isCancelled else { return }
                self.problem = (error as? SpotifyError)?.message ?? "Couldn't read your playlists: \(error.localizedDescription)"
            }
            self.shelfLoading = false
            self.pumpAllShelf()
        }
    }

    /// The row you've stopped on, so the songs around it get read.
    func shelfFocused(_ row: Int) {
        guard shelfSource == .all else { return }
        shelfFocus = row
        pumpAllShelf()
    }

    /// Takes a newly read list of playlists, keeping the songs of any that haven't changed.
    private func setSections(_ sources: [ShelfSource]) {
        let old = Dictionary(shelfSections.map { ($0.source.id, $0) }, uniquingKeysWith: { first, _ in first })
        shelfSections = sources.map { source in
            if var kept = old[source.id] {
                let same = source.snapshot != nil ? kept.source.snapshot == source.snapshot : Date().timeIntervalSince(kept.readAt) < 3600
                if same {
                    let image = kept.source.image, total = kept.source.total
                    kept.source = source
                    if source == .liked { kept.source.image = image; kept.source.total = total }
                    return kept
                }
            }
            if let cached = shelfCache[source.id], Date().timeIntervalSince(cached.read) < 3600 {
                return ShelfSection(source: source, songs: cached.songs, read: true, readAt: cached.read)
            }
            return ShelfSection(source: source)
        }
        rebuildAllShelf()
    }

    private func rebuildAllShelf() {
        guard shelfSource == .all else { return }
        shelfRows = shelfSections.flatMap { section -> [ShelfRow] in
            section.state.rows == 0 ? [] : [.divider(section.source)] + Self.rows(section.songs, in: section.source)
        }
    }

    /// Reads one page at a time, a moment apart, and only what `SongShelfPlan` says is near.
    private func pumpAllShelf() {
        guard shelfSource == .all, !previewing, shelfSectionTask == nil, !shelfWaiting,
              let index = SongShelfPlan.next(shelfSections.map(\.state), focus: shelfFocus) else { return }
        let source = shelfSections[index].source
        let address = shelfSections[index].next ?? Self.firstPage(of: source)
        shelfSectionTask = Task { [weak self, source, address] in
            guard let self else { return }
            do {
                let page = try await self.get(address)
                guard !Task.isCancelled else { return }
                self.take(page, for: source)
                try? await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                guard !Task.isCancelled else { return }
                self.shelfFailed(error, reading: source)
            }
            guard !Task.isCancelled else { return }
            self.shelfSectionTask = nil
            self.pumpAllShelf()
        }
    }

    private func take(_ page: [String: Any], for source: ShelfSource) {
        guard let index = shelfSections.firstIndex(where: { $0.source == source }) else { return }
        var section = shelfSections[index]
        section.songs += Self.songs(in: page)
        section.next = page["next"] as? String
        section.read = true
        section.readAt = Date()
        section.source.total = page["total"] as? Int ?? section.source.total
        // Liked Songs has no picture of its own, so it wears its newest song's.
        if section.source.image == nil { section.source.image = section.songs.first?.image }
        shelfSections[index] = section
        if section.next == nil { shelfCache[source.id] = (section.songs, section.readAt) }
        rebuildAllShelf()
    }

    /// A playlist Spotify won't give out is skipped; anything else waits, for as long as Spotify
    /// says when it says, rather than asking again straight away.
    private func shelfFailed(_ error: Error, reading source: ShelfSource) {
        let failure = error as? SpotifyError
        if failure?.refused == true, let index = shelfSections.firstIndex(where: { $0.source == source }) {
            shelfSections[index].read = true
            shelfSections[index].next = nil
            rebuildAllShelf()
            if shelfRows.isEmpty { problem = failure?.message }
            return
        }
        if shelfRows.isEmpty { problem = failure?.message ?? "Couldn't read your songs: \(error.localizedDescription)" }
        shelfWaiting = true
        let wait = min(failure?.retryAfter ?? 30, 3600)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.shelfWaiting = false
            self?.pumpAllShelf()
        }
    }

    /// Liked Songs and the playlists you own or share: Spotify gives other playlists' songs to nobody but their owners.
    private func refreshShelfSources() {
        Task { [weak self] in
            guard let self, let sources = try? await self.readShelfSources() else { return }
            self.shelfSources = [.all, .liked] + sources
        }
    }

    private func readShelfSources() async throws -> [ShelfSource] {
        let playlists = try await paged("https://api.spotify.com/v1/me/playlists?limit=50")
        var me = Token.load()?.user
        if me == nil, var token = Token.load() {
            me = try await get("https://api.spotify.com/v1/me")["id"] as? String
            token.user = me
            Token.save(token)
        }
        let mine = playlists.filter { ($0["owner"] as? [String: Any])?["id"] as? String == me || $0["collaborative"] as? Bool == true }
        return mine.compactMap { item -> ShelfSource? in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            let total = ((item["items"] ?? item["tracks"]) as? [String: Any])?["total"] as? Int
            guard total != 0 else { return nil }
            return ShelfSource(id: id, name: name, image: Self.smallestImage(item["images"]), total: total, snapshot: item["snapshot_id"] as? String)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func shelfSong(_ track: [String: Any]?) -> Song? {
        guard let track, let title = track["name"] as? String, let link = spotifyLink(track) else { return nil }
        let album = track["album"] as? [String: Any]
        return Song(title: title, artists: artistNames(track), album: album?["name"] as? String ?? "",
                    image: smallestImage(album?["images"]), link: link)
    }

    /// Plays a song in Spotify, in its playlist or Liked Songs so the ones after it follow.
    /// IDs go into a script, so only plain ones do.
    func play(_ song: Song, in source: ShelfSource) {
        let id = song.link?.lastPathComponent ?? ""
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return }
        let plain: (String) -> Bool = { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
        var context: String?
        if source == .liked {
            if let user = Token.load()?.user, plain(user) { context = "spotify:user:\(user):collection" }
        } else if plain(source.id) {
            context = "spotify:playlist:\(source.id)"
        }
        let inContext = context.map { " in context \"\($0)\"" } ?? ""
        keepFrontApp()
        AppleScriptRunner.run("tell application \"Spotify\" to play track \"spotify:track:\(id)\"\(inContext)")
    }

    private static let spotifyApp = "com.spotify.client"

    /// Playing a song leaves you where you are: if Spotify comes forward in the moments after,
    /// or while it starts up, the app you were in goes back in front.
    private func keepFrontApp() {
        let center = NSWorkspace.shared.notificationCenter
        if let focusGuard { center.removeObserver(focusGuard) }
        focusGuard = nil
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Self.spotifyApp else { return }
        let starting = NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyApp).isEmpty
        let pid = front.processIdentifier
        let observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Self.spotifyApp else { return }
            Task { @MainActor in Self.bringForward(pid) }
        }
        focusGuard = observer
        DispatchQueue.main.asyncAfter(deadline: .now() + (starting ? 15 : 2)) { [weak self] in
            guard let self, self.focusGuard === observer else { return }
            center.removeObserver(observer)
            self.focusGuard = nil
        }
    }

    private static func bringForward(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        app.activate(options: [])
        // Newer macOS can refuse a request from an app that isn't in front, so ask from the front.
        guard #available(macOS 14, *) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == spotifyApp, !app.isTerminated else { return }
            NSApp.activate(ignoringOtherApps: true)
            app.activate(from: .current, options: [])
        }
    }

    func showFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folder)
    }

    func show(_ backup: Backup) {
        NSWorkspace.shared.activateFileViewerSelecting([Self.folder.appendingPathComponent(backup.folder, isDirectory: true)])
    }

    /// Moves a backup to the Trash, so it can still be put back.
    func trash(_ backup: Backup) {
        guard !previewing else { return }
        do {
            try FileManager.default.trashItem(at: Self.folder.appendingPathComponent(backup.folder, isDirectory: true), resultingItemURL: nil)
            problem = nil
        } catch {
            problem = "Couldn't move that backup to the Trash: \(error.localizedDescription)"
        }
        backups = Self.scanBackups()
    }

    /// Reads the folder now and whenever something in it changes, until `stopWatchingBackups`.
    func watchBackups() {
        guard !previewing else { return }
        backups = Self.scanBackups()
        guard backupsWatcher == nil else { return }
        let descriptor = open(Self.folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.backups = Self.scanBackups()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        backupsWatcher = source
    }

    func stopWatchingBackups() {
        backupsWatcher?.cancel()
        backupsWatcher = nil
    }

    private static func scanBackups() -> [Backup] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { url -> Backup? in
            guard var backup = try? JSONDecoder().decode(Backup.self, from: Data(contentsOf: url.appendingPathComponent("summary.json"))) else { return nil }
            backup.folder = url.lastPathComponent
            return backup
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: Web API

    struct SpotifyError: Error {
        let message: String
        /// Spotify refused the refresh token itself (`invalid_grant`): the sign-in is gone.
        var revoked = false
        /// Spotify won't give this out: asking again won't help.
        var refused = false
        /// Spotify's rate limit: how long it asks us to wait, in seconds.
        var retryAfter: Double?
    }

    private func get(_ address: String, retried: Bool = false) async throws -> [String: Any] {
        guard var token = Token.load() else { throw SpotifyError(message: "Connect Spotify again.") }
        if token.expires < Date().addingTimeInterval(60) { token = try await refresh(token) }
        var request = URLRequest(url: URL(string: address)!, timeoutInterval: 30)
        request.setValue("Bearer \(token.access)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !retried { _ = try await refresh(token); return try await get(address, retried: true) }
        if status == 429 {
            let wait = Double((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
            // A long wait means stop asking: trying again early only extends it.
            guard !retried, wait <= 20 else {
                throw SpotifyError(message: "Spotify asked to wait \(Int(wait.rounded(.up))) seconds, so try again after that.", retryAfter: wait)
            }
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            return try await get(address, retried: true)
        }
        guard status == 200 else {
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            if status == 403 { throw SpotifyError(message: "Spotify said no (\(detail ?? "403")). Your app's owner needs Premium, and you need to be on its user list.", refused: true) }
            if status == 404 { throw SpotifyError(message: "Spotify couldn't find that.", refused: true) }
            throw SpotifyError(message: "Spotify said: \(detail ?? "error \(status)")")
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Every item of a paged list, following `next`.
    private func paged(_ address: String) async throws -> [[String: Any]] {
        var items: [[String: Any]] = []
        var next: String? = address
        while let page = next {
            let json = try await get(page)
            items += json["items"] as? [[String: Any]] ?? []
            next = json["next"] as? String
        }
        return items
    }

    /// Only a refused refresh token signs you out; offline or a timeout just fails this time.
    private func refresh(_ token: Token) async throws -> Token {
        if let refreshing { return try await refreshing.value }
        guard let refresh = token.refresh else { throw SpotifyError(message: "Connect Spotify again.") }
        let client = clientID
        let task = Task { () throws -> Token in
            let json = try await Self.tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": client])
            return try Token(json: json, previous: token)
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            Token.save(fresh)
            return fresh
        } catch let error as SpotifyError where error.revoked {
            Token.delete()
            forgetShelf()
            account = nil
            throw SpotifyError(message: "Spotify signed you out. Connect again.")
        } catch let error as SpotifyError {
            throw error
        } catch {
            throw SpotifyError(message: "Spotify didn't answer. Check the connection and try again.")
        }
    }

    private static func tokenRequest(_ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SpotifyError(message: "Spotify's sign-in said: \(json["error_description"] as? String ?? json["error"] as? String ?? "no")",
                               revoked: json["error"] as? String == "invalid_grant")
        }
        return json
    }

    private static func song(_ json: [String: Any]) -> Song? {
        guard let title = json["name"] as? String else { return nil }
        let album = json["album"] as? [String: Any]
        return Song(title: title, artists: artistNames(json), album: album?["name"] as? String ?? "",
                    image: smallestImage(album?["images"]), link: spotifyLink(json))
    }

    private static func artist(_ json: [String: Any]) -> Artist? {
        guard let name = json["name"] as? String else { return nil }
        return Artist(name: name, image: smallestImage(json["images"]), link: spotifyLink(json))
    }

    /// When Spotify sends no top artists (it can, for a development app), they're ranked
    /// from the top songs: each credited artist scores more the higher its songs rank, and
    /// shows its best song's cover. Tapping one searches for it in Spotify.
    static func artists(fromSongs items: [[String: Any]]) -> [Artist] {
        var score: [String: Double] = [:], first: [String: (rank: Int, image: URL?)] = [:]
        for (rank, item) in items.enumerated() {
            let image = smallestImage((item["album"] as? [String: Any])?["images"])
            for name in (item["artists"] as? [[String: Any]] ?? []).compactMap({ $0["name"] as? String }) {
                score[name, default: 0] += Double(items.count - rank)
                if first[name] == nil { first[name] = (rank, image) }
            }
        }
        return score.keys
            .sorted { score[$0]! != score[$1]! ? score[$0]! > score[$1]! : first[$0]!.rank < first[$1]!.rank }
            .prefix(50)
            .map { name in
                let query = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? name
                return Artist(name: name, image: first[name]?.image, link: URL(string: "https://open.spotify.com/search/\(query)"))
            }
    }

    private static func songRow(_ track: [String: Any]?, added: String?) -> [String]? {
        guard let track, let title = track["name"] as? String else { return nil }
        let isrc = (track["external_ids"] as? [String: Any])?["isrc"] as? String ?? ""
        return [title, artistNames(track), (track["album"] as? [String: Any])?["name"] as? String ?? "",
                String((added ?? "").prefix(10)), isrc, spotifyLink(track)?.absoluteString ?? ""]
    }

    private static func artistNames(_ json: [String: Any]) -> String {
        (json["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
    }

    private static func spotifyLink(_ json: [String: Any]) -> URL? {
        ((json["external_urls"] as? [String: Any])?["spotify"] as? String).flatMap(URL.init(string:))
    }

    /// The smallest image at least 160 px (Spotify's 300 px), sharp on a Retina tile in the Stats wall.
    private static func smallestImage(_ value: Any?) -> URL? {
        let images = (value as? [[String: Any]] ?? []).sorted { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        let pick = images.first { ($0["width"] as? Int ?? 0) >= 160 } ?? images.last
        return (pick?["url"] as? String).flatMap(URL.init(string:))
    }

    // MARK: Saved state

    private static var topURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dev.opensource.MacSpaces", isDirectory: true)
            .appendingPathComponent("spotify-top.json")
    }

    private static func loadTop() -> Top? {
        guard let data = try? Data(contentsOf: topURL), let plain = try? SecureStorage.open(data) else { return nil }
        return try? JSONDecoder().decode(Top.self, from: plain)
    }

    private static func saveTop(_ top: Top) {
        guard let data = try? JSONEncoder().encode(top), let sealed = try? SecureStorage.seal(data) else { return }
        try? FileManager.default.createDirectory(at: topURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? sealed.write(to: topURL, options: .atomic)
    }

    private static func randomString(_ length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }

    /// The access and refresh tokens, one Keychain item, this Mac only.
    private struct Token: Codable {
        var access: String
        var refresh: String?
        var expires: Date
        var name: String?
        var user: String?

        init(json: [String: Any], previous: Token?) throws {
            guard let access = json["access_token"] as? String else { throw SpotifyError(message: "Spotify sent no sign-in.") }
            self.access = access
            refresh = json["refresh_token"] as? String ?? previous?.refresh
            expires = Date().addingTimeInterval(json["expires_in"] as? Double ?? 3600)
            name = previous?.name
            user = previous?.user
        }

        private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                                   kSecAttrService as String: KeychainService.named("spotify"),
                                                   kSecAttrAccount as String: "token"]

        static func load() -> Token? {
            var query = query
            query[kSecReturnData as String] = true
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return try? JSONDecoder().decode(Token.self, from: data)
        }

        static func save(_ token: Token) {
            guard let data = try? JSONEncoder().encode(token) else { return }
            if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess { return }
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }

        static func delete() { SecItemDelete(query as CFDictionary) }
    }

    #if DEBUG
    /// Captures: a connected account with sample stats and backups, nothing fetched.
    func setPreview(account: String?, top: Top?, backups: [Backup], shelf: [(source: ShelfSource, songs: [Song])] = []) {
        previewing = true
        shelfSource = .all
        shelfRows = shelf.flatMap { [.divider($0.source)] + Self.rows($0.songs, in: $0.source) }
        self.account = account
        self.top = top
        self.backups = backups
    }
    #endif
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
