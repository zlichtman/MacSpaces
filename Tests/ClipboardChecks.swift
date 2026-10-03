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
        print("Clipboard checks passed: rich-format round trip, source search, deduplication, bounded favorites, concealed exclusion, image capture and size limits")
    }
}
