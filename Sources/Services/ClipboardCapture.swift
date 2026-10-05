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
        // Keys and tokens copied from a terminal or a web page carry no concealed
        // marker, so they're recognised by shape and kept out of history too.
        guard !ClipboardSecrets.looksSecret(text) else { return nil }
        var entry = ClipboardEntry(text: text)
        entry.representations = items
        entry.sourceName = sourceName
        entry.sourceBundleID = sourceBundleID
        return entry
    }
}

/// Recognises text that is almost certainly a credential: private keys, access
/// tokens with a published prefix, and JSON web tokens. Deliberately narrow, so
/// ordinary text is never dropped.
enum ClipboardSecrets {
    private static let prefixes = ["ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_", "glpat-", "sk-", "sk_live_", "rk_live_",
                                   "xoxb-", "xoxp-", "xoxa-", "xapp-", "npm_", "pypi-", "hf_", "dop_v1_", "AIza", "SG."]

    static func looksSecret(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("-----BEGIN"), value.contains("PRIVATE KEY") { return true }
        guard value.count >= 20, value.count <= 4096, !value.contains(where: \.isWhitespace) else { return false }
        if prefixes.contains(where: { value.hasPrefix($0) }) { return true }
        if value.count == 20, value.hasPrefix("AKIA") || value.hasPrefix("ASIA"),
           value.allSatisfy({ $0.isUppercase || $0.isNumber }) { return true }
        return value.range(of: #"^eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}
