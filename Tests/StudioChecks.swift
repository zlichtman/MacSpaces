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
        print("Studio checks passed")
    }
}
