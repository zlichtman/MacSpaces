import Foundation

/// Voices from recordings without any model: sorting people across recordings on made-up
/// fingerprints, choosing the speaking engine, and the download store's whole, part-way and
/// missing states and Remove, in a temporary folder.
@main struct VoiceChecks {
    /// A unit fingerprint near `base`, nudged by `noise` in a direction set by `seed`.
    static func print(_ base: Int, noise: Float = 0, seed: Int = 0) -> [Float] {
        var v = [Float](repeating: 0, count: 256)
        v[base] = 1
        if noise > 0 { v[(base + 17 + seed * 31) % 256] = noise }
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return v.map { $0 / norm }
    }

    static func main() async throws {
        typealias M = VoiceGrouping.Member
        // Two recordings: A and B in the first, A again and C in the second.
        let members = [
            M(recording: 0, person: 0, seconds: 120, fingerprint: print(1)),
            M(recording: 0, person: 1, seconds: 40, fingerprint: print(2)),
            M(recording: 1, person: 0, seconds: 30, fingerprint: print(1, noise: 0.3)),
            M(recording: 1, person: 1, seconds: 60, fingerprint: print(3)),
        ]
        let groups = VoiceGrouping.groups(members)
        precondition(groups.count == 3, "The same person in two recordings is one person: \(groups)")
        precondition(groups[0] == [0, 2], "Most heard first, with both recordings: \(groups)")
        precondition(groups[1] == [3] && groups[2] == [1])

        // Two people of one recording are never joined, however alike they sound.
        let twins = [M(recording: 0, person: 0, seconds: 10, fingerprint: print(5)),
                     M(recording: 0, person: 1, seconds: 9, fingerprint: print(5, noise: 0.05))]
        precondition(VoiceGrouping.groups(twins).count == 2)

        // An uncertain match stays apart; no fingerprint stays alone.
        let unsure = [M(recording: 0, person: 0, seconds: 10, fingerprint: print(7)),
                      M(recording: 1, person: 0, seconds: 10, fingerprint: print(7, noise: 1.2)),
                      M(recording: 2, person: 0, seconds: 10, fingerprint: nil)]
        precondition(VoiceGrouping.groups(unsure).count == 3)

        // Complete link: a third recording must match everyone already in the group.
        let chain = [M(recording: 0, person: 0, seconds: 30, fingerprint: print(9)),
                     M(recording: 1, person: 0, seconds: 20, fingerprint: print(9, noise: 0.7, seed: 0)),
                     M(recording: 2, person: 0, seconds: 10, fingerprint: print(9, noise: 0.7, seed: 1))]
        precondition(VoiceGrouping.groups(chain).count == 2, "\(VoiceGrouping.groups(chain))")

        // A tagged voice is recognised only when clearly alike.
        let known = [(id: "a", fingerprint: print(1)), (id: "b", fingerprint: print(2))]
        precondition(VoiceGrouping.match(print(1, noise: 0.2), among: known) == "a")
        precondition(VoiceGrouping.match(print(4), among: known) == nil)
        precondition(VoiceGrouping.match(nil, among: known) == nil)
        precondition(VoiceGrouping.match([Float](repeating: .nan, count: 256), among: known) == nil)
        let average = VoiceGrouping.average([(print(1), 3), (print(1, noise: 0.2), 1)])!
        precondition(VoiceGrouping.similarity(average, print(1)) > 0.95)

        // The engine: the chosen one while downloaded, else the closest copy that fits.
        let gb: UInt64 = 1_073_741_824
        precondition(VoiceModel.speakingEngine(chosen: nil, downloaded: [], memoryBytes: 16 * gb) == nil)
        precondition(VoiceModel.speakingEngine(chosen: nil, downloaded: ["sorting"], memoryBytes: 16 * gb) == nil, "Sorting doesn't speak")
        precondition(VoiceModel.speakingEngine(chosen: nil, downloaded: ["standard", "standard-small"], memoryBytes: 16 * gb) == .standard)
        precondition(VoiceModel.speakingEngine(chosen: nil, downloaded: ["standard", "standard-small"], memoryBytes: 8 * gb) == .standardSmall)
        precondition(VoiceModel.speakingEngine(chosen: nil, downloaded: ["standard"], memoryBytes: 8 * gb) == .standard, "A model that doesn't fit still beats none")
        precondition(VoiceModel.speakingEngine(chosen: "expressive", downloaded: ["standard", "expressive"], memoryBytes: 16 * gb) == .expressive)
        precondition(VoiceModel.speakingEngine(chosen: "expressive", downloaded: ["standard"], memoryBytes: 16 * gb) == .standard, "A removed choice falls back")
        precondition(VoiceModel.speakingEngine(chosen: "sorting", downloaded: ["sorting", "standard-small"], memoryBytes: 16 * gb) == .standardSmall)
        precondition(Set(VoiceModel.catalogue.map(\.id)).count == VoiceModel.catalogue.count)
        precondition(VoiceModel.catalogue.allSatisfy { !$0.parts.isEmpty && $0.downloadBytes > 0 })
        // Music removal is its own optional download: it never speaks, and Finding voices doesn't need it.
        precondition(!VoiceModel.musicRemoval.speaks && !VoiceModel.engines.contains(.musicRemoval))
        precondition(VoiceModel.speakingEngine(chosen: "music-removal", downloaded: ["sorting", "music-removal"], memoryBytes: 16 * gb) == nil)
        precondition(!VoiceModel.sorting.allParts.contains(VoiceModel.separatorRepo), "Music removal isn't part of Finding voices")
        precondition(VoiceModel.musicRemoval.peakGB <= 4, "Music removal stays under 4 GB")

        // Music removal's gate: talk with music under it is separated, a clean recording isn't.
        let talkRate = 24_000
        func talk(bed: Float) -> [Float] {
            (0..<(talkRate * 4)).map { i in
                let t = Float(i) / Float(talkRate)
                let speaking = Int(t * 4) % 2 == 0  // a quarter second of words, a quarter second of gap
                return (speaking ? 0.3 * sin(2 * .pi * 220 * t) : 0) + bed * sin(2 * .pi * 330 * t)
            }
        }
        let quietGap = MusicRemoval.gapLevelDB(talk(bed: 0), rate: talkRate), withMusic = MusicRemoval.gapLevelDB(talk(bed: 0.1), rate: talkRate)
        precondition(!MusicRemoval.needsSeparation(gapDB: quietGap), "A clean recording isn't separated: \(quietGap) dB")
        precondition(MusicRemoval.needsSeparation(gapDB: withMusic), "Music 10 dB under the talk is: \(withMusic) dB")
        precondition(MusicRemoval.gapLevelDB([0.1, 0.2], rate: talkRate) == -120, "Too short to tell")
        // SAM must find music after all, or the original is kept.
        precondition(MusicRemoval.foundMusic(residualShareDB: MusicRemoval.residualShareDB(speechEnergy: 9, residualEnergy: 1, samples: 100)))
        precondition(!MusicRemoval.foundMusic(residualShareDB: MusicRemoval.residualShareDB(speechEnergy: 999, residualEnergy: 1, samples: 100)))
        precondition(MusicRemoval.residualShareDB(speechEnergy: 0, residualEnergy: 0, samples: 100) == -100)
        // Overlapped pieces join seamlessly: a transform that changes nothing gives the input back.
        let long = (0..<10_000).map { Float(sin(Double($0) * 0.01)) }
        var pieces = 0
        let joined = try await MusicRemoval.overlapped(long, step: 3_000, context: 500, fade: 200) { piece in
            pieces += 1
            precondition(piece.count <= 4_000, "Each piece is at most a step and its context")
            return piece
        }
        precondition(pieces == 4 && joined.count == long.count)
        precondition(zip(joined, long).allSatisfy { abs($0 - $1) < 1e-5 }, "Pieces join back to the original")
        let doubled = try await MusicRemoval.overlapped(long, step: 3_000, context: 500, fade: 200) { $0.map { $0 * 2 } }
        precondition(zip(doubled, long).allSatisfy { abs($0 - 2 * $1) < 1e-4 })
        precondition(MusicRemoval.fitted([1, 2, 3], 2) == [1, 2] && MusicRemoval.fitted([1], 3) == [1, 0, 0])

        // The store: missing, part-way, whole, then Remove frees it.
        let hub = FileManager.default.temporaryDirectory.appendingPathComponent("voice-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: hub) }
        let store = VoiceModelStore(hub: hub)
        precondition(store.state(of: .sorting) == .notDownloaded)
        for part in VoiceModel.sorting.parts {
            try FileManager.default.createDirectory(at: store.folder(for: part), withIntermediateDirectories: true)
        }
        try Data(repeating: 1, count: 1000).write(to: store.folder(for: VoiceModel.diarizerRepo).appendingPathComponent("model.safetensors"))
        guard case .partial = store.state(of: .sorting) else { preconditionFailure("A part-way download is partial") }
        try VoiceModelStore.markComplete(store.folder(for: VoiceModel.diarizerRepo))
        guard case .partial = store.state(of: .sorting) else { preconditionFailure("One whole part of two is still partial") }
        try Data(repeating: 2, count: 500).write(to: store.folder(for: VoiceModel.fingerprintRepo).appendingPathComponent("model.safetensors"))
        try store.markWhole(.sorting)
        precondition(store.state(of: .sorting) == .downloaded(bytes: VoiceModelStore.size(of: store.folder(for: VoiceModel.diarizerRepo))
                                                                     + VoiceModelStore.size(of: store.folder(for: VoiceModel.fingerprintRepo))))
        precondition(store.downloaded() == ["sorting"])
        // A file cut short after the marker makes it part-way again.
        try Data(repeating: 2, count: 10).write(to: store.folder(for: VoiceModel.fingerprintRepo).appendingPathComponent("model.safetensors"))
        guard case .partial = store.state(of: .sorting) else { preconditionFailure("A changed file isn't whole") }
        try VoiceModelStore.markComplete(store.folder(for: VoiceModel.fingerprintRepo))
        let freed = try store.remove(.sorting)
        precondition(freed > 1000 && store.state(of: .sorting) == .notDownloaded)
        // Deliveries (Siren's): the best is Natural; with three strong clips, the slowest and
        // quietest is Slow and Soft and the quickest and liveliest Upbeat; weak clips don't count.
        typealias C = VoiceDelivery.Candidate
        precondition(VoiceDelivery.pick([]).isEmpty)
        let lone = VoiceDelivery.pick([C(score: 0.8, words: 30, seconds: 10, loudness: 0.5, liveliness: 0.5)])
        precondition(lone == [.natural: 0], "One clip is Natural alone: \(lone)")
        let clips = [
            C(score: 0.80, words: 30, seconds: 10, loudness: 0.5, liveliness: 0.5),   // steady: Natural
            C(score: 0.75, words: 18, seconds: 10, loudness: 0.2, liveliness: 0.3),   // slow and quiet
            C(score: 0.74, words: 42, seconds: 10, loudness: 0.7, liveliness: 0.9),   // quick and lively
            C(score: 0.40, words: 10, seconds: 10, loudness: 0.1, liveliness: 0.1),   // weak: never chosen
        ]
        let picks = VoiceDelivery.pick(clips)
        precondition(picks == [.natural: 0, .soft: 1, .upbeat: 2], "Deliveries: \(picks)")
        precondition(VoiceDelivery.pick(Array(clips.prefix(2)) + [clips[3]]) == [.natural: 0],
                     "Fewer than three strong clips give Natural alone")
        let alike = [C(score: 0.8, words: 30, seconds: 10, loudness: 0.5, liveliness: 0.5),
                     C(score: 0.8, words: 30, seconds: 10, loudness: 0.5, liveliness: 0.5),
                     C(score: 0.8, words: 30, seconds: 10, loudness: 0.5, liveliness: 0.5)]
        let same = VoiceDelivery.pick(alike)
        precondition(same == [.natural: 0],
                     "A delivery is never the Natural clip again: \(same)")

        // Several recordings, sorted one at a time: a person found in a new recording joins the
        // voice they already are (complete link), never one with a clip from the same recording.
        typealias S = VoiceSamples.Sample
        let first = UUID(), second = UUID(), third = UUID()
        func sample(_ file: String, _ seconds: Double, _ print: [Float]?, _ recording: UUID?, included: Bool = true,
                    delivery: VoiceDelivery = .natural) -> S {
            S(file: file, transcript: file, seconds: seconds, delivery: delivery, included: included, fingerprint: print, recording: recording)
        }
        let host = VoiceSamples.Candidate(id: "host", samples: [(first, print(1)), (second, print(1, noise: 0.2))])
        let guest = VoiceSamples.Candidate(id: "guest", samples: [(first, print(2))])
        precondition(VoiceSamples.joining(print(1, noise: 0.25, seed: 2), recording: third, among: [host, guest]) == "host",
                     "The host heard again in a third recording joins the host")
        precondition(VoiceSamples.joining(print(1), recording: first, among: [host, guest]) == nil,
                     "Two people of one recording never join")
        precondition(VoiceSamples.joining(print(4), recording: third, among: [host, guest]) == nil, "Someone new is a new voice")
        precondition(VoiceSamples.joining(nil, recording: third, among: [host, guest]) == nil, "No fingerprint, no joining")
        let loose = VoiceSamples.Candidate(id: "loose", samples: [(first, print(9)), (second, print(9, noise: 0.7, seed: 0))])
        precondition(VoiceSamples.joining(print(9, noise: 0.7, seed: 1), recording: third, among: [loose]) == nil,
                     "Complete link: it must match every clip already there")
        precondition(VoiceSamples.soundsLike(print(1, noise: 0.9), among: [(id: "host", fingerprint: print(1)), (id: "guest", fingerprint: print(2))]) == "host",
                     "A looser likeness is offered as Same Person")
        precondition(VoiceSamples.soundsLike(print(5), among: [(id: "host", fingerprint: print(1))]) == nil)

        // Its clips: each delivery reads one included clip, picked Siren's way; the last included
        // Natural clip can't be left out.
        let kept = [sample("a", 12, print(1), first), sample("b", 6, print(1), second), sample("c", 9, print(1), second),
                     sample("soft", 8, nil, first, delivery: .soft), sample("up", 7, nil, first, included: false, delivery: .upbeat)]
        precondition(VoiceSamples.reference(kept, for: .natural) == 0, "Nothing measured: the first that passes the checks")
        precondition(VoiceSamples.reference(kept, for: .soft) == 3)
        precondition(VoiceSamples.reference(kept, for: .upbeat) == 0, "A delivery left out reads Natural's choice")
        precondition(VoiceSamples.deliveries(kept) == [.natural, .soft])
        var leftOut = kept
        leftOut[0].included = false
        precondition(VoiceSamples.reference(leftOut, for: .natural) == 2, "A clip left out isn't read; 6 s is under the 8 s check")
        precondition(VoiceSamples.canExclude(kept, at: 0) && VoiceSamples.canExclude(kept, at: 3))
        let single = [sample("a", 12, nil, first), sample("soft", 8, nil, first, delivery: .soft)]
        precondition(!VoiceSamples.canExclude(single, at: 0), "The last Natural clip stays in")
        precondition(VoiceSamples.reference([sample("a", 30, nil, nil)], for: .natural) == 0, "One long clip is used whole")
        precondition(VoiceSamples.reference([], for: .natural) == nil)
        // Measured: identity first, then the sample checks, then the cleanest.
        typealias E = VoiceSamples.Evidence
        func measured(_ file: String, _ seconds: Double, _ evidence: E, delivery: VoiceDelivery = .natural) -> S {
            var made = sample(file, seconds, print(1), first, delivery: delivery)
            made.evidence = evidence
            return made
        }
        let clean = E(backgroundDB: 32, likeness: 0.8, longestPause: 0.3, joined: false, quality: 0.8, fellBack: false)
        var noisy = clean; noisy.backgroundDB = 12
        var unlike = clean; unlike.likeness = 0.45
        var paused = clean; paused.longestPause = 1.4
        var stitched = clean; stitched.joined = true
        var fell = clean; fell.fellBack = true
        var cleaner = clean; cleaner.backgroundDB = 45
        precondition(VoiceSamples.reference([measured("n", 12, noisy), measured("c", 10, clean)], for: .natural) == 1,
                     "Speech under 20 dB above its background fails the checks")
        precondition(VoiceSamples.reference([measured("p", 12, paused), measured("c", 10, clean)], for: .natural) == 1,
                     "A long pause between words fails the checks")
        precondition(VoiceSamples.reference([measured("j", 14, stitched), measured("c", 9, clean)], for: .natural) == 1,
                     "Joined bursts give way to a single clip that passes")
        precondition(VoiceSamples.reference([measured("s", 5, clean), measured("j", 14, stitched)], for: .natural) != nil)
        precondition(VoiceSamples.reference([measured("u", 12, unlike), measured("n", 12, noisy)], for: .natural) == 1,
                     "A clip measured as unlike them comes after any that's them")
        precondition(VoiceSamples.reference([measured("f", 12, fell), measured("c", 10, clean)], for: .natural) == 1,
                     "A clip whose checks fell back comes last")
        precondition(VoiceSamples.reference([measured("c", 10, clean), measured("k", 10, cleaner)], for: .natural) == 1,
                     "Of two that pass, the cleaner")
        precondition(VoiceSamples.reference([measured("u", 12, unlike), measured("s", 9, clean, delivery: .soft)], for: .natural) == 1,
                     "An unlike Natural clip gives way to a clip that's them, whatever its delivery")
        // Use First pins a clip for its delivery; Choose Automatically lets it go.
        let pinned = VoiceSamples.pinnedFirst(kept, at: 2)
        precondition(pinned.map(\.file) == ["c", "a", "b", "soft", "up"] && pinned[0].pinned == true)
        precondition(VoiceSamples.reference(pinned, for: .natural) == 0 && VoiceSamples.reference(pinned, for: .soft) == 3)
        var pinnedWorse = [measured("n", 12, noisy), measured("c", 10, clean)]
        pinnedWorse = VoiceSamples.pinnedFirst(pinnedWorse, at: 1)
        pinnedWorse = VoiceSamples.pinnedFirst(pinnedWorse, at: 1)
        precondition(pinnedWorse[0].file == "n" && pinnedWorse[1].pinned == nil && VoiceSamples.reference(pinnedWorse, for: .natural) == 0,
                     "A pin beats the automatic choice, and only one clip of a delivery is pinned")
        precondition(VoiceSamples.reference(VoiceSamples.unpinned(pinnedWorse, at: 0), for: .natural) == 1)
        var pinnedOut = pinnedWorse
        pinnedOut[0].included = false
        precondition(VoiceSamples.reference(pinnedOut, for: .natural) == 1, "A pinned clip left out isn't read")
        let pinnedUp = VoiceSamples.pinnedFirst(kept, at: 4)
        precondition(VoiceSamples.reference(pinnedUp, for: .upbeat) == 0 && VoiceSamples.reference(pinnedUp, for: .natural) == 1,
                     "Use First on Upbeat includes it and leaves Natural's choice alone")
        // A voice from an earlier version: its Use First is inferred from the order.
        let older = Date(timeIntervalSince1970: 0), newer = Date(timeIntervalSince1970: 100)
        let order = [first: older, second: newer]
        precondition(VoiceSamples.inferredPin([sample("b", 6, nil, second), sample("a", 12, nil, first)], added: order) == 0,
                     "A later recording's clip first was put there with Use First")
        precondition(VoiceSamples.inferredPin([sample("a", 12, nil, first), sample("b", 6, nil, second)], added: order) == nil)
        precondition(VoiceSamples.inferredPin([sample("b", 6, nil, second), sample("a", 12, nil, nil)], added: order) == nil, "Unknown order: no pin")
        precondition(VoiceSamples.inferredPin([measured("n", 12, noisy), sample("a", 12, nil, first)], added: order) == nil, "Measured: not old")
        var chosenAuto = [sample("b", 6, nil, second), sample("a", 12, nil, first)]
        chosenAuto = VoiceSamples.unpinned(chosenAuto, at: 0)
        precondition(VoiceSamples.inferredPin(chosenAuto, added: order) == nil, "Choose Automatically is a choice: nothing inferred after it")
        // Measuring an old clip in the app: background gap, longest quiet, and joins.
        let rate = 1_000
        func tone(_ seconds: Double, _ amplitude: Float) -> [Float] {
            (0..<Int(seconds * Double(rate))).map { amplitude * sin(Float($0) * 0.9) }
        }
        let speechy = tone(1, 0.5) + tone(0.3, 0.001) + tone(1, 0.5)
        precondition(VoiceSamples.backgroundGapDB(speechy, rate: rate) > 40, "Quiet gaps far under the speech")
        precondition(VoiceSamples.backgroundGapDB(tone(2, 0.5), rate: rate) < 1, "No gaps: no gap")
        precondition(abs(VoiceSamples.longestQuiet(speechy, rate: rate) - 0.3) < 0.05, "\(VoiceSamples.longestQuiet(speechy, rate: rate))")
        precondition(VoiceSamples.longestQuiet(tone(0.3, 0.001) + tone(1, 0.5), rate: rate) < 0.05, "Quiet before the first sound doesn't count")
        let joins = tone(1, 0.5) + [Float](repeating: 0, count: rate / 4) + tone(1, 0.5)
        precondition(VoiceSamples.looksJoined(joins, rate: rate) && !VoiceSamples.looksJoined(speechy, rate: rate))
        precondition(!VoiceSamples.looksJoined([Float](repeating: 0, count: rate) + tone(1, 0.5), rate: rate), "Leading silence isn't a join")
        // Same Person: an approved voice keeps reading as it did; the clips it gains start left out.
        let gained = VoiceSamples.combined([sample("a", 12, print(1), first)], with: [sample("x", 5, print(1), third)], keepReading: true)
        precondition(gained.count == 2 && gained[1].included == false && VoiceSamples.reference(gained, for: .natural) == 0)
        let waiting = VoiceSamples.combined([sample("a", 5, print(1), first)], with: [sample("x", 12, print(1), third)], keepReading: false)
        precondition(VoiceSamples.reference(waiting, for: .natural) == 1)
        precondition(VoiceGrouping.similarity(VoiceSamples.fingerprint(kept)!, print(1)) > 0.99)
        // A voice saved before 4.02 (voice.json without clips) decodes with its old fields.
        let old = #"{"id":"6F1C2C8E-7D0B-4D7A-9C55-2B1E0F3A9D11","name":"Sam","transcript":"Hi.","seconds":9,"created":0,"consent":"mine"}"#
        struct Old: Codable { let name: String; var samples: [VoiceSamples.Sample]?; var approved: Bool? }
        let decoded = try JSONDecoder().decode(Old.self, from: Data(old.utf8))
        precondition(decoded.name == "Sam" && decoded.samples == nil && decoded.approved == nil, "Old voices read as approved, with their clip")

        // Best Quality (Siren's take judge): the most alike attempt that says the words wins.
        typealias Score = TakeChoice.Score
        let alikeTake = Score(likeness: 0.82, wordError: 0, lengthRatio: 1.0)
        let lessAlike = Score(likeness: 0.64, wordError: 0, lengthRatio: 1.1)
        let skipsWords = Score(likeness: 0.9, wordError: 0.4, lengthRatio: 0.7)
        let runsOn = Score(likeness: 0.8, wordError: nil, lengthRatio: 2.6)
        precondition(TakeChoice.best([lessAlike, alikeTake, skipsWords]) == 1, "More alike wins when both say the words")
        precondition(TakeChoice.best([skipsWords, lessAlike]) == 1, "Skipped words cost more than a little likeness")
        precondition(TakeChoice.best([runsOn, lessAlike]) == 1, "A take that runs far past the clip's pace loses")
        precondition(TakeChoice.best([]) == nil)
        precondition(TakeChoice.best([alikeTake, alikeTake]) == 0, "Of equals, the first")
        precondition(abs(Score(likeness: nil, wordError: nil, lengthRatio: nil).total - (0.5 - 1.5 * TakeChoice.unmeasuredWordError)) < 1e-9,
                     "Unmeasured likeness counts as middling, unheard words as past the good line")
        precondition(Score(likeness: .nan, wordError: -1, lengthRatio: .infinity).total == Score(likeness: nil, wordError: nil, lengthRatio: nil).total,
                     "Nonsense counts as unmeasured")
        let unheard = Score(likeness: 0.8, wordError: nil, lengthRatio: 1)
        precondition(unheard.total < Score(likeness: 0.8, wordError: 0, lengthRatio: 1).total, "Unheard words never beat words said")
        // Siren 0.12: a check that couldn't run never counts as a pass.
        precondition(!unheard.isGoodEnough && !Score(likeness: nil, wordError: 0, lengthRatio: 1).isGoodEnough,
                     "Unmeasured likeness or words never stop the search")
        precondition(!Score(likeness: 0.8, wordError: 0, lengthRatio: nil).isGoodEnough, "A known pace with no length isn't a pass")
        precondition(Score(likeness: 0.8, wordError: 0, lengthRatio: nil, paceKnown: false).isGoodEnough, "No pace to check isn't a failure")
        let passes = Score(likeness: 0.76, wordError: 0.1, lengthRatio: 1), fails = Score(likeness: 0.74, wordError: 0, lengthRatio: 1)
        precondition(fails.total > passes.total && TakeChoice.best([fails, passes]) == 1 && TakeChoice.best([passes, fails]) == 0,
                     "A passing attempt beats a failing one whatever their totals")
        precondition(TakeChoice.replaces(passes, best: nil) && !TakeChoice.replaces(fails, best: passes))
        precondition(!TakeChoice.replaces(Score(likeness: 0.5, wordError: 0, lengthRatio: 1), best: Score(likeness: 0.5, wordError: 0, lengthRatio: 1)),
                     "Of equals, the earlier stays")
        precondition(alikeTake.isGoodEnough && !lessAlike.isGoodEnough && !skipsWords.isGoodEnough && !runsOn.isGoodEnough)
        precondition(TakeChoice.wantsAnother([lessAlike]) && TakeChoice.wantsAnother([lessAlike, skipsWords]))
        precondition(!TakeChoice.wantsAnother([lessAlike, alikeTake]), "A good enough attempt stops making more")
        precondition(!TakeChoice.wantsAnother([lessAlike, skipsWords, runsOn]), "Three at most")
        precondition(!TakeChoice.wantsAnother([lessAlike], limit: 1), "Fast makes one")
        precondition(TakeChoice.seed(42, piece: 0, attempt: 0) == 42, "The first attempt uses the take's own seed")
        let seeds = (0..<3).flatMap { piece in (0..<3).map { TakeChoice.seed(42, piece: piece, attempt: $0) } }
        precondition(Set(seeds).count == 9, "Every attempt samples differently: \(seeds)")
        precondition(seeds == (0..<3).flatMap { piece in (0..<3).map { TakeChoice.seed(42, piece: piece, attempt: $0) } },
                     "The same seed makes the same attempts again")
        precondition(TakeChoice.seed(43, piece: 1, attempt: 0) != TakeChoice.seed(42, piece: 1, attempt: 0))
        precondition(TakeChoice.wordErrorRate(said: "Hello there, it's 2 o'clock.", meant: "hello there it's two o'clock") == 0,
                     "Case, punctuation and numbers as words don't count")
        precondition(abs(TakeChoice.wordErrorRate(said: "the cat sat", meant: "the cat sat down") - 0.25) < 1e-9)
        precondition(TakeChoice.wordErrorRate(said: "", meant: "something") == 1)
        let pace = TakeChoice.wordsPerSecond(transcript: "one two three four five six", seconds: 3)!
        precondition(abs(pace - 2) < 1e-9 && TakeChoice.wordsPerSecond(transcript: "hi", seconds: 3) == nil)
        precondition(abs(TakeChoice.lengthRatio(seconds: 3, text: "a b c d", wordsPerSecond: 2)! - 1.5) < 1e-9)
        precondition(TakeChoice.lengthRatio(seconds: 3, text: "a b", wordsPerSecond: nil) == nil)

        // Sorting ranks a person's clips on how much each still sounds like them (Siren's
        // likenessRanks): half the difference from the typical clip's likeness.
        let ranks = VoiceSamples.likenessRanks([0.7, 0.7, 0.72], likeness: [0.9, 0.6, nil])
        precondition(abs(ranks[0] - 0.7) < 1e-9 && abs(ranks[1] - 0.55) < 1e-9 && abs(ranks[2] - 0.72) < 1e-9,
                     "Measured from the typical clip; unmeasured counts as typical: \(ranks)")
        precondition(VoiceSamples.likenessRanks([0.5, 0.6], likeness: [nil, nil]) == [0.5, 0.6], "Nothing measured: the scores")
        precondition(VoiceSamples.likenessRanks([0.6, 0.7], likeness: [0.85, 0.55]).enumerated().max { $0.element < $1.element }?.offset == 0,
                     "A clip much more like them beats a slightly fitter one")
        // Up to ten stretches from every recording: each recording's best, then the best of the rest.
        let spread = VoiceSamples.spread([[9, 7, 6], [3, 2], [5]], limit: 5, isBetter: >)
        precondition(spread == [9, 3, 5, 7, 6], "Every recording is heard, then the best: \(spread)")
        precondition(VoiceSamples.spread([[Int]](), limit: 3, isBetter: >).isEmpty && VoiceSamples.spread([[1]], limit: 0, isBetter: >).isEmpty)

        // Short bursts (Siren's): with no clip of 8 s, a person's clips join in the order said, per
        // recording, up to 15 s with a quarter second between.
        typealias P = VoiceBursts.Piece
        let bursts = [P(recording: 0, start: 30, seconds: 4), P(recording: 0, start: 2, seconds: 3.5),
                      P(recording: 0, start: 60, seconds: 6), P(recording: 1, start: 0, seconds: 5), P(recording: 0, start: 90, seconds: 2)]
        precondition(VoiceBursts.needsJoining(bursts))
        precondition(VoiceBursts.groups(bursts) == [[1, 0, 2], [4], [3]],
                     "3.5 + 4 + 6 and two pauses fit 15 s; 2 more would pass it; another recording starts its own: \(VoiceBursts.groups(bursts))")
        precondition(abs(VoiceBursts.seconds(bursts, group: [1, 0, 2]) - 14) < 1e-9)
        let oneLong = [P(recording: 0, start: 0, seconds: 9), P(recording: 0, start: 20, seconds: 3)]
        precondition(!VoiceBursts.needsJoining(oneLong) && VoiceBursts.groups(oneLong) == [[0], [1]], "One clip long enough: nothing joins")
        precondition(!VoiceBursts.needsJoining([P(recording: 0, start: 0, seconds: 3)]), "One clip alone stays as it is")
        precondition(VoiceBursts.groups([]).isEmpty)
        precondition(abs(VoiceBursts.weighted([(-20, 3), (-30, 1)]) - -22.5) < 1e-9)

        ownVoiceTakeChecks()

        Swift.print("Voice checks passed: deliveries, sorting across recordings, joining new recordings, clips, tagged-voice matches, Best Quality's take choice, short bursts, Record My Voice's checks, the speaking engine, music removal's gate and pieces, and model downloads' states and Remove")
    }

    /// A synthetic take at 24 kHz: `seconds` of 0.4 s "words" (a 180 Hz tone) with 0.15 s gaps,
    /// over a steady hiss of `floor` (a fixed pseudo-random sequence). No microphone.
    static func syntheticTake(seconds: Double, floor: Float) -> [Float] {
        let rate = 24_000
        var state: UInt32 = 12_345
        return (0..<Int(seconds * Double(rate))).map { i in
            state = state &* 1_664_525 &+ 1_013_904_223
            let hiss = (Float(state >> 8) / Float(1 << 24) * 2 - 1) * floor
            let t = Double(i) / Double(rate)
            let inWord = t.truncatingRemainder(dividingBy: 0.55) < 0.4
            return hiss + (inWord ? 0.3 * Float(sin(2 * Double.pi * 180 * t)) : 0)
        }
    }

    /// Record My Voice (`OwnVoiceTake`): the passage fits one clip, Siren's sample checks on
    /// synthetic takes (too short, too noisy, clean), and the meter's and clock's arithmetic.
    static func ownVoiceTakeChecks() {
        // About 2.5 to 3 words a second read aloud: long enough to pass, short enough for one clip.
        let words = OwnVoiceTake.passage.split(whereSeparator: \.isWhitespace).count
        precondition(Double(words) / 3 >= VoiceSamples.cleanSeconds && Double(words) / 2.5 <= VoiceSamples.referenceSeconds + 2,
                     "The passage reads in about 8 to 20 s: \(words) words")
        precondition(OwnVoiceTake.maximumSeconds > Double(words) / 2, "A slow reader isn't stopped early")

        func gap(_ samples: [Float]) -> VoiceSamples.Evidence {
            let value = VoiceSamples.backgroundGapDB(samples, rate: 24_000)
            return VoiceSamples.Evidence(backgroundDB: value > 0 ? value : nil)
        }
        let clean = gap(syntheticTake(seconds: 12, floor: 0.000_5))
        let noisy = gap(syntheticTake(seconds: 12, floor: 0.08))
        precondition((clean.backgroundDB ?? 0) >= VoiceSamples.cleanBackgroundDB, "A quiet room passes: \(clean)")
        precondition((noisy.backgroundDB ?? 99) < VoiceSamples.cleanBackgroundDB, "Loud hiss fails: \(noisy)")
        precondition(OwnVoiceTake.problem(seconds: 12, evidence: clean) == nil)
        precondition(OwnVoiceTake.problem(seconds: 12, evidence: noisy) == .tooNoisy)
        precondition(OwnVoiceTake.problem(seconds: 5.4, evidence: clean) == .tooShort(seconds: 5.4))
        precondition(OwnVoiceTake.problem(seconds: 5.4, evidence: noisy) == .tooShort(seconds: 5.4), "Too short is said first")
        precondition(OwnVoiceTake.problem(seconds: 8, evidence: nil) == nil, "8 s passes; an unmeasured background counts as a pass")
        precondition(OwnVoiceTake.problem(seconds: .nan, evidence: nil) == .tooShort(seconds: 0))
        precondition(OwnVoiceTake.problem(seconds: 12, evidence: .init(backgroundDB: .nan)) == .tooNoisy)
        precondition(OwnVoiceTake.Problem.tooShort(seconds: 5.4).message.hasPrefix("Only 5 seconds"))
        for problem in [OwnVoiceTake.Problem.tooShort(seconds: 3), .tooNoisy] {
            precondition(!problem.message.contains("\n") && problem.message.count < 110, "One line: \(problem.message)")
        }

        precondition(OwnVoiceTake.level(power: -50, previous: 0) == 0)
        precondition(OwnVoiceTake.level(power: -80, previous: 0) == 0, "Under -50 dB is silence")
        precondition(abs(OwnVoiceTake.level(power: 0, previous: 0) - 0.4) < 1e-6, "Eased toward full scale")
        precondition(abs(OwnVoiceTake.level(power: 0, previous: 1) - 1) < 1e-6)
        precondition(abs(OwnVoiceTake.level(power: -.infinity, previous: 0.5) - 0.3) < 1e-6, "A silent input decays")
        precondition(OwnVoiceTake.lit(1, of: 16) == 16 && OwnVoiceTake.lit(0, of: 16) == 0 && OwnVoiceTake.lit(0.5, of: 4) == 2)
        precondition(OwnVoiceTake.lit(2, of: 4) == 4 && OwnVoiceTake.lit(.nan, of: 4) == 0 && OwnVoiceTake.lit(0.5, of: 0) == 0)
        precondition(OwnVoiceTake.clock(0) == "0:00" && OwnVoiceTake.clock(7.9) == "0:07" && OwnVoiceTake.clock(65) == "1:05")
        precondition(OwnVoiceTake.clock(-3) == "0:00" && OwnVoiceTake.clock(.infinity) == "0:00")
    }
}
