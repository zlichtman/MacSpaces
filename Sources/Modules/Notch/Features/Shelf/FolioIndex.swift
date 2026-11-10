import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// What MacSpaces has read from one file in the Tray or a basket: the words in it (text in a
/// picture or a scanned page, a PDF's or text file's own text, a link's address) and what a
/// picture shows ("dog", "beach"). Made on this Mac with Vision, never sent anywhere.
struct FolioRecord: Codable, Equatable, Sendable {
    var text: String
    var tags: [String]
    /// A picture's Vision feature print (archived), for Find Similar.
    var print: Data?
    /// The file's modification date when it was read; a newer one reads it again.
    var stamp: Date
    var version: Int
}

/// The library behind the Tray, the file baskets and watched folders (Folio): one index of
/// every file they hold, so search finds words inside pictures and PDFs, what photos show, and
/// your own tags and notes, whichever list a file is in. Files are read one at a time on a
/// low-priority worker, and only once per change; the index and your marks (tags, notes and
/// likes) are two files in Application Support, keyed by path, and follow moved files.
@MainActor
final class FolioIndex: ObservableObject {
    static let shared = FolioIndex()
    /// Bumped when reading improves, so older records are read again.
    nonisolated static let version = 1
    /// Most text kept per file, so one long PDF can't swell the index.
    nonisolated static let textLimit = 20_000

    @Published private(set) var records: [String: FolioRecord] = [:]
    /// Your tags, notes and likes, by path (`folio-marks.json`).
    @Published private(set) var marks = FolioMarkBook()
    /// Files still waiting to be read (Settings shows it).
    @Published private(set) var waitingCount = 0
    /// Files waiting to be read, oldest first.
    private var waiting: [(url: URL, stamp: Date)] = []
    private var queued: Set<String> = []
    private var worker: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var loaded = false
    private var saveWork: DispatchWorkItem?
    private var marksSaveWork: DispatchWorkItem?
    /// Search text per path, folded once (lowercase, no accents, words split by spaces).
    private var folded: [String: String] = [:]
    private let file: URL
    private let marksFile: URL

    init() {
        let root = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests"))
        file = root.appendingPathComponent("MacSpaces", isDirectory: true).appendingPathComponent("folio-index.json")
        marksFile = file.deletingLastPathComponent().appendingPathComponent("folio-marks.json")
        loadTask = Task { [weak self] in await self?.load() }
    }

    func record(for url: URL) -> FolioRecord? { records[url.standardizedFileURL.path] }

    /// A Tray or basket file was checked: reads it unless it's already read at this date.
    func note(_ url: URL, modified: Date?, isDirectory: Bool) {
        guard !isDirectory else { return }
        let path = url.standardizedFileURL.path
        let stamp = modified ?? .distantPast
        if let record = records[path], record.stamp == stamp, record.version == Self.version { return }
        guard !queued.contains(path) else { return }
        queued.insert(path)
        waiting.append((url.standardizedFileURL, stamp))
        waitingCount = waiting.count
        startWorker()
    }

    /// A file moved: its record and your marks move with it.
    func moved(from old: URL, to new: URL) {
        let from = old.standardizedFileURL.path, to = new.standardizedFileURL.path
        guard from != to else { return }
        if marks.mark(from) != nil {
            marks.moved(from: from, to: to)
            folded[from] = nil; folded[to] = nil
            scheduleMarksSave()
        }
        guard let record = records.removeValue(forKey: from) else { return }
        records[to] = record
        folded[from] = nil; folded[to] = nil
        prints[to] = prints.removeValue(forKey: from)
        scheduleSave()
    }

    /// A file left a list for good: its record and marks go unless another list still holds it.
    func forget(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard records[path] != nil || marks.mark(path) != nil, !FolioLibrary.holds(path) else { return }
        if records[path] != nil {
            records[path] = nil; prints[path] = nil
            scheduleSave()
        }
        if marks.mark(path) != nil {
            marks.forget(path)
            scheduleMarksSave()
        }
        folded[path] = nil
    }

    // MARK: Your tags, notes and likes

    func mark(for url: URL) -> FolioMark? { marks.mark(url.standardizedFileURL.path) }
    func isLiked(_ url: URL) -> Bool { marks.isLiked(url.standardizedFileURL.path) }

    func addTags(_ tags: [String], to urls: [URL]) { changeMarks(urls) { $0.addTags(tags, to: $1) } }
    func removeTag(_ tag: String, from urls: [URL]) { changeMarks(urls) { $0.removeTag(tag, from: $1) } }
    func setNote(_ note: String, for urls: [URL]) { changeMarks(urls) { $0.setNote(note, for: $1) } }
    /// Likes them all, or unlikes them when every one is liked already.
    func toggleLike(_ urls: [URL]) { changeMarks(urls) { $0.toggleLike($1) } }

    private func changeMarks(_ urls: [URL], _ change: (inout FolioMarkBook, [String]) -> Void) {
        let paths = urls.map { $0.standardizedFileURL.path }
        guard !paths.isEmpty else { return }
        var book = marks
        change(&book, paths)
        guard book != marks else { return }
        marks = book
        paths.forEach { folded[$0] = nil }
        scheduleMarksSave()
    }

