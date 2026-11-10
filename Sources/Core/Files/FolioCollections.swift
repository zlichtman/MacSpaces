import Foundation

// Pure pieces of the Folio page's views, boards, Trash, colours and links, so the check
// scripts run them as they are.

// MARK: Views

/// How the Folio page shows a place's files. Saved as `folio.view`; unset is Rows.
enum FolioViewMode: String, CaseIterable, Sendable {
    case rows, columns, list, infinity, board

    var title: String {
        switch self {
        case .rows: return "Rows"
        case .columns: return "Columns"
        case .list: return "List"
        case .infinity: return "Infinity"
        case .board: return "Board"
        }
    }

    var symbol: String {
        switch self {
        case .rows: return "rectangle.grid.1x2"
        case .columns: return "rectangle.split.3x1"
        case .list: return "list.bullet"
        case .infinity: return "infinity"
        case .board: return "rectangle.on.rectangle.angled"
        }
    }

    /// ⌘1 to ⌘5, in this order.
    var key: Character { Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)) }

    var detail: String {
        switch self {
        case .rows: return "Justified rows, every picture whole"
        case .columns: return "Columns, each picture at its own height"
        case .list: return "Names, kinds, sizes and dates"
        case .infinity: return "An endless wall of pictures to wander"
        case .board: return "Lay this place out by hand"
        }
    }

    /// The saved value, or Rows when it's unset or unknown.
    static func saved(_ raw: String?) -> FolioViewMode { raw.flatMap(FolioViewMode.init(rawValue:)) ?? .rows }
}

/// Which laid-out tiles meet a rectangle, so a view draws only what's in sight.
enum FolioVisible {
    static func indices(_ frames: [CGRect], in rect: CGRect) -> [Int] {
        frames.indices.filter { frames[$0].intersects(rect) }
    }
}

/// Columns (masonry): equal columns, each tile at its own shape (clamped so none is a sliver),
/// each going to the shortest column.
enum FolioColumns {
    static func layout(aspects: [CGFloat], width: CGFloat, column target: CGFloat, gap: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let usable = max(1, width)
        let count = max(2, Int((usable + gap) / (target + gap)))
        let cell = max(1, (usable - CGFloat(count - 1) * gap) / CGFloat(count))
        var ends = [CGFloat](repeating: 0, count: count)
        var frames: [CGRect] = []
        frames.reserveCapacity(aspects.count)
        for raw in aspects {
            let aspect = raw.isFinite && raw > 0 ? raw : 1
            let height = cell * max(0.55, min(1.65, 1 / aspect))
            var column = 0
            for index in ends.indices where ends[index] < ends[column] { column = index }
            frames.append(CGRect(x: CGFloat(column) * (cell + gap), y: ends[column], width: cell, height: height))
            ends[column] += height + gap
        }
        return (frames, max(0, (ends.max() ?? 0) - gap))
    }
}

/// Infinity: every picture in one long strip that repeats down each column, and up to seven
/// columns that repeat across, each column (and each copy of it) starting at its own height, so
/// the wall never ends, never shows a gap, and the same picture rarely sits near itself.
/// `placed(in:)` finds only the pieces in a rectangle (a binary search down each column).
struct FolioWall {
    struct Piece: Identifiable, Equatable { let id: String; let index: Int; let frame: CGRect }

    let cell: CGFloat
    let gap: CGFloat
    /// Each picture's top in the strip, and its height.
    private(set) var tops: [CGFloat] = []
    private(set) var heights: [CGFloat] = []
    /// The strip's length, gaps included.
    private(set) var period: CGFloat = 0
    private(set) var columns = 0

    init(aspects: [CGFloat], cell: CGFloat, gap: CGFloat) {
        self.cell = cell; self.gap = gap
        guard !aspects.isEmpty else { return }
        for raw in aspects {
            let aspect = raw.isFinite && raw > 0 ? raw : 1
            let height = max(cell * 0.55, min(cell * 1.65, cell / aspect))
            tops.append(period); heights.append(height)
            period += height + gap
        }
        columns = min(aspects.count, 7)
    }

