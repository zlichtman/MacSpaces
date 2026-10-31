import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SQLite3
import Vision

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
    /// A short message about the last action (the pin limit), cleared after a few seconds.
    @Published private(set) var notice: String?
    private var noticeToken = 0
    @Published private(set) var importingMaccy = false
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
    private var autoDeleteWatch: AnyCancellable?
    private var quitObserver: NSObjectProtocol?

    private var pinsURL: URL { persistenceURL.deletingLastPathComponent().appendingPathComponent("clipboard-pins.json") }
    /// Pins and snippets on disk. If the file can't be read it is kept as it is:
    /// nothing replaces or removes it until Clear All sets it aside.
    private lazy var pinsStore = ProtectedFile(url: pinsURL)

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
                    if let sealed = try? SecureStorage.seal(JSONEncoder().encode(snapshot)) {
                        try? sealed.write(to: self.persistenceURL, options: [.atomic])
                    }
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
                    let saved = try JSONDecoder().decode(SavedHistory.self, from: SecureStorage.open(Data(contentsOf: persistenceURL)))
                    guard saved.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                    history.restore(saved.entries); entries = history.entries
                }
            } catch { storageError = error.localizedDescription; persistenceEnabled = false; storageReadFailed = true }
        }
        // Pins and snippets come back even when the rest of history doesn't.
        switch pinsStore.load({ try JSONDecoder().decode([ClipboardEntry].self, from: SecureStorage.open($0)) }) {
        case .loaded(let pins) where ClipboardPreferences.shared.keepsPins:
            for pin in pins.reversed() where !history.entries.contains(where: { $0.id == pin.id }) { history.record(pin) }
            for pin in pins { history.update(pin.id) { $0 = pin } }
            entries = history.entries
        case .unreadable(let reason):
            storageError = "Saved pins and snippets couldn't be read (\(reason)), so they were kept as they are. Clear All sets the file aside and starts new pins."
        default: break
        }
        // Clips past the auto-delete period go at launch and when the period changes, not only on the next copy.
        if applyAutoDelete(days: ClipboardPreferences.shared.autoDeleteDays) { entries = history.entries; persist() }
        autoDeleteWatch = ClipboardPreferences.shared.$autoDeleteDays.dropFirst().sink { [weak self] days in
            guard let self, self.applyAutoDelete(days: days) else { return }
            self.entries = self.history.entries
            self.persist()
        }
    }

    /// Removes clips not copied in `days` days (pins and snippets stay); true if any went.
    @discardableResult
    private func applyAutoDelete(days: Int) -> Bool {
        guard days > 0 else { return false }
        let count = history.entries.count
        history.removeUnused(olderThan: days)
        return history.entries.count != count
    }

    private func announce(_ message: String) {
        noticeToken += 1
        let token = noticeToken
        notice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.noticeToken == token else { return }
            self.notice = nil
        }
    }

    /// Whether another clip can be pinned; the pin limit is announced when it can't.
    var canPin: Bool { history.canPin }
    var pinLimitMessage: String { history.pinLimitMessage }
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
        savePins()
        guard persistenceEnabled else { return }
        storageRevision += 1
        let snapshot = SavedHistory(entries: entries), url = persistenceURL, revision = storageRevision
        diskQueue.async { [weak self] in
            let failure: String?
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
                // Encrypted with the device key (Secure Enclave where available); never written in plaintext.
                try SecureStorage.seal(JSONEncoder().encode(snapshot)).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                failure = nil
            } catch { failure = error.localizedDescription }
            Task { @MainActor in
                guard let self, self.storageRevision == revision else { return }
                self.storageError = failure
            }
        }
    }
    /// Pins and snippets on their own (0600), so they survive without saving all history.
    private func savePins() {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        // An unreadable pins file is never replaced or removed by an ordinary copy.
        guard pinsStore.isWritable else { return }
        let store = pinsStore
        let pins = ClipboardPreferences.shared.keepsPins ? entries.filter(\.isFavorite) : []
        diskQueue.async { [weak self] in
            if pins.isEmpty { try? store.remove(); return }
            do {
                try store.write(SecureStorage.seal(JSONEncoder().encode(pins)), options: .completeFileProtectionUnlessOpen)
            } catch {
                // Without a readable key nothing is written; say so rather than drop pins quietly.
                let failure = "Pins and snippets couldn't be saved (\(error.localizedDescription))."
                Task { @MainActor in self?.storageError = failure }
            }
        }
    }

    // MARK: - Snippets, collections and more

    /// False when nothing was saved (empty text, or the pin limit, which is announced).
    @discardableResult
    func addSnippet(_ text: String, collection: String? = nil) -> Bool {
        guard history.addSnippet(text, collection: collection) != nil else {
            if !history.canPin { announce(history.pinLimitMessage) }
            return false
        }
        entries = history.entries
        persist()
        return true
    }

    /// Anything filed in a collection is kept like a pin, so filing obeys the pin limit.
    @discardableResult
    func setCollection(_ entry: ClipboardEntry, to name: String?) -> Bool {
        guard history.setCollection(entry.id, to: name) else {
            announce(history.pinLimitMessage)
            return false
        }
        entries = history.entries
        persist()
        return true
    }

    var collections: [String] { history.collections }

    func copy(_ entry: ClipboardEntry, as style: ClipboardEntry.CaseStyle) {
        write(ClipboardEntry(text: entry.text(as: style)))
    }

    /// Picks a colour anywhere on screen (macOS's own magnifier) and copies its hex.
    func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let self, let rgb = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                             Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(hex, forType: .string)
            // Recorded as a clip on the next poll, with its swatch.
        }
    }

    /// Image clips waiting to have their text read, newest last.
    private var ocrWaiting: [(id: UUID, data: Data)] = []
    private var ocrRunning = false
    private let ocrWorker = DispatchQueue(label: "dev.opensource.MacSpaces.clipboard-ocr", qos: .utility)
    private static let ocrBacklog = 24

    /// Reads the text in an image clip (Vision, on this Mac) so it can be searched
    /// and copied. One image is read at a time, newest first; past the backlog the
    /// oldest waiting images are dropped, and results for clips deleted meanwhile are discarded.
    private func recognizeText(in entry: ClipboardEntry) {
        guard entry.isImage, entry.recognizedText.isEmpty, let data = entry.imageData,
              history.entries.contains(where: { $0.id == entry.id }),
              !ocrWaiting.contains(where: { $0.id == entry.id }) else { return }
        ocrWaiting.append((entry.id, data))
        if ocrWaiting.count > Self.ocrBacklog { ocrWaiting.removeFirst(ocrWaiting.count - Self.ocrBacklog) }
        recognizeNext()
    }

    private func recognizeNext() {
        guard !ocrRunning else { return }
        while let last = ocrWaiting.last, !history.entries.contains(where: { $0.id == last.id }) { ocrWaiting.removeLast() }
        guard let next = ocrWaiting.popLast() else { return }
        ocrRunning = true
        let id = next.id, data = next.data
        ocrWorker.async { [weak self] in
            let text = Self.recognizedText(in: data)
            Task { @MainActor in
                guard let self else { return }
                self.ocrRunning = false
                if !text.isEmpty, self.history.entries.contains(where: { $0.id == id && $0.recognizedText.isEmpty }) {
                    self.history.update(id) { $0.recognizedText = String(text.prefix(4000)) }
                    self.entries = self.history.entries
                    self.persist()
                }
                self.recognizeNext()
            }
        }
    }

    nonisolated private static func recognizedText(in data: Data) -> String {
        guard let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    // MARK: - Import from Maccy

    /// Brings in Maccy's history (text, links, rich text, images and files),
    /// pins included. Reads Maccy's own store; asks to choose the file if
    /// macOS keeps it in Maccy's container. The store is read and filtered off
    /// the main thread, then merged by date so newer clips here are never pushed
    /// out. Returns what was kept, after the history size and pin limits.
    func importFromMaccy() async -> MaccyImport.Outcome {
        guard !importingMaccy else { return .cancelled }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/Maccy/Storage.sqlite"),
            home.appendingPathComponent("Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"),
        ]
        var url = candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
        if url == nil {
            let panel = NSOpenPanel()
            panel.message = "Choose Maccy's Storage.sqlite (in Library/Application Support/Maccy)."
            panel.directoryURL = candidates[0].deletingLastPathComponent()
            panel.allowsMultipleSelection = false
            guard await SettingsWindowController.shared.runPanel(panel) else { return .cancelled }
            url = panel.url
        }
        guard let url else { return .cancelled }
        importingMaccy = true
        defer { importingMaccy = false }
        let filter = ClipboardPreferences.shared.filter, limit = history.historyLimit
        let clips: [ClipboardEntry]
        do {
            clips = try await Task.detached(priority: .userInitiated) { [url, filter, limit] in
                MaccyImport.newest(try MaccyImport.load(url, filter: filter), historyLimit: limit)
            }.value
        } catch {
            return .unreadable(error.localizedDescription)
        }
        guard !clips.isEmpty else { return .nothingToImport }
        let landed = history.merge(clips)
        applyAutoDelete(days: ClipboardPreferences.shared.autoDeleteDays)
        entries = history.entries
        persist()
        // Imported images are read for text too, newest first, on the same bounded worker.
        for clip in history.entries.reversed() where landed.contains(clip.id) { recognizeText(in: clip) }
        let kept = history.kept(landed)
        return .imported(clips: kept.clips, pins: kept.pins)
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
        let timer = Timer(timeInterval: queueEnabled ? 0.15 : 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
                self?.watchPastes()
            }
        }
        // Common modes keep polling while a menu is open or a drag is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
        // Every tick: assigning an unchanged value would still redraw everything watching.
        guard queueEnabled else { removeKeyMonitors(); if queueNeedsAccess { queueNeedsAccess = false }; return }
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
        let kept = history.record(entry)
        applyAutoDelete(days: preferences.autoDeleteDays)
        entries = history.entries
        persist()
        enqueue(entry)
        // A copy that merged into an earlier clip is read under that clip's identity.
        if let kept, let stored = history.entries.first(where: { $0.id == kept }) { recognizeText(in: stored) }
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
    /// in front when the history popup opened). Several clips are joined by
    /// new lines. Plain text drops formatting. With no app (MacSpaces itself was
    /// in front, or the app quit) or without Accessibility the clips are only
    /// copied; in the latter case macOS is asked for access.
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
        guard let app, !app.isTerminated else { return }
        guard AXIsProcessTrusted() else {
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            return
        }
        app.activate()
        let v = Self.keyCodeForV()
        // The target app needs a moment to become active before it receives ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Self.postCommandV(v) }
    }

    /// The key that types "v" with ⌘ held in the current keyboard layout (on
    /// Dvorak or AZERTY it isn't QWERTY's V key); QWERTY's when it can't be told.
    /// Text Input Sources are read on the main thread.
    private static func keyCodeForV() -> CGKeyCode {
        let qwerty = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return qwerty }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return qwerty }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let command = UInt32((cmdKey >> 8) & 0xFF)
        for code in 0..<128 {
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), command, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters)
            if status == noErr, length == 1, characters[0] == UniChar(118) { return CGKeyCode(code) } // "v"
        }
        return qwerty
    }

    nonisolated private static func postCommandV(_ v: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// False when the clip couldn't be pinned (the pin limit, which is announced).
    @discardableResult
    func toggleFavorite(_ entry: ClipboardEntry) -> Bool {
        let changed = history.toggleFavorite(entry.id)
        if !changed, history.entries.contains(where: { $0.id == entry.id && !$0.isFavorite }) { announce(history.pinLimitMessage) }
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
        // Clearing everything is the explicit reset for unreadable pins: kept beside, renamed.
        if !keepingFavorites, !pinsStore.isWritable {
            do { try pinsStore.setAside(); storageError = nil } catch { storageError = error.localizedDescription }
        }
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
