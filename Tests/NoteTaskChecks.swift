import Foundation

/// To-dos written in notes: reading the marks, ticking a line, adding one, and the day's order.
@main struct NoteTaskChecks {
    static func main() {
        let note = UUID()
        let text = """
        Kitchen
        - [ ] Call the plumber ~25m !! @14:30
        - [x] Buy tiles ~1h
          * [ ] Paint the wall ~1h30m
        - [] not a box
        - [ ]
        Plain line with ~5m and @9am
        + [X] Measure twice !
        - [ ] Email Sam @9am ~1.5h !!!
        """
        let tasks = NoteTasks.tasks(in: text, note: note)
        precondition(tasks.map(\.title) == ["Call the plumber", "Buy tiles", "Paint the wall", "Measure twice", "Email Sam"], "\(tasks.map(\.title))")
        precondition(tasks.map(\.line) == [1, 2, 3, 7, 8])
        precondition(tasks.map(\.done) == [false, true, false, true, false])
        precondition(tasks.map(\.minutes) == [25, 60, 90, nil, 90])
        precondition(tasks.map(\.priority) == [2, 0, 0, 1, 3])
        precondition(tasks.map(\.due) == [14 * 60 + 30, nil, nil, nil, 9 * 60])
        precondition(Set(tasks.map(\.id)).count == tasks.count)

        // Marks that aren't marks stay in the title.
        let odd = NoteTasks.tasks(in: "- [ ] Pay ~soon !!!! @home at 5 @25:00 ~0m", note: note)
        precondition(odd.first?.title == "Pay ~soon !!!! @home at 5 @25:00 ~0m" && odd.first?.minutes == nil && odd.first?.due == nil)
        precondition(NoteTasks.estimate("~45m") == 45 && NoteTasks.estimate("~2h") == 120 && NoteTasks.estimate("~1h30m") == 90)
        precondition(NoteTasks.estimate("45m") == nil && NoteTasks.estimate("~") == nil && NoteTasks.estimate("~30") == nil && NoteTasks.estimate("~25h") == nil)
        precondition(NoteTasks.time("@9am") == 540 && NoteTasks.time("@12am") == 0 && NoteTasks.time("@12pm") == 720 && NoteTasks.time("@2:30pm") == 870)
        precondition(NoteTasks.time("@14:30") == 870 && NoteTasks.time("@9") == nil && NoteTasks.time("@13pm") == nil && NoteTasks.time("@9:5") == nil)

        // Ticking: only that line's box changes, and only while it's still that to-do.
        let ticked = NoteTasks.toggled(text, task: tasks[0])!
        precondition(ticked.components(separatedBy: "\n")[1] == "- [x] Call the plumber ~25m !! @14:30")
        precondition(ticked.components(separatedBy: "\n").enumerated().allSatisfy { $0.offset == 1 || $0.element == text.components(separatedBy: "\n")[$0.offset] })
        precondition(NoteTasks.toggled(ticked, task: NoteTasks.tasks(in: ticked, note: note)[0]) == text, "Ticking again clears it")
        precondition(NoteTasks.toggled(text, task: tasks[2])!.components(separatedBy: "\n")[3] == "  * [x] Paint the wall ~1h30m", "Indented, with a star")
        precondition(NoteTasks.toggled("Kitchen\n- [ ] Something else", task: tasks[0]) == nil, "The note changed: nothing is ticked")
        precondition(NoteTasks.toggled(ticked, task: tasks[0]) == nil, "Already ticked elsewhere")
        precondition(NoteTasks.toggled("- [ ] A [link] here", task: NoteTasks.tasks(in: "- [ ] A [link] here", note: note)[0]) == "- [x] A [link] here")

        // A file with Windows line endings: the return isn't part of the title, and stays in the file.
        let windows = "- [ ] Send invoice ~10m\r\n- [ ] Call back\r\n"
        let crlf = NoteTasks.tasks(in: windows, note: note)
        precondition(crlf.map(\.title) == ["Send invoice", "Call back"] && crlf[0].minutes == 10)
        precondition(NoteTasks.toggled(windows, task: crlf[1]) == "- [ ] Send invoice ~10m\r\n- [x] Call back\r\n")

        // Adding.
        precondition(NoteTasks.adding("Water plants", to: "") == "- [ ] Water plants")
        precondition(NoteTasks.adding(" Water\nplants ", to: "To-Dos") == "To-Dos\n- [ ] Water plants")
        precondition(NoteTasks.adding("B", to: "- [ ] A\n") == "- [ ] A\n- [ ] B")
        // A file with Windows line endings: no blank line is left, and the new line matches it.
        precondition(NoteTasks.adding("B", to: windows) == windows + "- [ ] B")
        precondition(NoteTasks.adding("B", to: "- [ ] A\r\n- [ ] C") == "- [ ] A\r\n- [ ] C\r\n- [ ] B")

        // The day: timed first by time, then by priority, then as written; done ones left out.
        precondition(NoteTasks.plan(tasks).map(\.title) == ["Email Sam", "Call the plumber", "Paint the wall"])
        let untimed = NoteTasks.tasks(in: "- [ ] A\n- [ ] B !!\n- [ ] C !\n- [ ] D !!", note: note)
        precondition(NoteTasks.plan(untimed).map(\.title) == ["B", "D", "C", "A"])
        // Reminders: only those still to do, with a time still ahead today.
        precondition(NoteTasks.dueLater(tasks, after: 8 * 60).map(\.title) == ["Call the plumber", "Email Sam"])
        precondition(NoteTasks.dueLater(tasks, after: 9 * 60).map(\.title) == ["Call the plumber"], "A time that has just come isn't later")
        precondition(NoteTasks.dueLater(tasks, after: 15 * 60).isEmpty)
        precondition(NoteTasks.dueLater(NoteTasks.tasks(in: "- [x] Done @23:00\n- [ ] No time", note: note), after: 0).isEmpty)
        precondition(NoteTasks.minutesLeft(tasks) == 25 + 90 + 90)
        precondition(NoteTasks.duration(25) == "25 min" && NoteTasks.duration(120) == "2 h" && NoteTasks.duration(130) == "2 h 10 min")
        precondition(NoteTasks.clock(870, uses24Hour: true) == "14:30" && NoteTasks.clock(870, uses24Hour: false) == "2:30 PM")
        precondition(NoteTasks.clock(0, uses24Hour: false) == "12:00 AM" && NoteTasks.clock(540, uses24Hour: false) == "9:00 AM")
        fileChecks()
        print("Note task checks passed")
    }

