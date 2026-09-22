import AppKit

/// System-wide now-playing info via the private MediaRemote framework,
/// loaded dynamically so the app degrades gracefully when the framework or
/// its symbols are unavailable (e.g. entitlement restrictions on macOS 15.4+).
final class MediaRemoteProvider: NowPlayingProvider {
    private typealias GetNowPlayingInfoFn =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias SendCommandFn =
        @convention(c) (Int, AnyObject?) -> Bool
    private typealias GetIsPlayingFn =
        @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias SetElapsedTimeFn =
        @convention(c) (Double) -> Void
    private typealias RegisterNotificationsFn =
        @convention(c) (DispatchQueue) -> Void

    private let getNowPlayingInfo: GetNowPlayingInfoFn?
    private let sendCommand: SendCommandFn?
    private let getIsPlaying: GetIsPlayingFn?
    private let setElapsedTime: SetElapsedTimeFn?
    private var observers: [NSObjectProtocol] = []
    var onChange: (() -> Void)?

    // MRMediaRemoteCommand values.
    private enum Command: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    init() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else {
            getNowPlayingInfo = nil
            sendCommand = nil
            getIsPlaying = nil
            setElapsedTime = nil
            return
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        getNowPlayingInfo = symbol("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfoFn.self)
        sendCommand = symbol("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        getIsPlaying = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFn.self)
        setElapsedTime = symbol("MRMediaRemoteSetElapsedTime", as: SetElapsedTimeFn.self)
        let registerNotifications = symbol(
            "MRMediaRemoteRegisterForNowPlayingNotifications",
            as: RegisterNotificationsFn.self
        )
        registerNotifications?(DispatchQueue.main)

        let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingPlaybackStateDidChangeNotification",
        ]
        observers = notificationNames.map { rawName in
            NotificationCenter.default.addObserver(
                forName: Notification.Name(rawName),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onChange?()
            }
        }
    }

    var isAvailable: Bool {
        getNowPlayingInfo != nil && sendCommand != nil
    }

    func fetchNowPlaying(_ completion: @escaping (NowPlayingInfo?) -> Void) {
        guard let getNowPlayingInfo else {
            completion(nil)
            return
        }

        getNowPlayingInfo(DispatchQueue.global(qos: .userInitiated)) { [weak self] dict in
            guard let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
                  !title.isEmpty else {
                completion(nil)
                return
            }

            var info = NowPlayingInfo()
            info.title = title
            info.artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            info.album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            info.artwork = Self.extractArtwork(from: dict)
            if let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                info.isPlaying = rate > 0
            }
            info.duration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
            info.elapsed = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0

            // Playback rate is not always populated; double-check with the
            // dedicated is-playing call when available.
            if let getIsPlaying = self?.getIsPlaying, !info.isPlaying {
                getIsPlaying(DispatchQueue.global(qos: .userInitiated)) { playing in
                    info.isPlaying = playing
                    completion(info)
                }
            } else {
                completion(info)
            }
        }
    }

    /// MediaRemote has used several artwork key/value shapes across macOS
    /// releases. Resolve known keys first, then inspect artwork-labelled
    /// payloads so Sonoma through Tahoe all degrade cleanly.
    private static func extractArtwork(from dictionary: [String: Any]) -> NSImage? {
        let preferredKeys = [
            "kMRMediaRemoteNowPlayingInfoArtworkData",
            "MRMediaRemoteNowPlayingInfoArtworkData",
            "artworkData",
            "ArtworkData",
        ]

        for key in preferredKeys {
            if let image = image(from: dictionary[key]) {
                return image
            }
        }

        for (key, value) in dictionary
        where key.localizedCaseInsensitiveContains("artwork")
            || key.localizedCaseInsensitiveContains("image") {
            if let image = image(from: value) {
                return image
            }
        }
        return nil
    }

    private static func image(from value: Any?) -> NSImage? {
        if let image = value as? NSImage {
            return image
        }
        if let data = value as? Data {
            return NSImage(data: data)
        }
        if let data = value as? NSData {
            return NSImage(data: data as Data)
        }
        if let url = value as? URL,
           let data = try? Data(contentsOf: url) {
            return NSImage(data: data)
        }
        if let nested = value as? [String: Any] {
            for child in nested.values {
                if let image = image(from: child) {
                    return image
                }
            }
        }
        if let nested = value as? NSDictionary {
            for child in nested.allValues {
                if let image = image(from: child) {
                    return image
                }
            }
        }
        return nil
    }

    func send(_ command: NowPlayingCommand) {
        if case .seek(let elapsed) = command {
            setElapsedTime?(elapsed)
            return
        }
        guard let sendCommand else { return }
        let mrCommand: Command
        switch command {
        case .togglePlayPause: mrCommand = .togglePlayPause
        case .nextTrack: mrCommand = .nextTrack
        case .previousTrack: mrCommand = .previousTrack
        case .seek: return
        }
        _ = sendCommand(mrCommand.rawValue, nil)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
