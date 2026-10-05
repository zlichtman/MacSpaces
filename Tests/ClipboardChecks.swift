import AppKit

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
        print("Clipboard checks passed: rich-format round trip, source search, deduplication, bounded favorites, concealed and credential exclusion, image capture, size limits and the paste queue")
    }
}
