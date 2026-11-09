import Foundation

/// A voice's clips (its reference samples) and how they're used, Siren-style: each clip can be
/// included or left out, and each reading copies one included clip of its delivery, picked Siren's
/// way (`reference`): the one you Use First, else the clip most surely them that passes the sample
/// checks and is cleanest. Pure, so `Scripts/check-voices.sh` checks it. Also where people found
/// in a new recording join a voice they already are (complete link, as `VoiceGrouping`).
enum VoiceSamples {
    /// One clip of a voice, kept in its folder as `file`.
    struct Sample: Codable, Equatable, Identifiable, Sendable {
        /// The file name in the voice's folder (clip.wav, soft.wav and upbeat.wav for voices saved before 4.02).
        let file: String
        let transcript: String
        let seconds: Double
        var delivery: VoiceDelivery
        var included: Bool
        /// The person's fingerprint in the recording it was cut from; nil when unknown.
        var fingerprint: [Float]?
        /// The recording it came from (`VoiceRecording.id`), and its name to show; nil for earlier ones.
        var recording: UUID?
        var recordingName: String?
        /// What was measured of the clip for choosing it; nil until measured (at sorting, or for
        /// clips from earlier versions the first time the voice reads).
        var evidence: Evidence?
        /// Use First: true, its delivery always reads this clip while it's included; false after
        /// Choose Automatically (a choice made, so nothing is inferred again); nil never chosen.
        var pinned: Bool?

        var id: String { file }
    }

    /// What a clip's choice rests on (Siren's `StyleClip` evidence). Each is nil when unknown.
    struct Evidence: Codable, Equatable, Sendable {
        /// How far its speech sits above its background, in dB (`backgroundGapDB`).
        var backgroundDB: Double?
        /// Its own fingerprint's likeness to the person's.
        var likeness: Double?
        /// The longest quiet between two words, in seconds; a joined clip's joins count too.
        var longestPause: Double?
        /// Short bursts joined into one clip.
        var joined: Bool?
        /// Its fitness as a reference (`ReferenceFitness`, 0 to 1).
        var quality: Double?
        /// The check that it's only them, or noise reduction, didn't run as usual.
        var fellBack: Bool?
    }

    /// The longest reference the engines take (`ReferenceBuilder.maximumSeconds`).
    static let referenceSeconds = 20.0

    /// The clip a delivery reads, as an index into `samples` (Siren's `clip(for:)`): an included
    /// clip of it you chose with Use First, else the preferred included clip of it
    /// (`isPreferred`), else Natural's choice. A clip measured as unlike the person (likeness under
    /// `sameLikeness`) gives way to one measured as them, whatever its delivery. Falls back to the
    /// first included clip, then the first clip, so a voice always reads; nil only without clips.
    static func reference(_ samples: [Sample], for delivery: VoiceDelivery) -> Int? {
        let included = samples.indices.filter { samples[$0].included }
        func pinned(_ kind: VoiceDelivery) -> Int? {
            included.first { samples[$0].delivery == kind && samples[$0].pinned == true }
        }
        func preferred(_ indices: [Int]) -> Int? {
            indices.reduce(nil as Int?) { best, index in
                guard let best else { return index }
                return isPreferred(samples[index], over: samples[best]) ? index : best
            }
        }
        if let chosen = pinned(delivery) { return chosen }
        let naturalChoice = pinned(.natural)
        let requested = preferred(included.filter { samples[$0].delivery == delivery })
        if requested == nil, let naturalChoice { return naturalChoice }
        guard let proposed = requested ?? preferred(included.filter { samples[$0].delivery == .natural }) ?? preferred(included)
        else { return samples.isEmpty ? nil : 0 }
        guard isMismatch(samples[proposed]) else { return proposed }
        let compatible = included.filter { isCompatible(samples[$0]) }
        return preferred(compatible.filter { samples[$0].delivery == delivery })
            ?? naturalChoice.flatMap { isCompatible(samples[$0]) ? $0 : nil }
            ?? preferred(compatible.filter { samples[$0].delivery == .natural })
            ?? preferred(compatible)
            ?? proposed
    }

    // MARK: Siren's reference ordering

    /// A clip measured under this likeness to the person isn't surely them (Siren's 0.60).
    static let sameLikeness = 0.60
    /// The sample checks: speech this far above its background, one stretch this long, and no
    /// quiet between words longer than this (Siren's).
    static let cleanBackgroundDB = 20.0
    static let cleanSeconds = 8.0
    static let longestCleanPause = 0.6