    var blockWidth: CGFloat { CGFloat(max(1, columns)) * (cell + gap) }

    /// Where a copy of a column starts down the strip (a golden-ratio step of its length).
    private func shift(_ block: Int, _ column: Int) -> CGFloat {
        let turns = Double(block * columns + column) * 0.618
        return CGFloat(turns - turns.rounded(.down)) * period
    }

    func placed(in view: CGRect) -> [Piece] {
        guard columns > 0, period > 0, view.width > 0, view.height > 0 else { return [] }
        var out: [Piece] = []
        let first = Int((view.minX / blockWidth).rounded(.down)), last = Int((view.maxX / blockWidth).rounded(.down))
        for block in first...last {
            for column in 0..<columns {
                let x = CGFloat(block) * blockWidth + CGFloat(column) * (cell + gap)
                guard x + cell >= view.minX, x <= view.maxX else { continue }
                let offset = shift(block, column)
                let top = Int(((view.minY - offset) / period).rounded(.down))
                let bottom = Int(((view.maxY - offset) / period).rounded(.down))
                for lap in top...bottom {
                    let origin = CGFloat(lap) * period + offset
                    var index = firstEnding(after: view.minY - origin)
                    while index < tops.count, origin + tops[index] <= view.maxY {
                        let frame = CGRect(x: x, y: origin + tops[index], width: cell, height: heights[index])
                        out.append(Piece(id: "\(index)|\(block)|\(column)|\(lap)", index: index, frame: frame))
                        index += 1
                    }
                }
            }
        }
        return out
    }

