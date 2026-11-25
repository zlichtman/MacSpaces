import Foundation

/// Studio's rules without audio: what Read reads, take lists (star, keep the best, numbering),
/// styles, pace and the names saved takes get.
@main struct StudioChecks {
    static func take(_ text: String, minutes: Double, starred: Bool = false, voice: String = "Sam") -> StudioTake {
        StudioTake(id: UUID(), text: text, voice: "recorded:x", voiceName: voice, engine: "Qwen3-TTS 0.6B", seed: 7, style: nil,
                   pace: 1, seconds: 3, created: Date(timeIntervalSince1970: minutes * 60), starred: starred)
    }

    static func main() {
        // Read: the selection when it has words, else the whole script.
        let script = "  Hello there.\nThis is the second line.  "
        precondition(StudioTakes.reading(script, selection: nil) == "Hello there.\nThis is the second line.")
        precondition(StudioTakes.reading(script, selection: NSRange(location: 2, length: 12)) == "Hello there.")
        precondition(StudioTakes.reading(script, selection: NSRange(location: 14, length: 1)) == StudioTakes.reading(script, selection: nil),
                     "A selection of only spaces reads the whole script")
        precondition(StudioTakes.reading(script, selection: NSRange(location: 5, length: 500)) == StudioTakes.reading(script, selection: nil),
                     "A selection past the end (the text changed) reads the whole script")
        precondition(StudioTakes.readsSelection(script, selection: NSRange(location: 2, length: 12)))
        precondition(!StudioTakes.readsSelection(script, selection: NSRange(location: 0, length: 0)))
        precondition(!StudioTakes.readsSelection(script, selection: NSRange(location: 0, length: (script as NSString).length)),
                     "Selecting everything is the whole script")

        // Takes: newest first, star, keep the starred, number takes of the same words.
        let a1 = take("Hello there.", minutes: 1), b1 = take("Second line.", minutes: 2), a2 = take("Hello there.", minutes: 3)
        var takes = StudioTakes.adding(a1, to: [])
        takes = StudioTakes.adding(b1, to: takes)
        takes = StudioTakes.adding(a2, to: takes)
        precondition(takes.map(\.id) == [a2.id, b1.id, a1.id])
        precondition(StudioTakes.number(of: a1, in: takes) == 1 && StudioTakes.number(of: a2, in: takes) == 2)
        precondition(StudioTakes.number(of: b1, in: takes) == 1)
        precondition(StudioTakes.count(of: "Hello there.", in: takes) == 2)
        precondition(StudioTakes.keepingStarred(takes).removed.isEmpty, "Nothing starred: nothing goes")
        takes = StudioTakes.toggledStar(a2.id, in: takes)
        precondition(takes[0].starred && !takes[1].starred)
        let (kept, removed) = StudioTakes.keepingStarred(takes)
        precondition(kept.map(\.id) == [a2.id] && Set(removed.map(\.id)) == [a1.id, b1.id])
        precondition(!StudioTakes.toggledStar(a2.id, in: takes)[0].starred, "Starring again unstars")
        precondition(StudioTakes.present(takes, exists: { $0 == a1.fileName }).map(\.id) == [a1.id],
                     "Takes whose audio is gone are dropped")

        // Styles: lowercased, the same chip again clears it, trimmed and capped.
        precondition(StudioTakes.toggled("", chip: "Calm") == "calm")
        precondition(StudioTakes.toggled("calm", chip: "Calm") == "")
        precondition(StudioTakes.toggled("calm", chip: "Sad") == "sad")
        precondition(StudioTakes.cleanStyle("   ") == nil)
        precondition(StudioTakes.cleanStyle(" whispering ") == "whispering")
        precondition(StudioTakes.cleanStyle(String(repeating: "a", count: 300))?.count == StudioTakes.styleLimit)

        // Pace: Siren's 0.75 to 1.25 in 0.05 steps.
        precondition(StudioTakes.clampedPace(2) == 1.25 && StudioTakes.clampedPace(0.1) == 0.75)
        precondition(StudioTakes.clampedPace(1.02) == 1.0 && StudioTakes.clampedPace(1.13) == 1.15)

        // Names: the voice and the first words, nothing a file name can't hold.
        let named = take("Ship it: v2/final?\nMore words", minutes: 4)
        precondition(StudioTakes.fileName(for: named) == "Sam - Ship it- v2-final-.wav", StudioTakes.fileName(for: named))
        let long = take(String(repeating: "word ", count: 30), minutes: 5)
        precondition(StudioTakes.fileName(for: long).count <= "Sam - ".count + 40 + ".wav".count)
        precondition(StudioTakes.duration(7.4) == "0:07" && StudioTakes.duration(84) == "1:24")

        // Saved takes read back.
        let data = try! JSONEncoder().encode([a1])
        precondition(try! JSONDecoder().decode([StudioTake].self, from: data) == [a1])
        // A take saved before Best Quality reads as Fast; a Best Quality take keeps saying so.
        precondition(a1.bestQuality == nil && !String(decoding: data, as: UTF8.self).contains("bestQuality"))
        var best = a1
        best.bestQuality = true
        precondition(try! JSONDecoder().decode([StudioTake].self, from: JSONEncoder().encode([best]))[0].bestQuality == true)
        prompterChecks()
        print("Studio checks passed")
    }

