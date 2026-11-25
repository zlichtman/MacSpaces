import Foundation

/// One reading of some of a script's words in a voice. Studio keeps a script's takes beside the
/// scripts (Takes/<script id>/takes.json, each take's audio as <take id>.wav), newest first.
struct StudioTake: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// Exactly the words read.
    let text: String
    /// What read it: `recorded:<id>` for a voice from recordings, a Mac voice's identifier, or
    /// empty for Automatic (the best Mac voice for the language).
    let voice: String
    let voiceName: String
    /// The engine that made a take in a voice from recordings ("Qwen3-TTS 0.6B"); nil for Mac voices.
    let engine: String?
    /// The random seed the engine sampled with, so each take of the same words differs; nil for
    /// Mac voices, which read the same way every time.
    let seed: UInt64?
    /// The delivery asked of an engine that follows one (CosyVoice), else nil.
    let style: String?
    /// How fast it plays against the voice's own pace (1 is as made).
    let pace: Double
    let seconds: Double
    let created: Date
    var starred: Bool = false
    /// Siren's delivery it was read in (`VoiceDelivery` raw value: "soft", "upbeat"); nil is Natural.
    var delivery: String? = nil
    /// Made with Best Quality (each piece the most alike of up to three attempts); nil is Fast.
    var bestQuality: Bool? = nil

    var fileName: String { id.uuidString + ".wav" }
}

/// Studio's pure rules: which words a reading takes, take lists, styles, pace and file names.
enum StudioTakes {
    /// Siren's pace range: slower or quicker without changing the pitch.
    static let paces: ClosedRange<Double> = 0.75...1.25
    static let paceStep = 0.05
    /// Siren's style chips for an engine that follows a style (CosyVoice 3).
    static let styles = ["Calm", "Excited", "Whispering", "Sad", "Serious"]
    static let styleLimit = 240

    /// The words a reading takes: the selection when it holds any words, else the whole script.
    static func reading(_ script: String, selection: NSRange?) -> String {
        let whole = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, selection.length > 0, selection.location != NSNotFound,
              NSMaxRange(selection) <= (script as NSString).length else { return whole }
        let picked = (script as NSString).substring(with: selection).trimmingCharacters(in: .whitespacesAndNewlines)
        return picked.isEmpty ? whole : picked
    }

    /// True when `selection` picks out some words (so Read reads them, not the whole script).
    static func readsSelection(_ script: String, selection: NSRange?) -> Bool {
        let whole = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let read = reading(script, selection: selection)
        return !read.isEmpty && read != whole
    }

    static func clampedPace(_ pace: Double) -> Double {
        let stepped = (pace / paceStep).rounded() * paceStep
        return min(paces.upperBound, max(paces.lowerBound, (stepped * 100).rounded() / 100))
    }

    /// A chip's style, lowercased as Siren sends it; choosing the chip already chosen clears it.
    static func toggled(_ current: String, chip: String) -> String {
        let style = chip.lowercased()
        return current.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == style ? "" : style
    }

    /// The style sent to the engine: trimmed, at most `styleLimit` characters, nil when empty.
    static func cleanStyle(_ style: String) -> String? {
        let trimmed = String(style.trimmingCharacters(in: .whitespacesAndNewlines).prefix(styleLimit))
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Lists

    /// A new take goes first.
    static func adding(_ take: StudioTake, to takes: [StudioTake]) -> [StudioTake] {
        [take] + takes.filter { $0.id != take.id }
    }

    static func toggledStar(_ id: UUID, in takes: [StudioTake]) -> [StudioTake] {
        takes.map { take in
            guard take.id == id else { return take }
            var starred = take
            starred.starred.toggle()
            return starred
        }
    }

    /// Keeping the best: the starred takes stay and the rest go. With nothing starred nothing goes.
    static func keepingStarred(_ takes: [StudioTake]) -> (kept: [StudioTake], removed: [StudioTake]) {
        guard takes.contains(where: \.starred) else { return (takes, []) }
        return (takes.filter(\.starred), takes.filter { !$0.starred })
    }

    /// Which take of these words this is, counting from the oldest (Take 1, Take 2 and so on).
    static func number(of take: StudioTake, in takes: [StudioTake]) -> Int {
        let same = takes.filter { $0.text == take.text }.sorted { $0.created < $1.created }
        return (same.firstIndex { $0.id == take.id } ?? 0) + 1
    }

    /// How many takes there are of these words.
    static func count(of text: String, in takes: [StudioTake]) -> Int {
        takes.filter { $0.text == text }.count
    }

    /// The takes whose audio is still on disk (`exists` says which files are); the rest are dropped.
    static func present(_ takes: [StudioTake], exists: (String) -> Bool) -> [StudioTake] {
        takes.filter { exists($0.fileName) }
    }

    // MARK: Names

    /// A file name for a saved take: the voice, then the first words (at most 40 characters),
    /// with nothing a file name can't hold.
    static func fileName(for take: StudioTake) -> String {
        let words = take.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? take.text
        let cleaned = (take.voiceName + " - " + words)
            .map { "/:\\\"*?<>|".contains($0) ? "-" : $0 }
        let name = String(String(cleaned).prefix(take.voiceName.count + 3 + 40)).trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Take" : name) + ".wav"
    }

    /// "0:07", "1:24".
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