    /// Forgets everything read and reads every file in the Tray and baskets again
    /// (Settings → Folio → Library). Your tags, notes and likes stay.
    func readAgain() {
        records = [:]; folded = [:]; prints = [:]
        scheduleSave()
        FolioLibrary.stores.forEach { $0.pruneMissingItems() }
    }

    // MARK: Search

    /// True when every word of the query starts a word in the file's name, kind, your tags and
    /// note, its automatic tags or its text.
    func matches(_ terms: [String], url: URL, name: String, kind: String) -> Bool {
        guard !terms.isEmpty else { return true }
        let path = url.standardizedFileURL.path
        let haystack: String
        if let cached = folded[path] { haystack = cached }
        else {
            let record = records[path]
            haystack = FolioText.fold([name, kind, marks.searchText(path), record?.tags.joined(separator: " ") ?? "", record?.text ?? ""]
                .joined(separator: " "))
            if record != nil || marks.mark(path) != nil { folded[path] = haystack }
        }
        return FolioText.matches(terms, in: haystack)
    }

    /// A query split into folded words.
    nonisolated static func terms(_ query: String) -> [String] { FolioText.terms(query) }

    /// Lowercase, without accents, every run of non-letters a single space, with a space first
    /// so " word" finds a word's start.
    nonisolated static func fold(_ text: String) -> String { FolioText.fold(text) }

    // MARK: Find Similar

    /// Unarchived prints, kept while MacSpaces runs.
    private var prints: [String: VNFeaturePrintObservation] = [:]

