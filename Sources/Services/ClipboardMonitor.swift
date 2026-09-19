import AppKit
import Combine

struct ClipboardEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
    }
}

/// In-memory clipboard history built by polling the general pasteboard.
/// History never leaves the machine and is discarded when the app quits.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    private let maxEntries = 50
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

        // De-duplicate consecutive copies of the same content.
        guard entries.first?.text != text else { return }

        entries.insert(ClipboardEntry(text: text, date: Date()), at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
    }

    func copyToPasteboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        // Syncing the change count is what stops poll() from re-recording our
        // own write; the next genuine copy still bumps the count and is kept.
        lastChangeCount = pasteboard.changeCount

        // Re-copying an existing entry moves it to the top with a fresh date.
        if let index = entries.firstIndex(of: entry) {
            entries.remove(at: index)
        }
        entries.insert(ClipboardEntry(text: entry.text, date: Date()), at: 0)
    }

    func clear() {
        entries.removeAll()
    }

    deinit {
        timer?.invalidate()
    }
}
