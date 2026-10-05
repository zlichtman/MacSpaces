import AppKit
import SQLite3

@main enum ClipboardChecks {
    static func main() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let rich = NSPasteboardItem()
        rich.setString("A rich note", forType: .string)
        rich.setData(Data("{\\rtf1 A rich note}".utf8), forType: .rtf)
        board.writeObjects([rich])
        let entry = ClipboardCapture.entry(from: board, sourceName: "Test Editor")!
        precondition(entry.representations[0][NSPasteboard.PasteboardType.rtf.rawValue] != nil)
        var history = ClipboardHistory(historyLimit: 2, favoriteLimit: 1)
        history.record(entry)
        precondition(history.matching("Test Editor").count == 1)
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: JSONEncoder().encode(entry))
        precondition(decoded == entry)
        history.record(decoded); precondition(history.entries.count == 1)
        precondition(history.toggleFavorite(entry.id))
        history.record("second"); history.record("third"); history.record("fourth")
        precondition(history.entries.count == 3 && history.entries.contains { $0.id == entry.id })
        board.clearContents()
        let secret = NSPasteboardItem(); secret.setString("secret", forType: .string)
        secret.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")); board.writeObjects([secret])
        precondition(ClipboardCapture.entry(from: board) == nil)
        board.clearContents()
        let image = NSPasteboardItem(); image.setData(Data([1,2,3,4]), forType: .png); board.writeObjects([image])
        precondition(ClipboardCapture.entry(from: board)?.text == "Image")
        let oldCount = history.entries.count
        var oversized = ClipboardEntry(text: "large")
        oversized.representations = [["public.png": Data(count: 9 * 1024 * 1024)]]
        history.record(oversized); precondition(history.entries.count == oldCount)
        history.clear(keepingFavorites: true); precondition(history.entries.count == 1)
        // Credentials are recognised by shape; ordinary text never is.
        for secret in ["ghp_" + String(repeating: "a", count: 36), "AKIAIOSFODNN7EXAMPLE",
                       "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJlLXZhbHVl", "-----BEGIN OPENSSH PRIVATE KEY-----\nabc"] {
            precondition(ClipboardSecrets.looksSecret(secret), secret)
        }
        for secret in ["4242 4242 4242 4242", "4111-1111-1111-1111", "DATABASE_URL=postgres://x\nSTRIPE_SECRET_KEY=sk_test_abc",
                       "export GITHUB_TOKEN=abc123"] {
            precondition(ClipboardSecrets.looksSecret(secret), secret)
        }
        for ordinary in ["4242 4242 4242 4241", "Call 555 0100 2030", "DEBUG=true\nPORT=3000", "x = 1", "1234567890123"] {
            precondition(!ClipboardSecrets.looksSecret(ordinary), ordinary)
        }
        for ordinary in ["https://github.com/zlichtman/MacSpaces", "brew upgrade", "sk-", "Meeting notes for Thursday at noon",
                         "AKIA is a prefix", "/Users/someone/Library/Application Support/MacSpaces"] {
            precondition(!ClipboardSecrets.looksSecret(ordinary), ordinary)
        }
        board.clearContents(); board.setString("xoxb-" + String(repeating: "1", count: 30), forType: .string)
        precondition(ClipboardCapture.entry(from: board) == nil, "A token is not recorded")
        // Paste queue: in order, newest first, deduplication and the limit.
        var queue = PasteQueue()
        for text in ["one", "two", "two", "three"] { queue.add(ClipboardEntry(text: text)) }
        precondition(queue.count == 3 && queue.next?.text == "one")
        precondition(queue.advance()?.text == "two" && queue.advance()?.text == "three" && queue.advance() == nil && queue.isEmpty)
        queue.order = .newestFirst
        for text in ["a", "b", "c"] { queue.add(ClipboardEntry(text: text)) }
        precondition(queue.next?.text == "c" && queue.advance()?.text == "b")
        queue.clear()
        for index in 0..<60 { queue.add(ClipboardEntry(text: "\(index)")) }
        precondition(queue.count == 50 && queue.items.first?.text == "10")
        // Search modes, sorting, pins and copy counts.
        var library = ClipboardHistory(historyLimit: 10)
        library.record("alpha beta", at: Date(timeIntervalSince1970: 1))
        library.record("gamma", at: Date(timeIntervalSince1970: 2))
        library.record("alpha beta", at: Date(timeIntervalSince1970: 3))
        precondition(library.entries.first?.copyCount == 2 && library.entries.first?.firstDate == Date(timeIntervalSince1970: 1))
        precondition(library.matching("abt", mode: .fuzzy, order: .lastCopied, pinsFirst: nil).map(\.text) == ["alpha beta"])
        precondition(library.matching("abt", mode: .exact, order: .lastCopied, pinsFirst: nil).isEmpty)
        precondition(library.matching("^gam+a$", mode: .regex, order: .lastCopied, pinsFirst: nil).map(\.text) == ["gamma"])
        precondition(library.matching("(", mode: .regex, order: .lastCopied, pinsFirst: nil).isEmpty, "A bad pattern matches nothing")
        precondition(library.matching("gma", mode: .mixed, order: .lastCopied, pinsFirst: nil).map(\.text) == ["gamma"])
        precondition(library.matching("alpha", mode: .mixed, order: .lastCopied, pinsFirst: nil).map(\.text) == ["alpha beta"],
                     "Mixed stops at exact matches instead of adding fuzzy ones")
        precondition(library.matching("", mode: .exact, order: .firstCopied, pinsFirst: nil).map(\.text) == ["alpha beta", "gamma"])
        precondition(library.matching("", mode: .exact, order: .mostCopied, pinsFirst: nil).first?.text == "alpha beta")
        _ = library.toggleFavorite(library.entries.first { $0.text == "gamma" }!.id)
        precondition(library.matching("", mode: .exact, order: .lastCopied, pinsFirst: true).first?.text == "gamma")
        precondition(library.matching("", mode: .exact, order: .lastCopied, pinsFirst: false).last?.text == "gamma")
        library.historyLimit = 1; library.record("delta")
        precondition(library.entries.filter { !$0.isFavorite }.map(\.text) == ["delta"], "A smaller limit trims history, keeping pins")
        // Older saved clips decode with defaults for the newer fields.
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000009","text":"old","date":0,"isFavorite":false}"#
        let old = try JSONDecoder().decode(ClipboardEntry.self, from: Data(legacy.utf8))
        precondition(old.copyCount == 1 && old.firstDate == old.date && old.representations.isEmpty)
        precondition(ClipboardEntry(text: "#3E6A34").hexColor != nil && ClipboardEntry(text: "#fff").hexColor != nil
                     && ClipboardEntry(text: "#nope").hexColor == nil)
        // @ and # filters, snippets, auto-delete, case copies and Maccy import.
        var tagged = ClipboardHistory(historyLimit: 20)
        var link = ClipboardEntry(text: "https://example.com/a", date: Date(timeIntervalSince1970: 10)); link.sourceName = "Safari"
        tagged.record(link)
        var picture = ClipboardEntry(text: "Image", date: Date(timeIntervalSince1970: 20)); picture.representations = [["public.png": Data([1])]]
        picture.recognizedText = "Boarding pass gate 22"; picture.sourceName = "Preview"
        tagged.record(picture)
        tagged.record(ClipboardEntry(text: "#3E6A34", date: Date(timeIntervalSince1970: 30)))
        let snippet = tagged.addSnippet("Thanks for reaching out!", collection: "Email")!
        precondition(snippet.isFavorite && snippet.isSnippet)
        func texts(_ q: String) -> [String] { tagged.matching(q, mode: .exact, order: .lastCopied, pinsFirst: nil).map(\.text) }
        precondition(texts("@image") == ["Image"] && texts("@link") == ["https://example.com/a"] && texts("@color") == ["#3E6A34"])
        precondition(texts("@safari") == ["https://example.com/a"] && texts("@snippet") == ["Thanks for reaching out!"])
        precondition(texts("#email") == ["Thanks for reaching out!"] && texts("gate 22") == ["Image"], "image text is searchable")
        precondition(texts("@image gate") == ["Image"] && texts("@link gate").isEmpty)
        tagged.removeUnused(olderThan: 1, now: Date(timeIntervalSince1970: 86_400 * 3))
        precondition(texts("") == ["Thanks for reaching out!"], "old clips go, snippets stay")
        precondition(ClipboardEntry(text: "hello world").text(as: .title) == "Hello World" && ClipboardEntry(text: "Hi").text(as: .upper) == "HI")
        // Maccy import, from a fixture with Maccy's schema.
        let maccy = FileManager.default.temporaryDirectory.appendingPathComponent("maccy-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: maccy) }
        var store: OpaquePointer?
        precondition(sqlite3_open(maccy.path, &store) == SQLITE_OK)
        func run(_ sql: String) { precondition(sqlite3_exec(store, sql, nil, nil, nil) == SQLITE_OK, sql) }
        run("CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZAPPLICATION TEXT, ZFIRSTCOPIEDAT REAL, ZLASTCOPIEDAT REAL, ZNUMBEROFCOPIES INTEGER, ZPIN TEXT, ZTITLE TEXT)")
        run("CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE TEXT, ZVALUE BLOB)")
        run("INSERT INTO ZHISTORYITEM VALUES (1, 'com.apple.Safari', 100, 500, 3, 'b', 'link'), (2, '', 200, 300, 1, NULL, 'token'), (3, '', 50, 60, 1, NULL, 'note')")
        run("INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', CAST('https://example.com' AS BLOB)), (2, 2, 'public.utf8-plain-text', CAST('ghp_0123456789abcdefghijklmnopqrstuvwxyz' AS BLOB)), (3, 3, 'public.utf8-plain-text', CAST('Groceries: eggs' AS BLOB)), (4, 3, 'com.example.private', X'00')")
        sqlite3_close(store)
        let imported = MaccyImport.read(maccy, filter: ClipboardFilter())
        precondition(imported.map(\.text) == ["https://example.com", "Groceries: eggs"], "credentials stay out")
        precondition(imported[0].isFavorite && imported[0].copyCount == 3 && imported[0].sourceBundleID == "com.apple.Safari")
        precondition(imported[0].date == Date(timeIntervalSinceReferenceDate: 500) && imported[1].representations.first?.count == 1)
        // Filters: kinds, ignored types, patterns and apps.
        var filter = ClipboardFilter()
        board.clearContents(); board.setString("order 1234-5678", forType: .string)
        filter.ignoredPatterns = [#"\d{4}-\d{4}"#]
        precondition(ClipboardCapture.entry(from: board, filter: filter) == nil, "A matching pattern is not recorded")
        filter.ignoredPatterns = []
        precondition(ClipboardCapture.entry(from: board, sourceBundleID: "com.example.vault", filter: ClipboardFilter(apps: ["com.example.vault"])) == nil)
        precondition(ClipboardCapture.entry(from: board, sourceBundleID: "com.example.notes", filter: ClipboardFilter(apps: ["com.example.vault"])) != nil)
        precondition(ClipboardCapture.entry(from: board, sourceBundleID: "com.example.notes",
                                            filter: ClipboardFilter(apps: ["com.example.vault"], onlyListedApps: true)) == nil)
        filter.recordsText = false
        precondition(ClipboardCapture.entry(from: board, filter: filter) == nil, "Text is skipped when text isn't recorded")
        board.clearContents()
        let typed = NSPasteboardItem(); typed.setString("snippet", forType: .string); typed.setData(Data(), forType: .init("com.typeit4me.clipping"))
        board.writeObjects([typed])
        precondition(ClipboardCapture.entry(from: board) == nil, "Default ignored types are skipped")
        print("Clipboard checks passed: rich-format round trip, source search, deduplication, bounded favorites, concealed and credential exclusion, image capture, size limits, the paste queue, search modes, sorting, pins, legacy decoding, filters, @/# search, image text, snippets, auto-delete, case copies and Maccy import")
    }
}