    /// The first picture in the strip whose bottom is below `y`.
    private func firstEnding(after y: CGFloat) -> Int {
        var low = 0, high = tops.count
        while low < high {
            let middle = (low + high) / 2
            if tops[middle] + heights[middle] < y { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

// MARK: Boards

/// Where a file sits on a place's board: its top-left corner, its width (its height follows its
/// shape) and its stacking order.
struct FolioBoardSpot: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var z: Double

    func frame(aspect: CGFloat) -> CGRect {
        let shape = aspect.isFinite && aspect > 0 ? max(0.4, min(3, aspect)) : 1
        return CGRect(x: x, y: y, width: width, height: width / Double(shape))
    }
}

/// Laying a board out: files with a spot keep it; the rest go in rows below them (all of them,
/// after Tidy Up, which forgets every spot).
enum FolioBoardLayout {
    static let margin: Double = 10
    static let gap: Double = 10
    static let rowHeight: Double = 82
    static let smallest: Double = 36
    static let largest: Double = 900

    /// Every file's spot, in `paths` order: stored ones as they are, new ones in rows below.
    static func complete(_ stored: [String: FolioBoardSpot], paths: [String], aspects: [CGFloat], width: Double) -> [FolioBoardSpot] {
        var bottom = margin - gap * 2
        var z = 0.0
        for (index, path) in paths.enumerated() {
            guard let spot = stored[path] else { continue }
            let aspect = aspects.indices.contains(index) ? aspects[index] : 1
            bottom = max(bottom, Double(spot.frame(aspect: aspect).maxY))
            z = max(z, spot.z)
        }
        var y = bottom + gap * 2, x = margin
        let row = max(rowHeight + margin * 2, width)
        var out: [FolioBoardSpot] = []
        out.reserveCapacity(paths.count)
        for (index, path) in paths.enumerated() {
            if let spot = stored[path] { out.append(spot); continue }
            let raw = aspects.indices.contains(index) ? aspects[index] : 1
            let aspect = Double(raw.isFinite && raw > 0 ? max(0.4, min(3, raw)) : 1)
            let width = rowHeight * aspect
            if x > margin, x + width > row - margin { x = margin; y += rowHeight + gap }
            z += 1
            out.append(FolioBoardSpot(x: x, y: y, width: width, z: z))
            x += width + gap
        }
        return out
    }

    /// The spot moved by a drag, kept on the board (never above or left of its edge).
    static func moved(_ spot: FolioBoardSpot, by delta: CGSize) -> FolioBoardSpot {
        var moved = spot
        moved.x = max(0, spot.x + Double(delta.width))
        moved.y = max(0, spot.y + Double(delta.height))
        return moved
    }

    /// The spot resized from its bottom-right corner, keeping its shape.
    static func resized(_ spot: FolioBoardSpot, by delta: CGSize, aspect: CGFloat) -> FolioBoardSpot {
        let shape = Double(aspect.isFinite && aspect > 0 ? max(0.4, min(3, aspect)) : 1)
        // The larger of the two pulls, measured as a width.
        let grow = max(Double(delta.width), Double(delta.height) * shape)
        var resized = spot
        resized.width = max(smallest, min(largest, spot.width + grow))
        return resized
    }

    /// The order that puts one file above every other.
    static func front(_ spots: [FolioBoardSpot]) -> Double { (spots.map(\.z).max() ?? 0) + 1 }

    /// The board's extent: every spot, plus a margin to drag into.
    static func extent(_ frames: [CGRect], atLeast size: CGSize) -> CGSize {
        let right = frames.map(\.maxX).max() ?? 0, bottom = frames.map(\.maxY).max() ?? 0
        return CGSize(width: max(size.width, right + 120), height: max(size.height, bottom + 80))
    }
}

// MARK: Trash

/// Where a removed reference came from and when, by path, so Put Back returns it and it's let
/// go after `days`. Only references: nothing here ever touches a file.
struct FolioTrashBook: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// "tray", "basket:<id>" or "watched:<id>".
        var from: String
        var removed: Date
    }

    static let days: Double = 30
    private(set) var entries: [String: Entry] = [:]

    init(_ entries: [String: Entry] = [:]) { self.entries = entries }

    mutating func record(_ paths: [String], from: String, now: Date) {
        for path in paths { entries[path] = Entry(from: from, removed: now) }
    }

    func origin(_ path: String) -> String { entries[path]?.from ?? "tray" }

    /// Paths in the Trash longer than `days`; one with no record counts from `now`.
    func expired(_ paths: [String], now: Date, days: Double = FolioTrashBook.days) -> [String] {
        paths.filter { path in
            guard let entry = entries[path] else { return false }
            return now.timeIntervalSince(entry.removed) >= days * 86_400
        }
    }

    /// Days left before a reference is let go (at least 0).
    func daysLeft(_ path: String, now: Date, days: Double = FolioTrashBook.days) -> Int {
        guard let entry = entries[path] else { return Int(days) }
        return max(0, Int((days - now.timeIntervalSince(entry.removed) / 86_400).rounded(.up)))
    }

    /// Paths the Trash no longer holds lose their record; ones it holds without one get `now`.
    mutating func keep(only paths: Set<String>, now: Date) {
        entries = entries.filter { paths.contains($0.key) }
        for path in paths where entries[path] == nil { entries[path] = Entry(from: "tray", removed: now) }
    }

    mutating func forget(_ paths: [String]) { paths.forEach { entries[$0] = nil } }

    mutating func moved(from old: String, to new: String) {
        guard old != new, let entry = entries.removeValue(forKey: old) else { return }
        entries[new] = entry
    }
}

// MARK: Colours

/// Hex colours: parsing pasted palettes, and the numbers behind a swatch.
enum FolioHex {
    /// "#RRGGBB" from "#rgb", "#rrggbb" or a bare "rrggbb".
    static func normalized(_ token: String) -> String? {
        var text = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let hashed = text.hasPrefix("#")
        if hashed { text.removeFirst() }
        guard text.allSatisfy(\.isHexDigit) else { return nil }
        if hashed, text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6 else { return nil }
        return "#" + text.uppercased()
    }