    private func featurePrint(_ path: String) -> VNFeaturePrintObservation? {
        if let print = prints[path] { return print }
        guard let data = records[path]?.print,
              let print = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) else { return nil }
        prints[path] = print
        return print
    }

    /// Whether a file has been read far enough to find pictures like it.
    func canFindSimilar(_ url: URL) -> Bool { records[url.standardizedFileURL.path]?.print != nil }

    /// The pictures most like this one among these files, nearest first: at most `limit`, and
    /// none much further than the nearest (so a picture with no close matches finds few).
    func similar(to url: URL, among urls: [URL], limit: Int = 12) -> [String] {
        let target = url.standardizedFileURL.path
        guard let print = featurePrint(target) else { return [] }
        var distances: [(String, Float)] = []
        for path in Set(urls.map { $0.standardizedFileURL.path }) where path != target {
            guard let other = featurePrint(path) else { continue }
            var distance: Float = 0
            guard (try? print.computeDistance(&distance, to: other)) != nil else { continue }
            distances.append((path, distance))
        }
        distances.sort { $0.1 < $1.1 }
        guard let nearest = distances.first?.1 else { return [] }
        return distances.prefix(limit).filter { $0.1 <= max(nearest * 1.8, nearest + 0.15) }.map(\.0)
    }

    // MARK: Reading

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            await self?.loadTask?.value
            while let self, !self.waiting.isEmpty {
                let next = self.waiting.removeFirst()
                defer { self.waitingCount = self.waiting.count }
                let url = next.url, stamp = next.stamp
                let record = await Task.detached(priority: .utility) { [url, stamp] in
                    Self.read(url, stamp: stamp)
                }.value
                self.queued.remove(url.path)
                guard let record else { continue }
                self.records[url.path] = record
                self.folded[url.path] = nil
                self.prints[url.path] = nil
                self.scheduleSave()
            }
            self?.worker = nil
        }
    }

    /// Reads one file. Nil only when it can't be opened right now (so it's tried again later).
    nonisolated static func read(_ url: URL, stamp: Date) -> FolioRecord? {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey]) else { return nil }
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let bytes = values.fileSize ?? 0
        var text = "", tags: [String] = [], print: Data?
        autoreleasepool {
            if type.conforms(to: .image), bytes < 200_000_000 {
                (text, tags, print) = readPicture(url)
            } else if type.conforms(to: .pdf) {
                text = readPDF(url)
            } else if url.pathExtension.lowercased() == "webloc" {
                let plist = (try? Data(contentsOf: url)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                text = plist?["URL"] as? String ?? ""
            } else if type.conforms(to: .text), bytes < 5_000_000,
                      let handle = try? FileHandle(forReadingFrom: url) {
                let data = (try? handle.read(upToCount: 64_000)) ?? Data()
                try? handle.close()
                text = String(decoding: data, as: UTF8.self)
            }
        }
        return FolioRecord(text: kept(text), tags: tags, print: print, stamp: stamp, version: version)
    }

    /// Drops lines that look like credentials (the clipboard's own rule) and caps the length.
    nonisolated static func kept(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).filter { !ClipboardSecrets.looksSecret($0) }
        return String(lines.joined(separator: "\n").prefix(textLimit))
    }

    /// The text in a picture, what it shows and its feature print, read from a thumbnail (never
    /// the full image).
    nonisolated private static func readPicture(_ url: URL) -> (String, [String], Data?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2048,
              ] as CFDictionary) else { return ("", [], nil) }
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        let classify = VNClassifyImageRequest()
        let print = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: image).perform([text, classify, print])
        let words = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        let tags = (classify.results ?? [])
            .filter { $0.hasMinimumRecall(0.01, forPrecision: 0.9) }
            .prefix(6)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        let archived = print.results?.first.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        return (words, Array(tags), archived)
    }

    /// A PDF's own text, or for a scan, the text read from its first pages.
    nonisolated private static func readPDF(_ url: URL) -> String {
        guard let document = PDFDocument(url: url), !document.isLocked else { return "" }
        var pages: [String] = [], length = 0
        for index in 0..<min(document.pageCount, 60) where length < textLimit {
            if let text = document.page(at: index)?.string { pages.append(text); length += text.count }
        }
        let text = pages.joined(separator: "\n")
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        var scanned: [String] = []
        for index in 0..<min(document.pageCount, 3) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let scale = min(3, 2048 / max(bounds.width, bounds.height))
            guard let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: image).perform([request])
            scanned.append((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
        }
        return scanned.joined(separator: "\n")
    }

    // MARK: Saving

    private struct Saved: Codable { var version: Int; var records: [String: FolioRecord] }

    private func load() async {
        let file = self.file, marksFile = self.marksFile
        let (saved, savedMarks) = await withCheckedContinuation { (continuation: CheckedContinuation<([String: FolioRecord], [String: FolioMark]), Never>) in
            ShelfDisk.queue.async {
                // Records for files that are gone are dropped as the index loads.
                let records = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }?.records ?? [:]
                let marks = (try? Data(contentsOf: marksFile)).flatMap { try? JSONDecoder().decode([String: FolioMark].self, from: $0) } ?? [:]
                continuation.resume(returning: (records.filter { FileManager.default.fileExists(atPath: $0.key) }, Self.located(marks)))
            }
        }
        // Anything read or marked while the index loaded wins.
        records = saved.merging(records) { _, new in new }
        marks = FolioMarkBook(savedMarks.merging(marks.marks) { _, new in new })
        folded = [:]
        loaded = true
    }

    /// Marks whose file moved while MacSpaces wasn't running follow it through their bookmark
    /// (never mounting a volume); marks for files that are gone are dropped. On the disk queue.
    nonisolated private static func located(_ marks: [String: FolioMark]) -> [String: FolioMark] {
        var book = FolioMarkBook(marks)
        for (path, mark) in marks where !FileManager.default.fileExists(atPath: path) {
            if let bookmark = mark.bookmark, let url = TrayFiles.resolve(bookmark)?.standardizedFileURL,
               FileManager.default.fileExists(atPath: url.path), !TrayFiles.isInTrash(url) {
                book.moved(from: path, to: url.path)
            } else {
                book.forget(path)
            }
        }
        return book.marks
    }

    private func scheduleMarksSave() {
        guard loaded else { return }
        marksSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveMarks() }
        marksSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Writes the marks on the disk queue, first making a bookmark for any marked file without
    /// one, so its mark can find the file if it moves while MacSpaces isn't running.
    private func saveMarks() {
        guard !savesDisabled else { return }
        let marks = self.marks.marks, file = marksFile
        ShelfDisk.queue.async {
            var saved = marks
            var made: [String: Data] = [:]
            for (path, mark) in marks where mark.bookmark == nil {
                guard let bookmark = TrayFiles.bookmark(for: URL(fileURLWithPath: path)) else { continue }
                saved[path]?.bookmark = bookmark
                made[path] = bookmark
            }
            if let data = try? JSONEncoder().encode(saved) {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            guard !made.isEmpty else { return }
            Task { @MainActor [weak self, made] in
                guard let self else { return }
                var book = self.marks
                for (path, bookmark) in made { book.setBookmark(bookmark, for: path) }
                if book != self.marks { self.marks = book }
            }
        }
    }

    /// Check renders: no marks, and none saved.
    private var savesDisabled = false
#if DEBUG
    func setPreviewMarks(_ marks: [String: FolioMark]) {
        savesDisabled = true
        self.marks = FolioMarkBook(marks)
        folded = [:]
    }
#endif

    private func scheduleSave() {
        guard loaded else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func save() {
        let saved = Saved(version: Self.version, records: records), file = self.file
        ShelfDisk.queue.async {
            guard let data = try? JSONEncoder().encode(saved) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// The Tray, every basket and every watched folder as one library: which lists hold a file.
@MainActor
enum FolioLibrary {
    /// Every list that's loaded: the Tray first, then the baskets in order, then watched folders,
    /// then Folio's Trash (so what Folio knows of a file waits with its reference).
    static var stores: [ShelfStore] {
        [ShelfStore.shared] + BasketWindowController.shared.loadedStores + FolioWatchedFolders.shared.loadedStores + [FolioTrash.shared.store]
    }

    static func holds(_ path: String) -> Bool {
        stores.contains { $0.items.contains { $0.url.standardizedFileURL.path == path } }
    }
}
