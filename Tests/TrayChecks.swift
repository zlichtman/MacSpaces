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
    }
}