    /// Siren's `shouldPreferReference`: identity safety first (a clip that fell back or is
    /// measured as unlike them comes last), then the sample checks (`passesChecks`), then how
    /// complete the evidence is, then a fixed utility (likeness less bounded penalties for
    /// background, fitness and a very short clip), then fitness, likeness and background. Of
    /// equals, the earlier clip (the caller's order).
    static func isPreferred(_ candidate: Sample, over current: Sample) -> Bool {
        for (a, b) in zip(keys(candidate), keys(current)) where a != b { return a > b }
        return false
    }

    /// The engines copy everything in a clip: its noise, its pauses, the joins of joined bursts.
    /// A clip that passes these comes before any that doesn't: speech `cleanBackgroundDB` above
    /// its background, one stretch (not joined) of `cleanSeconds` or more, no pause between words
    /// over `longestCleanPause`. What wasn't measured counts as a pass, so older clips aren't
    /// pushed down for lacking it; nothing is excluded.
    static func passesChecks(_ sample: Sample) -> Bool {
        let evidence = sample.evidence
        if let background = evidence?.backgroundDB, !(background.isFinite && background >= cleanBackgroundDB) { return false }
        if evidence?.joined == true { return false }
        if !(sample.seconds.isFinite && sample.seconds >= cleanSeconds) { return false }
        if let pause = evidence?.longestPause, !(pause.isFinite && pause <= longestCleanPause) { return false }
        return true
    }

    private static func likeness(_ sample: Sample) -> Double? {
        sample.evidence?.likeness.flatMap { $0.isFinite && (-1...1).contains($0) ? $0 : nil }
    }

