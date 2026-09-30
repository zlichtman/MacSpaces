import AppKit
import Combine

/// Local clipboard history; persistence remains off until explicitly enabled.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    @Published private(set) var persistenceEnabled = false
    @Published private(set) var storageError: String?
    private let diskQueue = DispatchQueue(label: "dev.opensource.MacSpaces.clipboard-storage", qos: .utility)
    private var storageRevision = 0
    private var storageReadFailed = false
    private var history = ClipboardHistory()
    private var persistenceURL: URL {
        let isolated = Bundle.main.bundleIdentifier != "dev.opensource.MacSpaces"
        let directory = isolated ? FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpaces")
        return directory.appendingPathComponent("clipboard-v1.json")
    }
    private struct SavedHistory: Codable { var version = 1; var entries: [ClipboardEntry] }
    init() {
        persistenceEnabled = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" && UserDefaults.standard.bool(forKey: "clipboard.persistence")
        if persistenceEnabled {
            do {
                if FileManager.default.fileExists(atPath: persistenceURL.path) {
                    let size = try persistenceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= 48 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                    let saved = try JSONDecoder().decode(SavedHistory.self, from: Data(contentsOf: persistenceURL))
                    guard saved.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                    history.restore(saved.entries); entries = history.entries
                }
            } catch { storageError = error.localizedDescription; persistenceEnabled = false; storageReadFailed = true }
        }
    }
    func setPersistence(_ enabled: Bool) {
        guard !enabled || !storageReadFailed else {
            storageError = "Saved clipboard data could not be read. Clear All explicitly before starting new saved history."
            return
        }
        persistenceEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "clipboard.persistence")
        if enabled { persist() }
        else {
            storageRevision += 1
            let url = persistenceURL, revision = storageRevision
            diskQueue.async { [weak self] in
                let failure: String?
                do {
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    failure = nil
                } catch { failure = error.localizedDescription }
                Task { @MainActor in
                    guard let self, self.storageRevision == revision else { return }
                    self.storageError = failure
                }
            }
        }
    }
    private func persist() {
        guard persistenceEnabled else { return }
        storageRevision += 1
        let snapshot = SavedHistory(entries: entries), url = persistenceURL, revision = storageRevision
        diskQueue.async { [weak self] in
            let failure: String?
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
                try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                failure = nil
            } catch { failure = error.localizedDescription }
            Task { @MainActor in
                guard let self, self.storageRevision == revision else { return }
                self.storageError = failure
            }
        }
    }
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    /// Types declared by password managers and similar apps to mark pasteboard
    /// contents that must not be recorded (see nspasteboard.org).
    private static let sensitiveTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Never capture concealed/transient contents (password managers, etc.).
        guard pasteboard.availableType(from: Self.sensitiveTypes) == nil else { return }

        let source = NSWorkspace.shared.frontmostApplication
        guard let entry = ClipboardCapture.entry(from: pasteboard, sourceName: source?.localizedName ?? "", sourceBundleID: source?.bundleIdentifier ?? "") else { return }
        history.record(entry)
        entries = history.entries
        persist()
    }

    func matching(_ query: String, favoritesOnly: Bool) -> [ClipboardEntry] {
        history.matching(query, favoritesOnly: favoritesOnly)
    }

    @discardableResult
    func toggleFavorite(_ entry: ClipboardEntry) -> Bool {
        let changed = history.toggleFavorite(entry.id)
        entries = history.entries
        persist()
        return changed
    }

    func remove(_ entry: ClipboardEntry) {
        history.remove(entry.id)
        entries = history.entries
        persist()
    }

    func copyToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if entry.representations.isEmpty { pasteboard.setString(entry.text, forType: .string) }
        else {
            let items = entry.representations.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: .init(type)) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        // Syncing the change count is what stops poll() from re-recording our
        // own write; the next genuine copy still bumps the count and is kept.
        lastChangeCount = pasteboard.changeCount

        var refreshed = entry; refreshed.date = Date()
        history.record(refreshed)
        entries = history.entries
        persist()
    }

#if DEBUG
    func setPreviewEntries(_ texts: [String]) {
        stop()
        history.clear()
        for text in texts.reversed() { history.record(text) }
        entries = history.entries
    }
#endif

    func clear(keepingFavorites: Bool = false) {
        if storageReadFailed && !keepingFavorites { storageReadFailed = false; setPersistence(false) }
        history.clear(keepingFavorites: keepingFavorites)
        entries = history.entries
        persist()
    }

    deinit {
        timer?.invalidate()
    }
}
