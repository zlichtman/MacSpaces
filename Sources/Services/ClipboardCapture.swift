import AppKit

/// What gets recorded: kinds of content, and copies to leave out by format,
/// pattern or app. The defaults record everything except formats that other
/// clipboard and password tools mark as private.
struct ClipboardFilter: Equatable {
    var recordsText = true
    var recordsImages = true
    var recordsFiles = true
    /// Pasteboard types whose presence means "don't record this copy".
    var ignoredTypes: Set<String> = ClipboardFilter.defaultIgnoredTypes
    /// Regular expressions; text matching any of them isn't recorded.
    var ignoredPatterns: [String] = []
    /// Bundle identifiers of apps whose copies aren't recorded, or with
    /// `onlyListedApps`, the only apps whose copies are.
    var apps: Set<String> = []
    var onlyListedApps = false

    static let defaultIgnoredTypes: Set<String> = [
        "Pasteboard generator type", "com.agilebits.onepassword", "com.typeit4me.clipping",
        "de.petermaurer.TransientPasteboardType", "net.antelle.keeweb",
    ]

    func allows(app bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return !onlyListedApps }
        return onlyListedApps ? apps.contains(bundleID) : !apps.contains(bundleID)
    }

    func allows(text: String) -> Bool {
        !ignoredPatterns.contains { pattern in
            !pattern.isEmpty && (try? NSRegularExpression(pattern: pattern))?
                .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    var allowedTypes: [NSPasteboard.PasteboardType] {
        (recordsText ? [.string, .rtf, .html, .URL, .color] : [])
            + (recordsImages ? [.png, .tiff] : [])
            + (recordsFiles ? [.fileURL] : [])
    }
}

/// Capture is separately testable against an isolated pasteboard, never the user's clipboard.
enum ClipboardCapture {
    static let sensitiveTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"), .init("org.nspasteboard.TransientType")
    ]
    static func entry(from pasteboard: NSPasteboard, sourceName: String = "", sourceBundleID: String = "",
                      filter: ClipboardFilter = ClipboardFilter()) -> ClipboardEntry? {
        guard pasteboard.availableType(from: sensitiveTypes) == nil,
              filter.allows(app: sourceBundleID),
              !(pasteboard.types ?? []).contains(where: { filter.ignoredTypes.contains($0.rawValue) }) else { return nil }
        let allowed = filter.allowedTypes
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
        let has = { (type: NSPasteboard.PasteboardType) in items.contains { $0[type.rawValue] != nil } }
        let text = (filter.recordsText ? pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL) : nil)
            ?? (filter.recordsFiles ? pasteboard.string(forType: .fileURL) : nil)
            ?? (has(.png) || has(.tiff) ? "Image" : has(.rtf) || has(.html) ? "Rich text" : nil)
        guard let text else { return nil }
        // Keys and tokens copied from a terminal or a web page carry no concealed
        // marker, so they're recognised by shape and kept out of history too.
        guard !ClipboardSecrets.looksSecret(text), filter.allows(text: text), allowsContents(of: items, filter: filter) else { return nil }
        var entry = ClipboardEntry(text: text)
        entry.representations = items
        entry.sourceName = sourceName
        entry.sourceBundleID = sourceBundleID
        return entry
    }

    /// Every item is saved, so every item's text is checked: a later item, or text that exists
    /// only as rich text, is kept to the same rules as the text the entry shows.
    static func allowsContents(of items: [[String: Data]], filter: ClipboardFilter) -> Bool {
        items.allSatisfy { item in
            readableTexts(in: item).allSatisfy { !ClipboardSecrets.looksSecret($0) && filter.allows(text: $0) }
        }
    }

    /// Rich text bigger than this isn't parsed: this runs on the main thread for each copy.
    private static let richTextCheckLimit = 1024 * 1024

    static func readableTexts(in item: [String: Data]) -> [String] {
        var texts = [NSPasteboard.PasteboardType.string, .URL, .fileURL].compactMap { type in
            item[type.rawValue].flatMap { String(data: $0, encoding: .utf8) }
        }
        if let rtf = item[NSPasteboard.PasteboardType.rtf.rawValue], rtf.count <= richTextCheckLimit,
           let text = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string {
            texts.append(text)
        }
        if let html = item[NSPasteboard.PasteboardType.html.rawValue], html.count <= richTextCheckLimit,
           let markup = String(data: html, encoding: .utf8) {
            texts.append(plainText(html: markup))
        }
        return texts
    }

    /// The words in a piece of HTML. A plain strip, not a parse: AppKit's HTML reader runs WebKit
    /// and can load what the markup points at.
    private static func plainText(html: String) -> String {
        var text = html.replacingOccurrences(of: #"(?is)<(style|script)\b.*?</\1\s*>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text
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
        if isCardNumber(value) || isEnvSecrets(value) { return true }
        guard value.count >= 20, value.count <= 4096, !value.contains(where: \.isWhitespace) else { return false }
        if prefixes.contains(where: { value.hasPrefix($0) }) { return true }
        if value.count == 20, value.hasPrefix("AKIA") || value.hasPrefix("ASIA"),
           value.allSatisfy({ $0.isUppercase || $0.isNumber }) { return true }
        return value.range(of: #"^eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    /// 13–19 digits (spaces or dashes allowed) that pass the Luhn check.
    static func isCardNumber(_ value: String) -> Bool {
        guard value.count <= 23, value.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) else { return false }
        let digits = value.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { total, pair in
            let (index, digit) = pair
            guard index % 2 == 1 else { return total + digit }
            let doubled = digit * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }

    /// A `.env`-style block: lines of KEY=value where a key names a secret.
    static func isEnvSecrets(_ value: String) -> Bool {
        let lines = value.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty else { return false }
        let assignments = lines.filter { $0.range(of: #"^(export\s+)?[A-Z][A-Z0-9_]*=\S+"#, options: .regularExpression) != nil }
        guard assignments.count * 2 >= lines.count else { return false }
        let secretWords = ["SECRET", "TOKEN", "PASSWORD", "PASSWD", "API_KEY", "APIKEY", "PRIVATE_KEY", "ACCESS_KEY", "AUTH", "CREDENTIAL"]
        return assignments.contains { line in
            let key = line.replacingOccurrences(of: "export ", with: "").split(separator: "=").first.map(String.init) ?? ""
            return secretWords.contains { key.contains($0) }
        }
    }
}
