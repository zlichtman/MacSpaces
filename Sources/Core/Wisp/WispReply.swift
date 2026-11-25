import Foundation

/// A reply from a model behind Wisp that isn't Apple's: what to say, and the plain requests
/// it asked Wisp to carry out. The model asks with lines of their own, such as
/// `DO: remind me to call the dentist tomorrow`, and Wisp runs each through `WispCommand`. Questions
/// for KemoSabe, the gateway (`KemoSabeGateway`), come the same way: `ASK: free tonight`.
struct WispReply: Equatable {
    let text: String
    let actions: [String]
    var asks: [String] = []

    static func parse(_ raw: String) -> WispReply {
        var said: [String] = [], actions: [String] = [], asks: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`*-•"))
                .trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("DO:") {
                let request = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !request.isEmpty { actions.append(request) }
            } else if trimmed.uppercased().hasPrefix("ASK:") {
                let question = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                if !question.isEmpty { asks.append(question) }
            } else if !trimmed.isEmpty {
                said.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return WispReply(text: said.joined(separator: " "), actions: actions, asks: asks)
    }
}

/// The pages a web answer drew on, lifted out of the model's words so they show as a small line
/// of their own and are never drawn in the bubble or read aloud. Claude Code ends a searched
/// answer with "Sources: [Title](https://…), …" whatever its instructions say, and any model may
/// write a link inline; the API's citations arrive as addresses (`WispCloudBrain`).
struct WispSources: Equatable {
    /// What was said, with no links and no sources tail.
    let text: String
    /// The pages, in the order named, each once: http and https only.
    let pages: [URL]

    /// An address may hold one pair of brackets, as Wikipedia's do.
    private static let address = #"https?://(?:[^\s()\]>,;]|\([^\s()]*\))+"#
    private static let link = #"\[([^\]\n]*)\]\(("# + address + #")\)"#
    /// "Sources:" and the links after it, however they're listed.
    private static let tail = try! NSRegularExpression(
        pattern: #"[*_]*\b(?:sources?|references)\b[*_]*\s*:[*_]*((?:\s|[-*•·,;]|\d+[.)]|and(?=\s*(?:\[|https?://))|"# + link + "|" + address + ")+)",
        options: [.caseInsensitive])
    private static let links = try! NSRegularExpression(pattern: link)
    private static let addresses = try! NSRegularExpression(pattern: address)

    static func lift(_ raw: String) -> WispSources {
        var text = raw
        var found: [String] = []
        // The sources tail goes whole, when it names at least one page.
        for match in tail.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let listed = Range(match.range(at: 1), in: text) else { continue }
            let named = Self.addressesNamed(in: String(text[listed]))
            guard !named.isEmpty else { continue }
            found.insert(contentsOf: named, at: 0)
            // A list marker it took from the next line goes back as a line break.
            text.replaceSubrange(whole, with: text[listed].contains("\n") && whole.upperBound != text.endIndex ? "\n" : "")
        }
        // A link in the words keeps its words; its page joins the list, ahead of the tail's.
        var inline: [String] = []
        for match in links.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let label = Range(match.range(at: 1), in: text),
                  let page = Range(match.range(at: 2), in: text) else { continue }
            inline.insert(String(text[page]), at: 0)
            text.replaceSubrange(whole, with: String(text[label]))
        }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        return WispSources(text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                           pages: unique((inline + found).compactMap(page)))
    }

    /// Every address in a sources list, linked or bare, in order.
    private static func addressesNamed(in listed: String) -> [String] {
        addresses.matches(in: listed, range: NSRange(listed.startIndex..., in: listed)).compactMap {
            Range($0.range, in: listed).map { String(listed[$0]) }
        }
    }

    /// A web page's address, or nil for anything that isn't http or https with a host.
    static func page(_ address: String) -> URL? {
        // The sentence's own punctuation isn't the address's; a closing bracket is, when it has its opener.
        var trimmed = Substring(address.trimmingCharacters(in: .whitespaces))
        while let last = trimmed.last,
              ".,;:!?]>\"'".contains(last) || (last == ")" && trimmed.filter { $0 == "(" }.count < trimmed.filter { $0 == ")" }.count) {
            trimmed.removeLast()
        }
        guard let url = URL(string: String(trimmed)), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".") else { return nil }
        return url
    }

    static func unique(_ pages: [URL]) -> [URL] {
        var seen = Set<String>()
        return pages.filter { seen.insert($0.absoluteString).inserted }
    }

    /// A page's site as it's shown: the host from the address itself, never the model's name for it.
    static func site(_ page: URL) -> String {
        let host = page.host?.lowercased() ?? page.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The sites to name on the chat's line, each once with its first page, and how many more there were.
    static func sites(_ pages: [URL], limit: Int = 3) -> (shown: [(site: String, page: URL)], more: Int) {
        var seen = Set<String>(), all: [(site: String, page: URL)] = []
        for page in pages where seen.insert(site(page)).inserted { all.append((site(page), page)) }
        return (Array(all.prefix(limit)), max(0, all.count - limit))
    }

    /// The chat's line in plain words: "Claude searched the web: nps.gov, wikipedia.org and 2 more".
    static func line(service: String, pages: [URL]) -> String {
        let (shown, more) = sites(pages)
        guard !shown.isEmpty else { return "\(service) searched the web" }
        return "\(service) searched the web: " + shown.map(\.site).joined(separator: ", ") + (more > 0 ? " and \(more) more" : "")
    }
}

extension WispSources {
    /// The answer in an API reply's content blocks: the words after the last search (what comes
    /// before is the model saying it will look), whether it searched, and the pages those words
    /// cite. No words after a search is no answer, never the words before it.
    static func answer(in blocks: [[String: Any]]) -> (text: String, searched: Bool, pages: [URL]) {
        func kind(_ block: [String: Any]) -> String { block["type"] as? String ?? "" }
        let searched = blocks.contains { kind($0) == "server_tool_use" }
        let last = blocks.lastIndex { kind($0) == "server_tool_use" || kind($0).hasSuffix("_tool_result") }
        let said = (last.map { blocks[($0 + 1)...] } ?? blocks[...]).filter { kind($0) == "text" }
        let pages = said.flatMap { $0["citations"] as? [[String: Any]] ?? [] }.compactMap { ($0["url"] as? String).flatMap(page) }
        return (said.compactMap { $0["text"] as? String }.joined(), searched, unique(pages))
    }

    /// Whether a Claude Code run searched the web: its JSON result counts the searches under each
    /// model it used, and the search itself may run on a smaller one than the model that answers.
    static func searched(claudeCode output: String) -> Bool {
        let json = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any]
        let models = json?["modelUsage"] as? [String: [String: Any]] ?? [:]
        return models.values.contains { ($0["webSearchRequests"] as? Int ?? 0) > 0 }
    }
}
