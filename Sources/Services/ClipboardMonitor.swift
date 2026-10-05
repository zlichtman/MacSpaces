import AppKit
import ApplicationServices
import Combine

/// The closed Nook's count of clips left to paste.
@MainActor final class PasteQueueState: ObservableObject {
    static let shared = PasteQueueState()
    @Published var remaining = 0
}

/// Local clipboard history; persistence remains off until explicitly enabled.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []

    /// Paste queue: while on, every copy joins the queue and each ⌘V pastes the
    /// next clip. Noticing ⌘V in other apps needs Accessibility; nothing else does.
    @Published private(set) var queueEnabled = UserDefaults.standard.bool(forKey: "clipboard.pasteQueue")
    @Published private(set) var queue = PasteQueue() {
        didSet { PasteQueueState.shared.remaining = queueEnabled ? queue.count : 0 }
    }
    @Published private(set) var queueNeedsAccess = false
    private var keyMonitors: [Any] = []
    private var advancePending = false

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
    private var preferenceWatch: AnyCancellable?
    private var quitObserver: NSObjectProtocol?

    init() {
        history.historyLimit = ClipboardPreferences.shared.historyLimit
        preferenceWatch = ClipboardPreferences.shared.$historyLimit.dropFirst().sink { [weak self] limit in
            guard let self else { return }
            self.history.historyLimit = limit
            self.entries = self.history.entries
            self.persist()
        }
        // "Clear history on quit" also removes saved history, so nothing outlives the session.
        quitObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, ClipboardPreferences.shared.clearsOnQuit else { return }
                self.history.clear(keepingFavorites: true)
                self.entries = self.history.entries
                if self.persistenceEnabled {
                    let snapshot = SavedHistory(entries: self.entries)
                    try? JSONEncoder().encode(snapshot).write(to: self.persistenceURL, options: [.atomic])
                }
            }
        }
        if let order = UserDefaults.standard.string(forKey: "clipboard.pasteQueueOrder").flatMap(PasteQueue.Order.init) {
            queue.order = order
        }
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
        // Queued copies can come quickly, one after another; history alone can wait.
        timer = Timer.scheduledTimer(withTimeInterval: queueEnabled ? 0.15 : 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
                self?.watchPastes()
            }
        }
        watchPastes()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        removeKeyMonitors()
    }

    // MARK: - Paste queue

    func setQueueEnabled(_ enabled: Bool) {
        guard enabled != queueEnabled else { return }
        if !enabled, let latest = queue.items.last {
            // Hand back what was copied last, as if the queue had never reordered it.
            write(latest)
        }
        queueEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "clipboard.pasteQueue")
        queue.clear()
        if enabled, !AXIsProcessTrusted() {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
        if timer != nil { stop(); start() }
    }

    func setQueueOrder(_ order: PasteQueue.Order) {
        queue.order = order
        UserDefaults.standard.set(order.rawValue, forKey: "clipboard.pasteQueueOrder")
        if let next = queue.next { write(next) }
    }

    func removeFromQueue(_ entry: ClipboardEntry) {
        let wasNext = queue.next?.id == entry.id
        queue.remove(entry.id)
        if wasNext, let next = queue.next { write(next) }
    }

    func clearQueue() { queue.clear() }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Key monitors in other apps only report once MacSpaces is trusted, and a
    /// monitor added before that never starts, so it's added when trust arrives.
    private func watchPastes() {
        guard queueEnabled else { removeKeyMonitors(); queueNeedsAccess = false; return }
        let trusted = AXIsProcessTrusted()
        if queueNeedsAccess != !trusted { queueNeedsAccess = !trusted }
        guard trusted, keyMonitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let paste = Self.isPaste(event)
            Task { @MainActor in if paste { self?.pasted() } }
        }) { keyMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if Self.isPaste(event) { Task { @MainActor in self?.pasted() } }
            return event
        }) { keyMonitors.append(local) }
    }

    private func removeKeyMonitors() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
    }

    /// ⌘V, including Paste and Match Style (⌥⇧⌘V); held-key repeats don't count.
    nonisolated private static func isPaste(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !event.isARepeat && flags.contains(.command) && !flags.contains(.control)
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    /// The app reads the clipboard as it handles ⌘V, so the next clip goes on a
    /// moment later. A second ⌘V inside that moment pastes the same clip again
    /// rather than skipping one.
    private func pasted() {
        guard queueEnabled, !queue.isEmpty, !advancePending else { return }
        advancePending = true
        let expected = NSPasteboard.general.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.advancePending = false
            // Something new was copied meanwhile: poll() queues it instead.
            guard NSPasteboard.general.changeCount == expected, expected == self.lastChangeCount else { return }
            if let next = self.queue.advance() { self.write(next) }
        }
    }

    /// Puts a clip on the clipboard without recording it again.
    private func write(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if entry.representations.isEmpty { pasteboard.setString(entry.text, forType: .string) }
        else {
            pasteboard.writeObjects(entry.representations.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: .init(type)) }
                return item
            })
        }
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Never capture concealed/transient contents (password managers, etc.).
        guard pasteboard.availableType(from: Self.sensitiveTypes) == nil else { return }
        let preferences = ClipboardPreferences.shared
        guard !preferences.paused else { return }
        if preferences.ignoresNextCopy { preferences.ignoresNextCopy = false; return }

        let source = NSWorkspace.shared.frontmostApplication
        guard let entry = ClipboardCapture.entry(from: pasteboard, sourceName: source?.localizedName ?? "",
                                                 sourceBundleID: source?.bundleIdentifier ?? "", filter: preferences.filter) else { return }
        history.record(entry)
        entries = history.entries
        persist()
        enqueue(entry)
    }

    private func enqueue(_ entry: ClipboardEntry) {
        guard queueEnabled else { return }
        queue.add(entry)
        // In order, the first clip stays on the clipboard until it's pasted.
        if let next = queue.next, next.id != entry.id { write(next) }
    }

    func matching(_ query: String, favoritesOnly: Bool) -> [ClipboardEntry] {
        let preferences = ClipboardPreferences.shared
        return history.matching(query, favoritesOnly: favoritesOnly, mode: preferences.searchMode,
                                order: preferences.sortOrder, pinsFirst: preferences.pinsOnTop)
    }

    // MARK: - Pasting

    /// Puts clips on the clipboard and pastes them into `app` (the app that was
    /// in front before the history popup opened). Several clips are joined by
    /// new lines. Plain text drops formatting. Without Accessibility the clips
    /// are only copied, and macOS is asked for access.
    func paste(_ clips: [ClipboardEntry], plainText: Bool, into app: NSRunningApplication?) {
        guard !clips.isEmpty else { return }
        if clips.count == 1, !plainText {
            copyToPasteboard(clips[0])
        } else {
            let text = clips.map(\.text).joined(separator: "\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            lastChangeCount = pasteboard.changeCount
            for clip in clips {
                var refreshed = clip; refreshed.date = Date()
                history.record(refreshed)
            }
            entries = history.entries
            persist()
        }
        guard AXIsProcessTrusted() else {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            return
        }
        app?.activate()
        // The target app needs a moment to become active before it receives ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Self.postCommandV() }
    }

    nonisolated private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
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

    /// Copies a clip again; with the queue on, it joins the queue instead.
    func copyToPasteboard(_ entry: ClipboardEntry) {
        // Syncing the change count (in write) is what stops poll() from
        // re-recording our own write; the next genuine copy is still kept.
        write(entry)
        if queueEnabled { enqueue(ClipboardEntry(copying: entry)) }

        var refreshed = entry; refreshed.date = Date()
        history.record(refreshed)
        entries = history.entries
        persist()
    }

#if DEBUG
    /// QA captures: a queue of synthetic clips, without touching the clipboard or preferences.
    func setPreviewQueue(_ texts: [String], needsAccess: Bool) {
        queueEnabled = true
        queueNeedsAccess = needsAccess
        queue.clear()
        for text in texts { queue.add(ClipboardEntry(text: text)) }
    }

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
        if ClipboardPreferences.shared.clearsSystemClipboard {
            NSPasteboard.general.clearContents()
            lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    deinit {
        timer?.invalidate()
    }
}
