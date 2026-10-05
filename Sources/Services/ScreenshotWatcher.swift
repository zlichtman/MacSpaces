import AppKit
import Combine

/// New screenshots land in the Tray, and the closed notch shows a thumbnail for
/// a few seconds. Found through Spotlight's screen-capture attribute, so it
/// works wherever macOS saves them. Off until turned on (Settings → General),
/// because reading a screenshot saved on the Desktop makes macOS ask for
/// Desktop access once.
@MainActor
final class ScreenshotWatcher: ObservableObject {
    static let shared = ScreenshotWatcher()

    @Published private(set) var isEnabled: Bool
    /// The newest screenshot while its thumbnail shows beside the notch.
    @Published private(set) var recent: URL?
    @Published private(set) var recentImage: NSImage?
    var onCapture: (URL) -> Void = { _ in }

    private var query: NSMetadataQuery?
    private var since = Date()
    private var seen = Set<URL>()
    private var observers: [NSObjectProtocol] = []
    private var clearRecent: DispatchWorkItem?
    static let showsFor: TimeInterval = 6

    init() {
        isEnabled = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            && UserDefaults.standard.bool(forKey: "screenshots.toTray")
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "screenshots.toTray")
        enabled ? start() : stop()
    }

    func start() {
        guard isEnabled, query == nil else { return }
        since = Date()
        let query = NSMetadataQuery()
        query.predicate = Self.predicate(since: since)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.collect() }
            })
        }
        query.start()
        self.query = query
    }

    /// Spotlight's screen-capture flag, or (where a macOS version doesn't set
    /// it) an image named like a screenshot: macOS's name in common languages,
    /// or the name chosen with `defaults write com.apple.screencapture name`.
    static func predicate(since: Date) -> NSPredicate {
        var prefixes = ["Screenshot", "Screen Shot", "Bildschirmfoto", "Capture d’écran", "Captura de pantalla",
                        "Schermafbeelding", "Istantanea", "Skärmavbild", "Skjermbilde", "スクリーンショット", "截屏", "스크린샷"]
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name"), !custom.isEmpty {
            prefixes.append(custom)
        }
        let named = NSCompoundPredicate(orPredicateWithSubpredicates: prefixes.map {
            NSPredicate(format: "kMDItemFSName LIKE[c] %@", $0 + "*")
        })
        let image = NSPredicate(format: "kMDItemContentTypeTree == 'public.image'")
        let capture = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "kMDItemIsScreenCapture == 1"),
            NSCompoundPredicate(andPredicateWithSubpredicates: [image, named]),
        ])
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            capture, NSPredicate(format: "kMDItemFSCreationDate >= %@", since as NSDate),
        ])
    }

    func stop() {
        query?.stop(); query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    /// Only screenshots taken since watching began count; older ones stay put.
    private func collect() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var fresh: [(URL, Date)] = []
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
                  created >= since else { continue }
            let url = URL(fileURLWithPath: path)
            if seen.insert(url).inserted { fresh.append((url, created)) }
        }
        for (url, _) in fresh.sorted(by: { $0.1 < $1.1 }) {
            onCapture(url)
            show(url)
        }
    }

    private func show(_ url: URL) {
        recent = url
        recentImage = NSImage(contentsOf: url)
        clearRecent?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recent = nil; self?.recentImage = nil }
        clearRecent = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showsFor, execute: work)
    }
}