    /// The teleprompter's marks, positions, lines, points, timing, takes and saved scripts.
    static func prompterChecks() {
        // Sections, notes, points and paragraphs.
        let text = """
        # Opening
        Hello everyone, [smile] thanks for coming.

        > Mention the launch date in March
        Today we ship. [pause for two seconds] Then questions.
        ## Pricing
        It costs nothing. [end on a smile]
        """
        let script = PrompterScript(text)
        precondition(script.sections.map(\.title) == ["Opening", "Pricing"])
        precondition(script.sections[0].firstWord == 0 && script.words[0].kind == .heading && script.words[0].breaksBefore)
        precondition(script.points.map(\.text) == ["Mention the launch date in March"] && script.points[0].keywords == ["mention", "launch", "date", "march"])
        precondition(!script.words.contains { $0.text.hasPrefix(">") }, "Points aren't in the text")
        let kinds = script.words.map(\.kind)
        precondition(kinds.filter { $0 == .heading }.count == 2)
        precondition(script.words.filter { $0.kind == .note }.map(\.text) == ["[smile]", "[pause", "for", "two", "seconds]", "[end", "on", "a", "smile]"],
                     "A note mid-sentence, one of several words, and one ending the script")
        precondition(script.spoken == ["hello", "everyone", "thanks", "for", "coming", "today", "we", "ship", "then", "questions", "it", "costs", "nothing"],
                     "Speech is compared with spoken words only: no headings or notes")
        let hello = script.words.firstIndex { $0.text == "Hello" }!, today = script.words.firstIndex { $0.text == "Today" }!
        precondition(script.words[hello].breaksBefore, "The first words after a heading start a line")
        precondition(script.words[today].breaksBefore, "A blank line starts a paragraph")
        precondition(!script.words[today + 1].breaksBefore)
        let thanks = script.words.firstIndex { $0.text == "thanks" }!
        // "Hello everyone," heard: rest on [smile], which is still to come, not past it on "thanks".
        precondition(script.word(afterSpoken: 2) == thanks - 1 && script.words[thanks - 1].text == "[smile]", "A note after the words heard is still ahead")
        precondition(script.spoken(atOrAfter: thanks - 1) == 2, "From a note, the next spoken word")
        // "…coming." heard: the paragraph's last word; the point and "Today" are next.
        precondition(script.word(afterSpoken: 5) == today, "Resting after the last word heard")
        // "…questions." heard: the Pricing heading on its own line is next, not skipped.
        precondition(script.word(afterSpoken: 10) == script.sections[1].firstWord, "A heading after the words heard is still ahead")
        precondition(script.word(afterSpoken: script.spoken.count) == script.words.firstIndex { $0.text == "[end" }!, "A closing note is still shown")
        precondition(script.word(afterSpoken: 99) == script.word(afterSpoken: script.spoken.count) && script.word(afterSpoken: 0) == 0)
        precondition(PrompterScript("").word(afterSpoken: 3) == 0)
        precondition(script.spoken(atOrAfter: script.words.count - 1) == script.spoken.count)

        // Sections: Tab and Shift-Tab.
        let pricing = script.sections[1].firstWord
        precondition(script.section(containing: 3) == 0 && script.section(containing: pricing + 1) == 1)
        precondition(script.nextSection(after: 0) == 1 && script.nextSection(after: Double(pricing)) == nil)
        precondition(script.previousSection(before: Double(pricing + 3)) == 1, "Into a section, back to its start")
        precondition(script.previousSection(before: Double(pricing)) == 0 && script.previousSection(before: 0) == nil)

        // Marks that don't make anything.
        precondition(PrompterScript.heading(in: "#hashtag") == nil && PrompterScript.heading(in: "####### Seven") == nil && PrompterScript.heading(in: "# ") == nil)
        precondition(PrompterScript.point(in: ">") == nil)
        let open = PrompterScript("Start [unclosed note here\n\nBack to speaking.")
        precondition(open.words.last?.kind == .spoken, "A note left open ends with its paragraph")
        precondition(PrompterScript("").words.isEmpty && PrompterScript("Plain words only").spoken.count == 3)

        // Points: said in your own words.
        let point = script.points[0]
        precondition(PrompterScript.covered(point, heard: ["we", "launch", "in", "march"]) == false, "Two of four isn't enough")
        precondition(PrompterScript.covered(point, heard: ["launching", "on", "the", "date", "march"]), "Three of four, a different ending counting")
        precondition(!PrompterScript.covered(PrompterScript.Point(text: "the and", keywords: []), heard: ["the"]))
        precondition(PrompterScript.covered(PrompterScript.Point(text: "Pricing", keywords: ["pricing"]), heard: ["pricing"]))

        // Lines: headings alone, paragraphs new, width respected.
        let lines = PrompterLayout.wrap(script.words, width: 40, space: 2, measure: { Double(script.words[$0].text.count * 4) })
        precondition(lines[0].isHeading && lines[0].count == 1)
        precondition(lines.allSatisfy { line in line.count == 1 || (line.first..<line.first + line.count).map { script.words[$0].text.count * 4 + 2 }.reduce(-2, +) <= 40 })
        precondition(lines.contains { $0.first == today }, "A paragraph starts a line")
        precondition(lines.filter(\.isHeading).map(\.first) == script.sections.map(\.firstWord))
        precondition(PrompterLayout.line(containing: Double(today) + 0.5, in: lines) == lines.firstIndex { $0.first == today })
        // Runs: a plain line is one run; a note splits it; a heading is its own.
        let wide = PrompterLayout.wrap(script.words, width: 10_000, space: 2, measure: { _ in 1 })
        let runs = PrompterLayout.segments(wide, words: script.words, shown: { $0.kind == .heading ? $0.text.uppercased() : $0.text })
        precondition(runs[0] == [PrompterLayout.Segment(text: "OPENING", kind: .heading)])
        precondition(runs[1].map(\.text) == ["Hello everyone,", "[smile]", "thanks for coming."] && runs[1].map(\.kind) == [.spoken, .note, .spoken])
        precondition(runs.count == wide.count && runs.last?.last?.text == "[end on a smile]")

        // Timing against a target.
        precondition(PrompterTiming.state(elapsed: 100, target: nil) == .fine)
        precondition(PrompterTiming.state(elapsed: 47, target: 60) == .fine && PrompterTiming.state(elapsed: 48, target: 60) == .near)
        precondition(PrompterTiming.state(elapsed: 61, target: 60) == .over && PrompterTiming.clock(125.9) == "2:05")

        // A take's summary.
        var summary = PrompterTakeSummary(duration: 90, spokenWords: 210, longestPause: nil, points: 2, missed: ["Pricing"], target: 120)
        precondition(summary.pace == 140)
        precondition(PrompterTakeSummary(duration: 90, spokenWords: 0, longestPause: nil, points: 0, missed: [], target: nil).pace == nil, "No words counted: no pace")
        summary.duration = 3
        precondition(summary.pace == nil, "Too short to say")
        precondition(PrompterTakeSummary.longestPause([2, 3, 9, 10], start: 0) == 6)
        precondition(PrompterTakeSummary.longestPause([], start: 0) == nil)

        // A PDF's printed lines become paragraphs.
        let printed = "Welcome back to the\nshow. Today we are talk-\ning about mornings.\n\n# News\nThree things hap-\nPened this week.\n> Thank everyone\nBye."
        precondition(ScriptImport.paragraphs(fromPrinted: printed)
                     == "Welcome back to the show. Today we are talking about mornings.\n\n# News\n\nThree things hap- Pened this week.\n\n> Thank everyone\n\nBye.")
        precondition(ScriptImport.paragraphs(fromPrinted: "\n\n  \n") == "")

        // Saved scripts: a 4.33 library opens, with no target, place or speed of its own.
        let old = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Toast","text":"To the two of you.","edited":786000000}]"#
        let decoded = try! JSONDecoder().decode([SavedScript].self, from: Data(old.utf8))
        precondition(decoded.count == 1 && decoded[0].title == "Toast" && decoded[0].target == nil && decoded[0].lastPosition == nil && decoded[0].speed == nil)
        var saved = decoded[0]
        saved.target = 60; saved.lastPosition = 4; saved.speed = 150
        precondition(try! JSONDecoder().decode([SavedScript].self, from: JSONEncoder().encode([saved])) == [saved])
    }
}
