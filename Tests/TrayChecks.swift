import Foundation

/// Tray references on disk (`TrayFiles`): moved files are followed, deleted and
/// trashed files are gone, disconnected drives and evicted iCloud files are
/// kept; tile names, badges, staged names, undo order and the summary.
enum TrayChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func run() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MacSpaces-tray-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let present = root.appendingPathComponent("Notes.txt")
        try Data("Fixture".utf8).write(to: present)
        check(TrayFileState.inspect(present, bookmark: nil) == .present, "an existing file is present")

        let original = root.appendingPathComponent("Draft.txt")
        try Data("Fixture".utf8).write(to: original)
        let bookmark = TrayFiles.bookmark(for: original)
        check(bookmark != nil, "a bookmark is made while the file exists")
        let renamed = root.appendingPathComponent("Final.txt")
        try fm.moveItem(at: original, to: renamed)
        if case .moved(let url) = TrayFileState.inspect(original, bookmark: bookmark) {
            check(url.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path, "a renamed file is followed to its new name")
        } else { check(false, "a renamed file is followed, not dropped") }

        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        let trashed = trash.appendingPathComponent("Final.txt")
        try fm.moveItem(at: renamed, to: trashed)
        check(TrayFileState.inspect(original, bookmark: bookmark) == .gone, "a file moved to the Trash is gone, not followed")
        check(TrayFileState.inspect(trashed, bookmark: nil) == .gone, "a reference inside the Trash is gone")

        try fm.removeItem(at: present)
        check(TrayFileState.inspect(present, bookmark: nil) == .gone, "a deleted file is gone")

        let offline = URL(fileURLWithPath: "/Volumes/MacSpaces Missing " + UUID().uuidString + "/Archive.zip")
        check(TrayFileState.inspect(offline, bookmark: nil) == .offline, "a file on an unmounted volume is kept")
        check(TrayFiles.volumeRoot(of: offline)?.lastPathComponent.hasPrefix("MacSpaces Missing") == true, "volume root")
        check(TrayFiles.volumeRoot(of: URL(fileURLWithPath: "/Users/x/a.txt")) == nil, "startup-disk files have no volume root")

        let evicted = root.appendingPathComponent("Report.pdf")
        try Data().write(to: root.appendingPathComponent(".Report.pdf.icloud"))
        check(TrayFileState.inspect(evicted, bookmark: nil) == .offline, "an evicted iCloud file is kept")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_792_800_000) // 2026-10-24 UTC
        let stamp = "2026-10-24"
        check(TrayFiles.displayName("Screenshot \(stamp) at 14.03.22.png", now: now, calendar: calendar) == "Screenshot at 14.03.22", "today's screenshot drops the date")
        check(TrayFiles.displayName("Screenshot 2026-10-01 at 14.03.22.png", now: now, calendar: calendar) == "Screenshot 2026-10-01 at 14.03.22", "older screenshots keep the date")
        check(TrayFiles.displayName("Budget.csv", now: now, calendar: calendar) == "Budget", "extension hidden")
        check(TrayFiles.displayName("Makefile", now: now, calendar: calendar) == "Makefile", "no extension")
        check(TrayFiles.displayName(".env", now: now, calendar: calendar) == ".env", "dot file keeps its name")
        check(TrayFiles.displayName("v1.2 release notes", now: now, calendar: calendar) == "v1.2 release notes", "a long fake extension stays")
        check(TrayFiles.badge("Boarding pass.pdf", isDirectory: false) == "PDF", "badge")
        check(TrayFiles.badge("Photos.library", isDirectory: true) == nil && TrayFiles.badge("README", isDirectory: false) == nil, "no badge")

        check(TrayFiles.stagedName(for: .text("  Meeting notes\nsecond line"), now: now, calendar: calendar) == "Meeting notes", "text named by its first line")
        check(TrayFiles.stagedName(for: .text("a/b: c"), now: now, calendar: calendar) == "a-b- c", "no slashes or colons in names")
        check(TrayFiles.stagedName(for: .text("\n\n"), now: now, calendar: calendar).hasPrefix("Pasted Text 2026-10-24 at "), "blank text gets a dated name")
        check(TrayFiles.stagedName(for: .link(URL(string: "https://www.example.com/a")!), now: now, calendar: calendar) == "example.com", "links named by host")
        check(TrayFiles.stagedName(for: .image, now: now, calendar: calendar).hasPrefix("Pasted Image 2026-10-24 at "), "images dated")
        check(TrayFiles.displayName(TrayFiles.stagedName(for: .image, now: now, calendar: calendar) + ".png", now: now, calendar: calendar).hasPrefix("Pasted Image at "),
              "today's pasted image drops the date on its tile")

        let restored = TrayFiles.restoring([(index: 0, item: "a"), (index: 2, item: "c")], into: ["new", "b"], same: ==)
        check(restored == ["a", "new", "c", "b"], "undo puts items back at their old positions")
        check(TrayFiles.restoring([(index: 0, item: "b")], into: ["b"], same: ==) == ["b"], "undo never duplicates")
        check(TrayFiles.restoring([(index: 9, item: "z")], into: ["a"], same: ==) == ["a", "z"], "undo clamps to the end")

        check(TrayFiles.summary(count: 1, bytes: 0) == "1 item", "summary without sizes")
        check(TrayFiles.summary(count: 3, bytes: 2_400_000).hasPrefix("3 items · "), "summary with sizes")
        print("Tray reference checks passed")
        folioMarks()
        folioViews()
        folioTrash()
        folioColours()
        folioLinks()
    }

    /// The views' layouts: the saved choice, Columns, Infinity drawing only what's in view, and boards.
    static func folioViews() {
        check(FolioViewMode.saved(nil) == .rows && FolioViewMode.saved("gallery") == .rows, "an unset or unknown view is Rows")
        check(FolioViewMode.saved("board") == .board && FolioViewMode.board.key == "5" && FolioViewMode.rows.key == "1", "views keep their keys")

        let columns = FolioColumns.layout(aspects: [1, 2, 0.5, 1, 1], width: 300, column: 90, gap: 6)
        check(Set(columns.frames.map(\.width)).count == 1, "columns are one width")
        check(columns.frames.count == 5 && columns.frames.allSatisfy { $0.maxX <= 300.5 }, "columns fit the width")
        check(abs(columns.frames[1].height - columns.frames[1].width * 0.55) < 0.01, "a wide picture is clamped, not a sliver")
        check(columns.frames[3].minX == columns.frames[1].minX && columns.frames[3].minY > columns.frames[1].maxY, "the next tile goes to the shortest column")
        let frames = (0..<100).map { CGRect(x: 0, y: CGFloat($0) * 50, width: 40, height: 40) }
        check(FolioVisible.indices(frames, in: CGRect(x: 0, y: 1000, width: 100, height: 120)) == [20, 21, 22], "only tiles in view are drawn")

        let wall = FolioWall(aspects: Array(repeating: 1, count: 40), cell: 100, gap: 6)
        let near = wall.placed(in: CGRect(x: 0, y: 0, width: 400, height: 300))
        let far = wall.placed(in: CGRect(x: -90_000, y: 70_000, width: 400, height: 300))
        check(!near.isEmpty && near.count < 40 && !far.isEmpty && far.count < 40, "Infinity draws only what's in view, however far you wander")
        check(Set(near.map(\.id)).count == near.count, "every piece on the wall has its own key")
        check(near.allSatisfy { $0.frame.intersects(CGRect(x: 0, y: 0, width: 400, height: 300)) }, "every piece drawn is in view")
        check(FolioWall(aspects: [], cell: 100, gap: 6).placed(in: CGRect(x: 0, y: 0, width: 400, height: 300)).isEmpty, "an empty wall draws nothing")

        let paths = ["/a.png", "/b.png", "/c.png"]
        let fresh = FolioBoardLayout.complete([:], paths: paths, aspects: [1, 2, 1], width: 400)
        check(fresh.count == 3 && fresh[0].y == fresh[1].y && fresh[1].x > fresh[0].x, "a new board starts in rows")
        let narrow = FolioBoardLayout.complete([:], paths: paths, aspects: [1, 2, 1], width: 200)
        check(narrow[2].y > narrow[0].y, "rows wrap at the board's width")
        let pinned = FolioBoardSpot(x: 300, y: 400, width: 120, z: 7)
        let kept = FolioBoardLayout.complete(["/b.png": pinned], paths: paths, aspects: [1, 2, 1], width: 400)
        check(kept[1] == pinned, "a placed file keeps its spot")
        check(kept[0].y >= 460 + 20 && kept[0].z > 7, "new files go below and above what's placed")
        check(FolioBoardLayout.moved(pinned, by: CGSize(width: -500, height: 20)).x == 0, "a move stays on the board")
        check(FolioBoardLayout.resized(pinned, by: CGSize(width: 30, height: 0), aspect: 2).width == 150, "a resize from the corner grows the width")
        check(FolioBoardLayout.resized(pinned, by: CGSize(width: -500, height: -500), aspect: 1).width == FolioBoardLayout.smallest, "a resize has a smallest size")
        check(pinned.frame(aspect: 2).height == 60, "height follows the picture's shape")
        check(FolioBoardLayout.front(kept) > kept.map(\.z).max()!, "bring to front tops every other")
        print("Folio view checks passed")
    }

    /// The Trash: where a reference came from, and letting it go after 30 days.
    static func folioTrash() {
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        var book = FolioTrashBook()
        book.record(["/a.png", "/b.png"], from: "basket:1234", now: now.addingTimeInterval(-31 * 86_400))
        book.record(["/c.png"], from: "tray", now: now.addingTimeInterval(-2 * 86_400))
        check(book.origin("/a.png") == "basket:1234" && book.origin("/unknown.png") == "tray", "Put Back knows where each came from")
        check(Set(book.expired(["/a.png", "/b.png", "/c.png"], now: now)) == ["/a.png", "/b.png"], "references older than 30 days are let go")
        check(book.daysLeft("/c.png", now: now) == 28, "days left count down from 30")
        book.keep(only: ["/c.png", "/d.png"], now: now)
        check(book.entries.keys.sorted() == ["/c.png", "/d.png"] && book.expired(["/d.png"], now: now).isEmpty, "a reference without a record starts its 30 days now")
        book.moved(from: "/c.png", to: "/moved/c.png")
        check(book.origin("/moved/c.png") == "tray" && book.entries["/c.png"] == nil, "a record follows a moved file")
        print("Folio Trash checks passed")
    }

    /// Hex parsing, palettes, dominant colours and swatches.
    static func folioColours() {
        check(FolioHex.palette(in: "#2e5e4e") == ["#2E5E4E"], "one hex code")
        check(FolioHex.palette(in: "#264653, #2A9D8F;#e9c46a\n#F4A261 | #e76f51") == ["#264653", "#2A9D8F", "#E9C46A", "#F4A261", "#E76F51"], "a palette of several")
        check(FolioHex.palette(in: "264653-2a9d8f-e9c46a") == ["#264653", "#2A9D8F", "#E9C46A"], "a palette copied as an address")
        check(FolioHex.palette(in: "#fff #FFFFFF") == ["#FFFFFF"], "short codes expand, and each colour shows once")
        check(FolioHex.palette(in: "Use #333 for body text").isEmpty, "a sentence is not a palette")
        check(FolioHex.palette(in: "decade").isEmpty && FolioHex.palette(in: "FFFFFF") == ["#FFFFFF"], "a bare code needs a digit or capitals")
        check(FolioHex.palette(in: "#12345").isEmpty && FolioHex.palette(in: "fff").isEmpty && FolioHex.palette(in: "").isEmpty, "not hex codes")
        check(FolioHex.rgbText("#2E5E4E") == "rgb(46, 94, 78)", "a swatch's RGB")
        check(FolioHex.hex(red: 1, green: 0.5, blue: 0) == "#FF8000", "hex from components")
        check(FolioHex.name("#1E40AF") == "blue" && FolioHex.name("#F8F8F8") == "white" && FolioHex.name("#2E7D32") == "green" && FolioHex.name("#2E5E4E") == "teal", "colour names for search")

        func pixels(_ colours: [(UInt8, UInt8, UInt8, Int)]) -> [UInt8] {
            colours.flatMap { colour in (0..<colour.3).flatMap { _ in [colour.0, colour.1, colour.2, 255] } }
        }
        let picture = pixels([(250, 20, 20, 600), (252, 22, 18, 100), (20, 30, 240, 300), (240, 240, 240, 5)])
        check(FolioPalette.dominant(rgba: picture) == ["#FA1414", "#141EF0"], "the fullest colours, a near shade folded in, a speck left out")
        check(FolioPalette.dominant(rgba: [10, 10, 10, 0, 10, 10, 10, 0]).isEmpty, "transparent pixels don't count")

        var book = FolioSwatchBook()
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        book.add(["#2E7D32", "#F59AB5"], source: "Pasted", now: now)
        book.add(["#f59ab5", "#FFB077"], source: "Blossom", now: now)
        check(book.swatches.map(\.hex) == ["#F59AB5", "#FFB077", "#2E7D32"], "saving a colour again brings it to the front, once")
        check(book.matching(FolioText.terms("green")).map(\.hex) == ["#2E7D32"], "search finds a swatch by its colour's name")
        check(book.matching(FolioText.terms("blossom")).map(\.hex) == ["#FFB077"], "search finds where a swatch came from")
        let removed = book.remove([book.swatches[1].id])
        check(book.swatches.count == 2, "removing a swatch")
        book.restore(removed)
        check(book.swatches.map(\.hex) == ["#F59AB5", "#FFB077", "#2E7D32"], "Undo puts a swatch back in its place")
        print("Folio colour checks passed")
    }

    /// Pasted addresses and what a page's head says.
    static func folioLinks() {
        check(FolioWeb.addresses(in: "https://example.com/a\nhttp://harbor.example.org") .map(\.absoluteString) == ["https://example.com/a", "http://harbor.example.org"], "addresses on lines")
        check(FolioWeb.addresses(in: "see https://example.com").isEmpty, "a sentence is not a list of addresses")
        check(FolioWeb.addresses(in: "file:///etc/hosts").isEmpty && FolioWeb.addresses(in: "javascript:alert(1)").isEmpty && FolioWeb.addresses(in: "ftp://a.example.com").isEmpty, "only http and https")
        check(FolioWeb.host("https://www.example.com/a") == "example.com", "a link's host")
        let html = """
        <html><head><title>Fallback</title>
        <meta property="og:title" content="Launch notes &amp; plans">
        <meta property='og:image' content='/cover.png'>
        </head><body><meta property="og:title" content="Not this"></body></html>
        """
        let page = FolioWeb.page(html: html, base: URL(string: "https://example.com/launch")!)
        check(page.title == "Launch notes & plans", "a page's own title, Open Graph first")
        check(page.image?.absoluteString == "https://example.com/cover.png", "a relative preview resolves against the page")
        check(FolioWeb.page(html: "<title>  Two\n words </title>", base: URL(string: "https://a.example.com")!).title == "Two words", "a plain title")
        check(FolioWeb.page(html: "<meta property=\"og:image\" content=\"file:///etc/passwd\">", base: URL(string: "https://a.example.com")!).image == nil, "a preview that isn't on the web is ignored")
        var book = FolioLinkBook()
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        let first = book.add([URL(string: "https://example.com/a")!, URL(string: "https://example.com/a")!], now: now)
        check(first.count == 1 && book.links.count == 1, "one link per address")
        let again = book.add([URL(string: "https://b.example.com")!, URL(string: "https://example.com/a")!], now: now)
        check(again.map(\.address) == ["https://b.example.com"] && book.links.map(\.address) == ["https://b.example.com", "https://example.com/a"],
              "an address saved again moves to the front and isn't fetched again")
        book.fill(first[0].id, title: "Launch", preview: "x.jpg")
        check(book.links[1].fetched && book.links[1].title == "Launch", "a fetched page fills its card once")
        check(book.matching(FolioText.terms("launch")).count == 1, "search finds a link by its title")
        print("Folio link checks passed")
    }

    /// Folio's own tags, notes and likes: cleaning, search and following moves.
    static func folioMarks() {
        check(FolioTags.parse(" road  trip, Road Trip,\nbeach ,, ") == ["road trip", "beach"], "tags trim, collapse spaces and keep one spelling")
        check(FolioTags.automatic(["Beach", "sky"], without: ["beach"]) == ["sky"], "an automatic tag that's also yours shows once")
        var book = FolioMarkBook()
        book.addTags(["Road trip"], to: ["/a.png", "/b.png"])
        book.addTags(["road TRIP", "ferry"], to: ["/a.png"])
        check(book.mark("/a.png")?.tags == ["Road trip", "ferry"], "adding a tag twice keeps the first spelling")
        let terms = FolioText.terms("Road ferr")
        check(FolioText.matches(terms, in: FolioText.fold("IMG_204.png " + book.searchText("/a.png"))), "search finds your tags by word starts")
        check(!FolioText.matches(terms, in: FolioText.fold("IMG_205.png " + book.searchText("/b.png"))), "every word must match")
        check(FolioText.matches(FolioText.terms("cafe"), in: FolioText.fold("Café")), "search ignores accents and case")
        book.removeTag("ROAD TRIP", from: ["/b.png"])
        check(book.mark("/b.png") == nil, "removing the last tag drops the empty mark")
        book.moved(from: "/a.png", to: "/Trips/a.png")
        check(book.mark("/a.png") == nil && book.mark("/Trips/a.png")?.tags == ["Road trip", "ferry"], "tags follow a moved file")
        book.addTags(["sunset"], to: ["/Trips/b.png"])
        book.moved(from: "/Trips/b.png", to: "/Trips/a.png")
        check(book.mark("/Trips/a.png")?.tags == ["Road trip", "ferry", "sunset"], "a move onto a marked file joins the tags")
        book.setNote("Ferry to the island, 7:40", for: ["/Trips/a.png"])
        check(FolioText.matches(FolioText.terms("island ferry"), in: FolioText.fold(book.searchText("/Trips/a.png"))), "search finds note text")
        book.setNote("  ", for: ["/c.png"])
        check(book.mark("/c.png") == nil, "a blank note keeps no mark")
        check(book.toggleLike(["/Trips/a.png", "/d.png"]) && book.likedCount == 2, "liking several likes them all")
        book.update("/d.png") { $0.liked = false }
        check(book.toggleLike(["/Trips/a.png", "/d.png"]) && book.isLiked("/d.png"), "a mixed selection is liked, not toggled one by one")
        check(!book.toggleLike(["/Trips/a.png", "/d.png"]) && book.mark("/d.png") == nil, "unliking all of them drops the empty mark")
        book.forget("/Trips/a.png")
        check(book.marks.isEmpty, "a forgotten file keeps no mark")
        print("Folio mark checks passed")
    }
}
