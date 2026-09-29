import AppKit
import Combine

/// In-memory clipboard history built by polling the general pasteboard.
/// History never leaves the machine and is discarded when the app quits.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private var history = ClipboardHistory()
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

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        history.record(text)
        entries = history.entries
    }

    func matching(_ query: String, favoritesOnly: Bool) -> [ClipboardEntry] {
        history.matching(query, favoritesOnly: favoritesOnly)
    }

    @discardableResult
    func toggleFavorite(_ entry: ClipboardEntry) -> Bool {
        let changed = history.toggleFavorite(entry.id)
        entries = history.entries
        return changed
    }

    func remove(_ entry: ClipboardEntry) {
        history.remove(entry.id)
        entries = history.entries
    }

    func copyToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        // Syncing the change count is what stops poll() from re-recording our
        // own write; the next genuine copy still bumps the count and is kept.
        lastChangeCount = pasteboard.changeCount

        history.record(entry.text)
        entries = history.entries
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
        history.clear(keepingFavorites: keepingFavorites)
        entries = history.entries
    }

    deinit {
        timer?.invalidate()
    }
}