    /// The colours in pasted text, in order and once each, when the text is nothing but hex
    /// codes (one, or a palette separated by spaces, commas, semicolons, bars, dashes or lines).
    /// Anything else (a sentence mentioning #333) is not a palette.
    static func palette(in text: String, limit: Int = 64) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|-\"'()[]"))
        let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !tokens.isEmpty, tokens.count <= limit else { return [] }
        var seen = Set<String>(), out: [String] = []
        for token in tokens {
            // A bare code needs a digit or capitals, so a word like "decade" stays a word.
            if !token.hasPrefix("#"), !token.contains(where: \.isNumber), token != token.uppercased() { return [] }
            guard let hex = normalized(token) else { return [] }
            if seen.insert(hex).inserted { out.append(hex) }
        }
        return out
    }

    static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard let value = normalized(hex), let number = UInt32(value.dropFirst(), radix: 16) else { return nil }
        return (Double(number >> 16 & 255) / 255, Double(number >> 8 & 255) / 255, Double(number & 255) / 255)
    }

    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ value: Double) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// "rgb(46, 94, 78)".
    static func rgbText(_ hex: String) -> String {
        guard let rgb = rgb(hex) else { return hex }
        return "rgb(\(Int((rgb.red * 255).rounded())), \(Int((rgb.green * 255).rounded())), \(Int((rgb.blue * 255).rounded())))"
    }

    /// A plain colour name for search ("blue", "gray").
    static func name(_ hex: String) -> String {
        guard let (r, g, b) = rgb(hex) else { return "" }
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        let saturation = high == 0 ? 0 : delta / high
        if high < 0.18 { return "black" }
        if saturation < 0.12 { return high > 0.87 ? "white" : "gray" }
        var hue = high == r ? (g - b) / delta : high == g ? 2 + (b - r) / delta : 4 + (r - g) / delta
        hue *= 60
        if hue < 0 { hue += 360 }
        if hue < 15 || hue >= 345 { return "red" }
        if hue < 45 { return high < 0.6 ? "brown" : "orange" }
        if hue < 70 { return "yellow" }
        if hue < 160 { return "green" }
        if hue < 195 { return "teal" }
        if hue < 255 { return "blue" }
        if hue < 290 { return "purple" }
        return "pink"
    }

    /// Whether dark text reads better than white on this colour.
    static func isLight(_ hex: String) -> Bool {
        guard let (r, g, b) = rgb(hex) else { return false }
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6
    }
}

/// A picture's dominant colours from its pixels (RGBA, 8 bits each): pixels gathered into
/// 3-bit-per-channel boxes, the fullest boxes first, each box's average colour, skipping one
/// too close to a colour already chosen. Transparent pixels don't count.
enum FolioPalette {
    static func dominant(rgba: [UInt8], count: Int = 5, distance: Double = 48) -> [String] {
        var counts = [Int](repeating: 0, count: 512)
        var sums = [Int](repeating: 0, count: 512 * 3)
        var offset = 0
        while offset + 3 < rgba.count {
            defer { offset += 4 }
            guard rgba[offset + 3] >= 128 else { continue }
            let r = Int(rgba[offset]), g = Int(rgba[offset + 1]), b = Int(rgba[offset + 2])
            let box = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            counts[box] += 1
            sums[box * 3] += r; sums[box * 3 + 1] += g; sums[box * 3 + 2] += b
        }
        let total = counts.reduce(0, +)
        guard total > 0 else { return [] }
        var chosen: [(r: Double, g: Double, b: Double)] = []
        for box in counts.indices.filter({ counts[$0] > 0 }).sorted(by: { counts[$0] > counts[$1] }) {
            // A box holding a sliver of the picture isn't one of its colours.
            if Double(counts[box]) / Double(total) < 0.005, !chosen.isEmpty { break }
            let n = Double(counts[box])
            let colour = (r: Double(sums[box * 3]) / n, g: Double(sums[box * 3 + 1]) / n, b: Double(sums[box * 3 + 2]) / n)
            let far = chosen.allSatisfy { other in
                let dr = other.r - colour.r, dg = other.g - colour.g, db = other.b - colour.b
                return (2 * dr * dr + 4 * dg * dg + 3 * db * db).squareRoot() / 3 >= distance
            }
            if far { chosen.append(colour) }
            if chosen.count == count { break }
        }
        return chosen.map { FolioHex.hex(red: $0.r / 255, green: $0.g / 255, blue: $0.b / 255) }
    }
}

