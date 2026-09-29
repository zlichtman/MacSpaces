import AppKit

/// Capture is separately testable against an isolated pasteboard, never the user's clipboard.
enum ClipboardCapture {
    static let sensitiveTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType")
    ]
    static func entry(from pasteboard: NSPasteboard, sourceName: String = "", sourceBundleID: String = "") -> ClipboardEntry? {
        guard pasteboard.availableType(from: sensitiveTypes) == nil else { return nil }
        let allowed: [NSPasteboard.PasteboardType] = [.string, .rtf, .html, .png, .tiff, .URL, .fileURL, .color]
        var items: [[String: Data]] = []
        var bytes = 0
        for item in (pasteboard.pasteboardItems ?? []).prefix(32) {
            guard item.availableType(from: sensitiveTypes) == nil else { return nil }
            var values: [String: Data] = [:]
            for type in allowed {
                if let data = item.data(forType: type) {
                    bytes += data.count
                    guard bytes <= 8 * 1024 * 1024 else { return nil }
                    values[type.rawValue] = data
                }
            }
            if !values.isEmpty { items.append(values) }
        }
        guard !items.isEmpty else { return nil }
        let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
            ?? pasteboard.string(forType: .fileURL) ?? (pasteboard.availableType(from: [.png, .tiff]) != nil ? "Image" : "Rich text")
        var entry = ClipboardEntry(text: text)
        entry.representations = items
        entry.sourceName = sourceName
        entry.sourceBundleID = sourceBundleID
        return entry
    }
}