    private static func background(_ sample: Sample) -> Double? {
        sample.evidence?.backgroundDB.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private static func isMismatch(_ sample: Sample) -> Bool { likeness(sample).map { $0 < sameLikeness } == true }

    private static func isCompatible(_ sample: Sample) -> Bool {
        sample.evidence?.fellBack != true && likeness(sample).map { $0 >= sameLikeness } == true
    }

    private static func isWeak(_ sample: Sample) -> Bool { sample.evidence?.fellBack == true || isMismatch(sample) }

    private static func keys(_ sample: Sample) -> [Double] {
        let weak = isWeak(sample)
        let evidenceClass: Double = weak ? 0 : sample.evidence?.fellBack == false && likeness(sample) != nil && background(sample) != nil ? 2 : 1
        let quality: Double
        if let value = sample.evidence?.quality { quality = value.isFinite && (0...1).contains(value) ? value : -1 } else { quality = .infinity }
        return [weak ? 0 : 1, passesChecks(sample) ? 1 : 0, evidenceClass, utility(sample), quality,
                likeness(sample) ?? -2, background(sample) ?? -1]
    }

    /// Siren's `referenceUtility`: likeness (-2 when unknown) less up to 0.04 for background under
    /// 50 dB, up to 0.10 for fitness under 0.8, and up to 0.06 for a clip under 4 s.
    private static func utility(_ sample: Sample) -> Double {
        let backgroundPenalty: Double
        if let value = background(sample) { backgroundPenalty = min(0.04, max(0, 50 - value) * 0.002) }
        else { backgroundPenalty = sample.evidence?.backgroundDB == nil ? 0 : 0.04 }
        let fitnessPenalty: Double
        if let quality = sample.evidence?.quality {
            fitnessPenalty = quality.isFinite && (0...1).contains(quality) ? min(0.10, max(0, 0.80 - quality) * 0.25) : 0.10
        } else {
            fitnessPenalty = 0
        }
        let contextPenalty = sample.seconds.isFinite && sample.seconds > 0 ? min(0.06, max(0, 4 - sample.seconds) * 0.015) : 0.06
        return (likeness(sample) ?? -2) - backgroundPenalty - fitnessPenalty - contextPenalty
    }

    // MARK: Measuring a clip (for clips from earlier versions; sorting measures its own)

    /// How far the background (10th percentile of 20 ms frame levels, the gaps between words)
    /// sits under the speech (90th percentile), in dB (`ReferenceChoice.backgroundGapDB`). Larger
    /// is cleaner; 0 for silence or a clip too short to tell.
    static func backgroundGapDB(_ samples: [Float], rate: Int) -> Double {
        let levels = frameLevels(samples, rate: rate).sorted()
        guard levels.count >= 10 else { return 0 }
        let speech = levels[levels.count * 9 / 10], background = levels[levels.count / 10]
        guard speech > 0.000_01 else { return 0 }
        return 20 * log10(speech / max(background, 0.000_001))
    }

    /// The longest quiet inside a clip, first sound to last, in seconds: 20 ms frames more than
    /// 20 dB under its speech (90th percentile). Clips from earlier versions have no word timings, so
    /// this stands in for the longest pause between words.
    static func longestQuiet(_ samples: [Float], rate: Int) -> Double {
        let levels = frameLevels(samples, rate: rate)
        guard levels.count >= 10 else { return 0 }
        let speech = levels.sorted()[levels.count * 9 / 10]
        guard speech > 0.000_01 else { return 0 }
        let quiet = speech * 0.1
        guard let first = levels.firstIndex(where: { $0 > quiet }), let last = levels.lastIndex(where: { $0 > quiet }) else { return 0 }
        var longest = 0, run = 0
        for level in levels[first...last] {
            run = level <= quiet ? run + 1 : 0
            longest = max(longest, run)
        }
        return Double(longest) * 0.02
    }

    /// Whether a clip holds a run of exact silence at least a fifth of a second long inside it:
    /// the joins short bursts were joined with (`VoiceBursts.pause`); a recording never has one.
    static func looksJoined(_ samples: [Float], rate: Int) -> Bool {
        let needed = max(1, rate / 5)
        guard let first = samples.firstIndex(where: { $0 != 0 }), let last = samples.lastIndex(where: { $0 != 0 }) else { return false }
        var run = 0
        for sample in samples[first...last] {
            run = sample == 0 ? run + 1 : 0
            if run >= needed { return true }
        }
        return false
    }

    private static func frameLevels(_ samples: [Float], rate: Int) -> [Double] {
        let frame = max(1, rate / 50)
        guard samples.count >= frame else { return [] }
        return stride(from: 0, to: samples.count - frame + 1, by: frame).map { start in
            var power = 0.0
            for i in start..<(start + frame) { power += Double(samples[i]) * Double(samples[i]) }
            return (power / Double(frame)).squareRoot()
        }
    }

    /// A voice from an earlier version whose first clip was moved there with Use First (it's Natural, and
    /// another Natural clip of it came from a recording brought in earlier): that clip, to keep as
    /// the one it reads. Nil when nothing shows a choice was made, once a choice was made since,
    /// or once the first clip is measured.
    static func inferredPin(_ samples: [Sample], added: [UUID: Date]) -> Int? {
        guard !samples.contains(where: { $0.pinned != nil }),
              let first = samples.first, first.evidence == nil, first.included, first.delivery == .natural,
              let firstAdded = first.recording.flatMap({ added[$0] }) else { return nil }
        let earlier = samples.dropFirst().contains { sample in
            sample.delivery == .natural && sample.recording.flatMap { added[$0] }.map { $0 < firstAdded } == true
        }
        return earlier ? 0 : nil
    }

    /// The deliveries a voice can read: Natural, then each with an included clip.
    static func deliveries(_ samples: [Sample]) -> [VoiceDelivery] {
        [.natural] + VoiceDelivery.allCases.filter { kind in kind != .natural && samples.contains { $0.included && $0.delivery == kind } }
    }

    /// Whether a clip can be left out: never the last included Natural clip.
    static func canExclude(_ samples: [Sample], at index: Int) -> Bool {
        guard samples.indices.contains(index), samples[index].included else { return false }
        guard samples[index].delivery == .natural else { return true }
        return samples.enumerated().contains { $0.offset != index && $0.element.included && $0.element.delivery == .natural }
    }

    /// The voice's fingerprint: its clips' fingerprints weighted by length.
    static func fingerprint(_ samples: [Sample]) -> [Float]? {
        VoiceGrouping.average(samples.compactMap { sample in sample.fingerprint.map { ($0, sample.seconds) } })
    }

    /// A voice as the joining sees it: its id and its clips' recordings and fingerprints.
    struct Candidate: Sendable {
        let id: String
        let samples: [(recording: UUID?, fingerprint: [Float]?)]
    }

    /// The voice a person found in `recording` already is: every fingerprinted clip of it at least
    /// `VoiceGrouping.sameAcrossRecordings` alike (complete link), never a voice with a clip from
    /// the same recording (the recording already told them apart), the most alike when several.
    /// Nil without a usable fingerprint.
    static func joining(_ fingerprint: [Float]?, recording: UUID, among voices: [Candidate]) -> String? {
        guard let fingerprint, VoiceGrouping.isUsable(fingerprint) else { return nil }
        var best: (id: String, score: Double)?
        for voice in voices {
            guard !voice.samples.contains(where: { $0.recording == recording }) else { continue }
            let scores = voice.samples.compactMap(\.fingerprint).filter(VoiceGrouping.isUsable).map { VoiceGrouping.similarity(fingerprint, $0) }
            guard let worst = scores.min(), worst >= VoiceGrouping.sameAcrossRecordings else { continue }
            if best.map({ worst > $0.score }) ?? true { best = (voice.id, worst) }
        }
        return best?.id
    }

    /// Below joining but this alike, a voice is offered as "Sounds like" with Same Person.
    static let soundsAlike = 0.6

    /// The other voice a voice most sounds like, at `soundsAlike` or more (by their fingerprints).
    static func soundsLike(_ fingerprint: [Float]?, among voices: [(id: String, fingerprint: [Float]?)]) -> String? {
        guard let fingerprint, VoiceGrouping.isUsable(fingerprint) else { return nil }
        let scored = voices.compactMap { voice in voice.fingerprint.flatMap { VoiceGrouping.isUsable($0) ? (voice.id, VoiceGrouping.similarity(fingerprint, $0)) : nil } }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= soundsAlike else { return nil }
        return best.0
    }

    /// `incoming` added to `samples` (Same Person, or joining): left out while `keepReading` (an
    /// approved voice keeps reading as it did until you include them), else as they were.
    static func combined(_ samples: [Sample], with incoming: [Sample], keepReading: Bool) -> [Sample] {
        samples + incoming.map { sample in
            var sample = sample
            if keepReading { sample.included = false }
            return sample
        }
    }

    /// A person's clips ranked at sorting (Siren's `likenessRanks`): each clip's `score` plus half
    /// of how much more it sounds like them (`likeness`, its fingerprint against theirs) than the
    /// typical clip, so only the differences count. An unmeasured clip counts as typical; with
    /// nothing measured, the scores as they are.
    static func likenessRanks(_ scores: [Double], likeness: [Double?]) -> [Double] {
        let measured = likeness.compactMap { $0 }.filter(\.isFinite).sorted()
        let typical = measured.dropFirst(measured.count / 2).first ?? 0
        return scores.indices.map { index in
            let alike = index < likeness.count ? likeness[index].flatMap { $0.isFinite ? $0 : nil } : nil
            return scores[index] + 0.5 * ((alike ?? typical) - typical)
        }
    }

    /// Up to `limit` of a person's stretches to transcribe, from several recordings (each list
    /// best first, the recordings most heard first): every recording's best, then the best of the
    /// rest by `isBetter`, so each recording is heard and the bound holds.
    static func spread<T>(_ perRecording: [[T]], limit: Int, isBetter: (T, T) -> Bool) -> [T] {
        guard limit > 0 else { return [] }
        let firsts = perRecording.compactMap(\.first)
        let rest = perRecording.flatMap { $0.dropFirst() }.sorted(by: isBetter)
        return Array((firsts + rest).prefix(limit))
    }

    /// Use First: the clip included, pinned for its delivery (no other clip of it is), and moved
    /// to the front of the list.
    static func pinnedFirst(_ samples: [Sample], at index: Int) -> [Sample] {
        guard samples.indices.contains(index) else { return samples }
        var samples = samples
        let delivery = samples[index].delivery
        for other in samples.indices where samples[other].delivery == delivery { samples[other].pinned = nil }
        samples[index].pinned = true
        samples[index].included = true
        let sample = samples.remove(at: index)
        samples.insert(sample, at: 0)
        return samples
    }

    /// Choose Automatically: the clip's delivery goes back to the preferred clip.
    static func unpinned(_ samples: [Sample], at index: Int) -> [Sample] {
        guard samples.indices.contains(index) else { return samples }
        var samples = samples
        samples[index].pinned = false
        return samples
    }
}