/// A colour saved on the Folio page, from a paste, the colour picker or a picture.
struct FolioSwatch: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// "#RRGGBB".
    var hex: String
    /// Where it came from: "Pasted", "Colour picker" or a picture's name.
    var source: String
    var added: Date
}

/// Every swatch, newest first, one of each colour: saving a colour that's there already brings
/// it to the front.
struct FolioSwatchBook: Codable, Equatable, Sendable {
    private(set) var swatches: [FolioSwatch] = []

    init(_ swatches: [FolioSwatch] = []) {
        var seen = Set<String>()
        self.swatches = swatches.filter { FolioHex.normalized($0.hex) != nil && seen.insert($0.hex).inserted }
    }

    /// Saves these colours at the front, in their order. Returns how many there are now of them.
    @discardableResult
    mutating func add(_ hexes: [String], source: String, now: Date) -> Int {
        var fresh: [FolioSwatch] = []
        for raw in hexes {
            guard let hex = FolioHex.normalized(raw), !fresh.contains(where: { $0.hex == hex }) else { continue }
            if let index = swatches.firstIndex(where: { $0.hex == hex }) {
                fresh.append(swatches.remove(at: index))
            } else {
                fresh.append(FolioSwatch(id: UUID(), hex: hex, source: source, added: now))
            }
        }
        swatches.insert(contentsOf: fresh, at: 0)
        return fresh.count
    }

    /// Removes these and returns them with their places, for Undo.
    mutating func remove(_ ids: Set<UUID>) -> [(index: Int, item: FolioSwatch)] {
        let removed = swatches.enumerated().filter { ids.contains($0.element.id) }.map { (index: $0.offset, item: $0.element) }
        swatches.removeAll { ids.contains($0.id) }
        return removed
    }

    mutating func restore(_ removed: [(index: Int, item: FolioSwatch)]) {
        swatches = TrayFiles.restoring(removed, into: swatches) { $0.id == $1.id || $0.hex == $1.hex }
    }

    /// The words search reads: the hex, its colour's name and where it came from.
    static func searchText(_ swatch: FolioSwatch) -> String {
        [swatch.hex, String(swatch.hex.dropFirst()), FolioHex.name(swatch.hex), swatch.source].joined(separator: " ")
    }

    func matching(_ terms: [String]) -> [FolioSwatch] {
        guard !terms.isEmpty else { return swatches }
        return swatches.filter { FolioText.matches(terms, in: FolioText.fold(Self.searchText($0))) }
    }
}

// MARK: Links

/// A web address saved on the Folio page, with what its page says about itself.
struct FolioLink: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var address: String
    var title: String
    /// The preview picture's file name in the link previews folder, once fetched.
    var preview: String?
    var added: Date
    /// The page has been read (or tried); it's never fetched again.
    var fetched: Bool

    var url: URL? { URL(string: address) }
    var host: String { FolioWeb.host(address) }
}

/// Every saved link, newest first, one per address.
struct FolioLinkBook: Codable, Equatable, Sendable {
    private(set) var links: [FolioLink] = []

    init(_ links: [FolioLink] = []) {
        var seen = Set<String>()
        self.links = links.filter { seen.insert($0.address).inserted }
    }