    /// A linked Markdown file, in a temporary folder: only the ticked or added line changes,
    /// a line that changed underneath is left alone, and files that aren't a list aren't read.
    static func fileChecks() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macspaces-todo-" + UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Inbox.md")
        let original = "# Inbox\n\nSome thoughts, untouched.\n- [ ] Renew passport ~20m\n- [ ] Book dentist @9am\n\n```\n- [ ] not mine to touch? still a box\n```\nLast line"
        try! original.write(to: file, atomically: true, encoding: .utf8)
        let tasks = NoteTasks.tasks(in: try! TodoFile.read(file), note: TodoFile.noteID)
        precondition(tasks.map(\.title) == ["Renew passport", "Book dentist", "not mine to touch? still a box"] && tasks.allSatisfy { $0.note == TodoFile.noteID })

        // Ticking changes that line's box and nothing else.
        precondition(try! TodoFile.toggle(tasks[1], in: file))
        let ticked = try! String(contentsOf: file, encoding: .utf8)
        precondition(ticked == original.replacingOccurrences(of: "- [ ] Book dentist", with: "- [x] Book dentist"), ticked)

        // The file changed underneath (a line added above): the stale to-do isn't ticked, nothing is written.
        try! ("New first line\n" + ticked).write(to: file, atomically: true, encoding: .utf8)
        precondition(try! TodoFile.toggle(tasks[0], in: file) == false)
        precondition(try! String(contentsOf: file, encoding: .utf8) == "New first line\n" + ticked)

        // Adding goes on a new last line; the rest is as it was.
        try! TodoFile.append("Buy stamps !", to: file)
        precondition(try! String(contentsOf: file, encoding: .utf8) == "New first line\n" + ticked + "\n- [ ] Buy stamps !")

        // Not plain text, too large, or gone: an error, and never a write.
        let binary = folder.appendingPathComponent("picture.md")
        try! Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: binary)
        precondition((try? TodoFile.read(binary)) == nil && (try? TodoFile.append("x", to: binary)) == nil)
        precondition(try! Data(contentsOf: binary) == Data([0xFF, 0xFE, 0x00, 0xD8]), "A file that isn't text is left as it was")
        let large = folder.appendingPathComponent("large.md")
        try! String(repeating: "- [ ] again\n", count: 200_000).write(to: large, atomically: true, encoding: .utf8)
        precondition((try? TodoFile.read(large)) == nil)
        precondition((try? TodoFile.toggle(tasks[0], in: folder.appendingPathComponent("missing.md"))) == nil)
        precondition(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("missing.md").path), "A missing file isn't made")

    }
}