    /// Saves these addresses at the front; one saved already moves there. Returns the links
    /// that are new (the only ones to fetch).
    @discardableResult
    mutating func add(_ urls: [URL], now: Date) -> [FolioLink] {
        var front: [FolioLink] = [], fresh: [FolioLink] = []
        for url in urls {
            let address = url.absoluteString
            guard FolioWeb.isWeb(url), !front.contains(where: { $0.address == address }) else { continue }
            if let index = links.firstIndex(where: { $0.address == address }) {
                front.append(links.remove(at: index))
            } else {
                let link = FolioLink(id: UUID(), address: address, title: "", preview: nil, added: now, fetched: false)
                front.append(link); fresh.append(link)
            }
        }
        links.insert(contentsOf: front, at: 0)
        return fresh
    }

    mutating func fill(_ id: UUID, title: String, preview: String?) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        if !title.isEmpty { links[index].title = title }
        if let preview { links[index].preview = preview }
        links[index].fetched = true
    }

    mutating func remove(_ ids: Set<UUID>) -> [(index: Int, item: FolioLink)] {
        let removed = links.enumerated().filter { ids.contains($0.element.id) }.map { (index: $0.offset, item: $0.element) }
        links.removeAll { ids.contains($0.id) }
        return removed
    }

    mutating func restore(_ removed: [(index: Int, item: FolioLink)]) {
        links = TrayFiles.restoring(removed, into: links) { $0.id == $1.id || $0.address == $1.address }
    }

    func matching(_ terms: [String]) -> [FolioLink] {
        guard !terms.isEmpty else { return links }
        return links.filter { FolioText.matches(terms, in: FolioText.fold($0.title + " " + $0.host + " " + $0.address)) }
    }
}

/// Web addresses and what a page's head says about it.
enum FolioWeb {
    static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return url.host?.contains(".") == true || url.host == "localhost"
    }

    /// The web addresses in pasted text when it's nothing but addresses (one, or several on
    /// lines or separated by spaces); http and https only.
    static func addresses(in text: String, limit: Int = 50) -> [URL] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= limit else { return [] }
        var seen = Set<String>(), out: [URL] = []
        for word in words {
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()[],"))
            guard let url = URL(string: trimmed), isWeb(url) else { return [] }
            if seen.insert(url.absoluteString).inserted { out.append(url) }
        }
        return out
    }

    /// "example.com" from "https://www.example.com/a".
    static func host(_ address: String) -> String {
        guard let host = URL(string: address)?.host?.lowercased() else { return address }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// A page's title and preview picture, from its head: Open Graph and Twitter tags first, then
    /// `<title>`. A preview that isn't http or https is ignored.
    static func page(html: String, base: URL) -> (title: String, image: URL?) {
        let head: String
        if let end = html.range(of: "</head>", options: .caseInsensitive) { head = String(html[..<end.lowerBound]) }
        else { head = String(html.prefix(300_000)) }
        var meta: [String: String] = [:]
        for tag in matches(#"<meta\s[^>]*>"#, head) {
            let key = (attribute("property", tag) ?? attribute("name", tag))?.lowercased()
            if let key, let content = attribute("content", tag), meta[key] == nil { meta[key] = decode(content) }
        }
        let titleTag = matches(#"<title[^>]*>([\s\S]*?)</title>"#, head, group: 1).first.map(decode)
        let title = clean(meta["og:title"] ?? meta["twitter:title"] ?? titleTag ?? "")
        var image: URL?
        if let raw = meta["og:image:secure_url"] ?? meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"] ?? meta["twitter:image:src"],
           let url = URL(string: raw.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL, isWeb(url) {
            image = url
        }
        return (String(title.prefix(300)), image)
    }

    private static func matches(_ pattern: String, _ text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    private static func attribute(_ name: String, _ tag: String) -> String? {
        let pattern = "\\b" + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 { if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) } }
        return nil
    }

    private static func clean(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    static func decode(_ text: String) -> String {
        var out = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&nbsp;", " "), ("&#8217;", "\u{2019}"), ("&#8211;", "\u{2013}"), ("&#8212;", "\u{2014}"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        return out
    }
}
