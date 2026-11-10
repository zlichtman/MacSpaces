import AVFoundation
import Foundation
import MLXAudioCore

/// Dropped recordings in, people out. Each recording is analysed for who talks when
/// (`SourceProcessor`), the people are sorted across recordings (`VoiceGrouping`), and each
/// person's cleanest stretch is cut on word boundaries with what it says (`ReferenceBuilder`):
/// the clip a voice made from them copies. The recordings are only read. Their decoded copies
/// are deleted once the clips are made, so only the clips stay.
///
/// Siren's import, simplified: a clip per person from the stretches that sound most like them
/// and least like anyone else, ranked on how much each clip still sounds like them
/// (`VoiceSamples.likenessRanks`), Siren's short bursts joined when none is long enough
/// (`VoiceBursts`), Siren's music removal (when downloaded) and light noise reduction kept only
/// where they leave them as much like themselves (`ReferenceChoice`), and Siren's Slow and Soft and
/// Upbeat deliveries from the other clear stretches when at least three differ.
actor VoiceSorter {
    /// People worth offering from one drop, most heard first.
    static let maximumPeople = 8
    /// Stretches transcribed per person to find the clearest (Siren's `maximumCandidates`);
    /// transcription is the slow part.
    static let maximumCandidates = 10
    /// Recordings a person's stretches are looked for in, those they're heard most in first.
    static let maximumRecordingsPerPerson = 8
    static let maximumWindows = 10

    /// One of a person's clips as it's made: the clip, its score (fitness plus small bonuses for
    /// being checked and clear of the background), where it came from, and what was measured.
    private struct Made {
        var clip: ReferenceBuilder.Result
        var score: Double
        var piece: VoiceBursts.Piece
        var checked: Bool
        /// Noise reduction was meant to run on it but failed, so it's the recording as it was.
        var cleanupFailed = false
        var joined = false
        /// Likeness of the clip's own fingerprint to the person's.
        var likeness: Double?
    }

    private typealias Window = (window: (start: Double, end: Double), checked: Bool, gapDB: Double)

    private let store: VoiceModelStore
    private let processor: SourceProcessor

    init(store: VoiceModelStore) {
        self.store = store
        processor = SourceProcessor(store: store)
    }

    func sort(_ request: VoiceHelperMessage.SortRequest,
              progress: @escaping @Sendable (String, Double) -> Void) async throws -> VoiceHelperMessage.SortResult {
        guard store.state(of: .sorting).isDownloaded else { throw SourceProcessor.Failure.modelsUnavailable }
        let fm = FileManager.default
        let output = URL(fileURLWithPath: request.output, isDirectory: true)
        try? fm.removeItem(at: output)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        var analyses: [(file: URL, analysis: SourceAnalysis)] = []
        var skipped: [String] = []
        let files = request.files.map { URL(fileURLWithPath: $0) }
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let work = output.appendingPathComponent("recording-\(index)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let share = 0.7 / Double(files.count), base = Double(index) * share
            do {
                let analysis = try await processor.analyze(file, workDirectory: work) { stage, fraction in
                    let name = stage == .reading ? "Reading" : "Finding who's speaking"
                    progress(files.count > 1 ? "\(name) in \(file.lastPathComponent)" : name, base + share * (fraction ?? 0.5))
                }
                analyses.append((file, analysis))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skipped.append(file.lastPathComponent + ": " + error.localizedDescription)
            }
        }
        defer {
            for index in files.indices { try? fm.removeItem(at: output.appendingPathComponent("recording-\(index)")) }
        }

        var members: [VoiceGrouping.Member] = []
        var tracks: [(recording: Int, track: SpeakerTrack)] = []
        for (recording, entry) in analyses.enumerated() {
            for track in entry.analysis.speakers where track.kind == .talk {
                members.append(.init(recording: recording, person: track.index, seconds: track.seconds, fingerprint: track.fingerprint))
                tracks.append((recording, track))
            }
        }
        let groups = Array(VoiceGrouping.groups(members).prefix(Self.maximumPeople))
        var people: [VoiceHelperMessage.Person] = []
        for (number, group) in groups.enumerated() {
            try Task.checkCancellation()
            progress("Finding each person's clearest stretch", 0.7 + 0.3 * Double(number) / Double(max(1, groups.count)))
            let heard = group.reduce(0) { $0 + members[$1].seconds }
            let main = group.max { members[$0].seconds < members[$1].seconds }!
            var made: [Made] = []
            var unheard = true
            // Their stretches in every recording they're heard in (bounded), each recording's
            // cleanest first, then the cleanest of the rest, up to `maximumCandidates` transcribed.
            var found: [[(recording: Int, pick: Window)]] = []
            for index in group.sorted(by: { members[$0].seconds > members[$1].seconds }).prefix(Self.maximumRecordingsPerPerson) {
                let (recording, track) = tracks[index]
                found.append(try await candidates(for: track, in: analyses[recording].analysis).map { (recording, $0) })
            }
            let chosen = VoiceSamples.spread(found, limit: Self.maximumCandidates) { Self.isCleaner($0.pick, than: $1.pick) }
            let person = VoiceGrouping.average(group.compactMap { i in members[i].fingerprint.map { ($0, members[i].seconds) } })
            // Siren's cleaning on just these stretches, one recording at a time (each model loads
            // once per recording, SAM-Audio let go before DeepFilterNet, both before transcribing):
            // music taken out where there is music (with Music removal downloaded), then light
            // noise reduction. An improvement, never a requirement: without the models, or if it
            // fails, the recording is used as it is.
            let cleanFolder = output.appendingPathComponent("clean-\(number)", isDirectory: true)
            defer { try? fm.removeItem(at: cleanFolder) }
            var cleaned: [Int: URL] = [:]
            var cleanupFailed = false
            if await processor.canClean {
                let at = 0.7 + 0.3 * Double(number) / Double(max(1, groups.count))
                progress("Reducing background noise", at)
                for recording in Set(chosen.map(\.recording)).sorted() {
                    let indices = chosen.indices.filter { chosen[$0].recording == recording }
                    do {
                        let files = try await processor.clean(analyses[recording].analysis.audio,
                                                              windows: indices.map { chosen[$0].pick.window },
                                                              workDirectory: cleanFolder) { stage in
                            progress(stage == .removingMusic ? "Removing music" : "Reducing background noise", at)
                        }
                        for (index, file) in zip(indices, files) { cleaned[index] = file?.file }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        cleanupFailed = true
                    }
                }
                progress("Finding each person's clearest stretch", 0.7 + 0.3 * Double(number) / Double(max(1, groups.count)))
            }
            for (index, (recording, pick)) in chosen.enumerated() {
                do {
                    try Task.checkCancellation()
                    let audio = analyses[recording].analysis.audio
                    var clip: ReferenceBuilder.Result
                    var likeness: Double?
                    if let file = cleaned[index] {
                        clip = try await ReferenceBuilder.build(from: file)
                        clip.excerpt = clip.excerpt.map { ($0.lowerBound + pick.window.start)...($0.upperBound + pick.window.start) }
                        // The cleaned clip is kept only when it's still as much like them (`ReferenceChoice`).
                        if let person, let range = clip.excerpt {
                            (clip, likeness) = await original(for: clip, range: range, audio: audio, person: person)
                        }
                    } else {
                        clip = try await ReferenceBuilder.build(from: audio, start: pick.window.start, end: pick.window.end)
                    }
                    unheard = false
                    // Clear of the background and checked to be only them counts for a little.
                    let score = clip.qualityScore + (pick.checked ? 0.05 : 0) + min(0.05, pick.gapDB / 600)
                    made.append(Made(clip: clip, score: score,
                                     piece: .init(recording: recording, start: clip.excerpt?.lowerBound ?? pick.window.start,
                                                  seconds: clip.seconds),
                                     checked: pick.checked, cleanupFailed: cleanupFailed && cleaned[index] == nil,
                                     likeness: likeness))
                } catch is CancellationError {
                    for entry in made { try? fm.removeItem(at: entry.clip.file) }
                    throw CancellationError()
                } catch let failure as ReferenceBuilder.Failure where failure == .recognitionDenied || failure == .recognitionUnavailable {
                    for entry in made { try? fm.removeItem(at: entry.clip.file) }
                    throw failure
                } catch {
                    continue
                }
            }
            // Someone who only speaks in short bursts: their clips joined into longer ones (Siren's).
            let joinedBursts = VoiceBursts.needsJoining(made.map(\.piece))
            if joinedBursts {
                do {
                    made = try joinBursts(made)
                } catch {
                    for entry in made { try? fm.removeItem(at: entry.clip.file) }
                    throw error
                }
            }
            // How much each clip still sounds like them (Siren's `likenessRanks`): the clip's own
            // fingerprint against the person's across their recordings (already measured for a
            // cleaned clip).
            if let person {
                for index in made.indices where made[index].likeness == nil {
                    do {
                        try Task.checkCancellation()
                        if let print = try await processor.fingerprint(of: made[index].clip.file) {
                            made[index].likeness = Double(SourceProcessor.similarity(person, print))
                        }
                    } catch is CancellationError {
                        for entry in made { try? fm.removeItem(at: entry.clip.file) }
                        throw CancellationError()
                    } catch {}
                }
            }
            let ranks = VoiceSamples.likenessRanks(made.map(\.score), likeness: made.map(\.likeness))
            // The best is their clip; with enough clear stretches that differ, Siren's deliveries too.
            let picks = VoiceDelivery.pick(made.indices.map { index in
                let entry = made[index]
                return VoiceDelivery.Candidate(score: ranks[index], words: entry.clip.transcript.split(whereSeparator: \.isWhitespace).count,
                                        seconds: entry.clip.seconds, loudness: entry.clip.sourceLoudness,
                                        liveliness: entry.clip.sourceLiveliness)
            })
            defer {
                for (index, entry) in made.enumerated() where !picks.values.contains(index) { try? fm.removeItem(at: entry.clip.file) }
            }
            guard let natural = picks[.natural] else {
                skipped.append("\(label(for: tracks[main].track, number: number, single: analyses.count == 1)): " +
                               (unheard ? "no words could be heard in their stretches." : "no clear stretch was found."))
                continue
            }
            let best = made[natural]
            // What a voice's reference choice rests on (`VoiceSamples.reference`), measured now.
            func evidence(_ entry: Made) -> VoiceSamples.Evidence {
                let samples = (try? ReferenceBuilder.decode(entry.clip.file, seconds: ReferenceBuilder.maximumSeconds + 1)) ?? []
                let gap = ReferenceChoice.backgroundGapDB(samples, rate: ReferenceBuilder.sampleRate)
                return .init(backgroundDB: gap > 0 ? gap : nil, likeness: entry.likeness, longestPause: entry.clip.longestPause,
                             joined: entry.joined, quality: entry.clip.qualityScore,
                             fellBack: !entry.checked || entry.cleanupFailed)
            }
            let clip = output.appendingPathComponent("person-\(number).wav")
            let bestEvidence = evidence(best)
            try? fm.removeItem(at: clip)
            try fm.moveItem(at: best.clip.file, to: clip)
            var deliveries: [VoiceDelivery.Clip] = []
            for delivery in [VoiceDelivery.soft, .upbeat] {
                guard let index = picks[delivery] else { continue }
                let file = output.appendingPathComponent("person-\(number)-\(delivery.rawValue).wav")
                try? fm.removeItem(at: file)
                let measured = evidence(made[index])
                guard (try? fm.moveItem(at: made[index].clip.file, to: file)) != nil else { continue }
                deliveries.append(.init(delivery: delivery, file: file.path, transcript: made[index].clip.transcript,
                                        seconds: made[index].clip.seconds, evidence: measured))
            }
            var notes: [String] = []
            if heard < 30 {
                notes.append("About \(Int(heard.rounded())) seconds of them talking were found; a longer recording may sound more like them.")
            }
            if joinedBursts { notes.append("They spoke in short bursts, so their clip joins several together.") }
            if best.clip.seconds < 6 { notes.append("Their clearest stretch is short.") }
            let partial = Set(group.map { members[$0].recording }).sorted()
                .filter { analyses[$0].analysis.readableUntil != nil }.map { analyses[$0].file.lastPathComponent }
            if !partial.isEmpty { notes.append(partial.joined(separator: ", ") + " could only be read part of the way.") }
            people.append(.init(id: number, label: label(for: tracks[main].track, number: number, single: analyses.count == 1),
                                seconds: heard, recordings: Set(group.map { members[$0].recording }).count,
                                clip: clip.path, transcript: best.clip.transcript,
                                fingerprint: person,
                                note: notes.isEmpty ? nil : notes.joined(separator: " "),
                                deliveries: deliveries.isEmpty ? nil : deliveries, evidence: bestEvidence))
        }
        progress("Done", 1)
        return .init(people: people, skipped: skipped)
    }

    // MARK: Record My Voice

    /// Record My Voice's take made into a clip the way `sort` makes a person's: decoded to 24 kHz
    /// mono, fingerprinted, Siren's light noise reduction over all of it when DeepFilterNet is
    /// downloaded (the take as it was kept instead when that's clearly more like them,
    /// `original(for:)`), cut on word boundaries with what it says (`ReferenceBuilder.build(from:script:)`,
    /// which never puts the passage in place of words it couldn't hear), then measured for the
    /// sample checks. Only the clip is left in `output`; the app judges it (`OwnVoiceTake.problem`).
    func prepareTake(_ request: VoiceHelperMessage.TakeRequest,
                     progress: @escaping @Sendable (String, Double) -> Void) async throws -> VoiceHelperMessage.Person {
        guard store.state(of: .sorting).isDownloaded else { throw SourceProcessor.Failure.modelsUnavailable }
        let fm = FileManager.default
        let output = URL(fileURLWithPath: request.output, isDirectory: true)
        try? fm.removeItem(at: output)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let work = output.appendingPathComponent("work", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        progress("Reading", 0.05)
        let rate = ReferenceBuilder.sampleRate
        let samples = try ReferenceBuilder.decode(URL(fileURLWithPath: request.file), seconds: OwnVoiceTake.maximumSeconds + 5)
        let duration = Double(samples.count) / Double(rate)
        guard duration >= ReferenceBuilder.minimumSeconds else { throw ReferenceBuilder.Failure.tooShort }
        let audio = work.appendingPathComponent("take.wav")
        try AudioUtils.writeWavFile(samples: samples, sampleRate: rate, fileURL: audio)

        try Task.checkCancellation()
        progress("Listening to your voice", 0.15)
        let person = try? await processor.fingerprint(of: audio)
        try Task.checkCancellation()

        var cleaned: URL?
        var cleanupFailed = false
        if await processor.canReduceNoise {
            progress("Reducing background noise", 0.3)
            do {
                cleaned = try await processor.clean(audio, windows: [(0, duration)], workDirectory: work).first??.file
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                cleanupFailed = true
            }
        }

        progress("Writing down what you said", 0.55)
        var clip: ReferenceBuilder.Result
        var likeness: Double?
        if let cleaned {
            clip = try await ReferenceBuilder.build(from: cleaned, script: request.script)
            if let person, let range = clip.excerpt {
                (clip, likeness) = await original(for: clip, range: range, audio: audio, person: person)
            }
        } else {
            clip = try await ReferenceBuilder.build(from: audio, script: request.script)
        }
        do {
            try Task.checkCancellation()
            progress("Checking the clip", 0.85)
            if likeness == nil, let person, let print = try? await processor.fingerprint(of: clip.file) {
                likeness = Double(SourceProcessor.similarity(person, print))
            }
            try Task.checkCancellation()
            let measured = (try? ReferenceBuilder.decode(clip.file, seconds: ReferenceBuilder.maximumSeconds + 1)) ?? []
            let gap = ReferenceChoice.backgroundGapDB(measured, rate: rate)
            let evidence = VoiceSamples.Evidence(backgroundDB: gap > 0 ? gap : nil, likeness: likeness, longestPause: clip.longestPause,
                                                 joined: false, quality: clip.qualityScore, fellBack: cleanupFailed)
            let file = output.appendingPathComponent("clip.wav")
            try? fm.removeItem(at: file)
            try fm.moveItem(at: clip.file, to: file)
            progress("Done", 1)
            return .init(id: 0, label: OwnVoiceTake.name, seconds: duration, recordings: 1, clip: file.path,
                         transcript: clip.transcript, fingerprint: person, note: nil, evidence: evidence)
        } catch {
            try? fm.removeItem(at: clip.file)
            throw error
        }
    }

    /// A person's short clips joined as `VoiceBursts.groups` says: each joined clip scores its own
    /// fitness plus the pieces' average bonus for being clear and checked, and its pieces' files
    /// are removed. A group that can't be joined keeps its pieces as they were.
    private func joinBursts(_ made: [Made]) throws -> [Made] {
        let pieces = made.map(\.piece)
        var joined: [Made] = []
        for group in VoiceBursts.groups(pieces) {
            try Task.checkCancellation()
            guard group.count > 1 else { joined.append(made[group[0]]); continue }
            let clip: ReferenceBuilder.Result
            do {
                clip = try ReferenceBuilder.joined(group.map { made[$0].clip })
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                joined += group.map { made[$0] }
                continue
            }
            for index in group { try? FileManager.default.removeItem(at: made[index].clip.file) }
            let bonus = group.reduce(0) { $0 + made[$1].score - made[$1].clip.qualityScore } / Double(group.count)
            joined.append(Made(clip: clip, score: clip.qualityScore + bonus,
                               piece: .init(recording: pieces[group[0]].recording, start: pieces[group[0]].start, seconds: clip.seconds),
                               checked: group.allSatisfy { made[$0].checked },
                               cleanupFailed: group.contains { made[$0].cleanupFailed }, joined: true))
        }
        return joined
    }

    /// The same words cut from the recording as it was, kept instead of the cleaned `clip` when
    /// cleanup took some of the person away (Siren's `original(for:)`, `ReferenceChoice.keepsOriginal`).
    /// The words are the same, so nothing is transcribed again; the cost is one fingerprint of
    /// each. Returns the clip kept (the other's file is removed) and its likeness to `person`.
    private func original(for clip: ReferenceBuilder.Result, range: ClosedRange<Double>, audio: URL,
                          person: [Float]) async -> (ReferenceBuilder.Result, Double?) {
        guard !Task.isCancelled else { return (clip, nil) }
        guard let cleanPrint = try? await processor.fingerprint(of: clip.file) else { return (clip, nil) }
        let cleanLikeness = Double(SourceProcessor.similarity(person, cleanPrint))
        let slice = AVAudioFile.readSlice(audio, from: range.lowerBound, to: range.upperBound)
        guard Int(slice.rate) == ReferenceBuilder.sampleRate,
              var plain = try? ReferenceBuilder.reference(from: slice.samples, transcript: clip.transcript) else { return (clip, cleanLikeness) }
        guard !Task.isCancelled else { try? FileManager.default.removeItem(at: plain.file); return (clip, cleanLikeness) }
        guard let plainPrint = try? await processor.fingerprint(of: plain.file),
              let cleanSamples = try? ReferenceBuilder.decode(clip.file, seconds: ReferenceBuilder.maximumSeconds + 1) else {
            try? FileManager.default.removeItem(at: plain.file)
            return (clip, cleanLikeness)
        }
        let plainLikeness = Double(SourceProcessor.similarity(person, plainPrint))
        let rate = ReferenceBuilder.sampleRate
        guard ReferenceChoice.keepsOriginal(cleanLikeness: cleanLikeness, originalLikeness: plainLikeness,
                                            cleanGapDB: ReferenceChoice.backgroundGapDB(cleanSamples, rate: rate),
                                            originalGapDB: ReferenceChoice.backgroundGapDB(slice.samples, rate: rate)) else {
            try? FileManager.default.removeItem(at: plain.file)
            return (clip, cleanLikeness)
        }
        try? FileManager.default.removeItem(at: clip.file)
        plain.excerpt = range
        plain.longestPause = clip.longestPause
        plain.unheardSeconds = clip.unheardSeconds
        return (plain, plainLikeness)
    }

    private func label(for track: SpeakerTrack, number: Int, single: Bool) -> String {
        single && !track.label.isEmpty ? track.label : "Person \(number + 1)"
    }

    /// Their stretches in one recording worth transcribing (up to `maximumWindows`), cleanest
    /// first (`isCleaner`): up to 20 s each, without coughs, laughs or anyone else, kept to the
    /// parts that sound like them (`checkWindows`).
    private func candidates(for track: SpeakerTrack, in analysis: SourceAnalysis) async throws -> [Window] {
        let others = analysis.speakers.filter { $0.index != track.index }.flatMap(\.segments) + analysis.noises
        let speech = Stretches.excluding(analysis.noises, from: track.segments)
        let level = Stretches.speechLevel(analysis.audio, segments: track.segments)
        let background = Stretches.backgroundLevel(analysis.audio, segments: track.segments)
        let gap: (Double, Double) throws -> Double = { start, end in
            try Task.checkCancellation()
            let slice = AVAudioFile.readSlice(analysis.audio, from: start, to: end)
            return ReferenceChoice.backgroundGapDB(slice.samples, rate: Int(slice.rate))
        }
        var windows = try Stretches.windows(speech, others: others, length: analysis.seconds, count: Self.maximumWindows, gapDB: gap) { start, end in
            level.map { Stretches.isPause(analysis.audio, from: start, to: end, speechLevel: $0, background: background) } ?? true
        }
        var purity = SourceProcessor.PurityCheck.unavailable
        do {
            (windows, purity) = try await processor.checkWindows(analysis, person: track.index, windows: windows)
        } catch is CancellationError {
            throw CancellationError()
        } catch {}
        func checked(_ window: (start: Double, end: Double)) -> Bool {
            switch purity {
            case .checked: true
            case .partlyChecked(let unchecked): !unchecked.contains { $0.contains((window.start + window.end) / 2) }
            case .notApplicable, .unavailable, .keptUnchecked: false
            }
        }
        let scored = try windows.map { (window: $0, checked: checked($0), gapDB: try gap($0.start, $0.end)) }
        return scored.sorted(by: Self.isCleaner)
    }

    /// Long enough to carry the voice first, then checked to be only them, then the clearest of
    /// the background.
    private static func isCleaner(_ a: Window, than b: Window) -> Bool {
        let longA = a.window.end - a.window.start >= 6, longB = b.window.end - b.window.start >= 6
        if longA != longB { return longA }
        if a.checked != b.checked { return a.checked }
        return a.gapDB > b.gapDB
    }
}

/// Choosing a person's stretches (Siren's `SourceImporter` helpers).
enum Stretches {
    /// A little either side of a cough or laugh is cut out with it.
    static let noisePad = 0.15

    /// `segments` with every part of `cut` taken out, and `noisePad` either side.
    static func excluding(_ cut: [SpeechSegment], from segments: [SpeechSegment]) -> [SpeechSegment] {
        guard !cut.isEmpty else { return segments }
        return segments.flatMap { segment -> [SpeechSegment] in
            var pieces = [segment]
            for noise in cut {
                let lo = noise.start - noisePad, hi = noise.end + noisePad
                pieces = pieces.flatMap { piece -> [SpeechSegment] in
                    guard hi > piece.start, lo < piece.end else { return [piece] }
                    return [SpeechSegment(start: piece.start, end: lo), SpeechSegment(start: hi, end: piece.end)].filter { $0.duration > 0.3 }
                }
            }
            return pieces
        }
    }

    /// Stretches of this person talking, cut to at most 20 s and spread across the recording.
    /// Pauses of up to 1.2 s are kept inside a stretch unless someone else speaks in them or
    /// `isPause` says the gap isn't one. Long stretches are preferred; when there are few,
    /// shorter ones are used too, down to the single longest. Past `count`, each part of the
    /// recording gives its cleanest by `gapDB` (`ReferenceChoice.spread`).
    static func windows(_ segments: [SpeechSegment], others: [SpeechSegment] = [], length: Double = .infinity, count: Int,
                        gapDB: ((Double, Double) throws -> Double)? = nil,
                        isPause: (Double, Double) -> Bool = { _, _ in true }) throws -> [(start: Double, end: Double)] {
        var runs: [(start: Double, end: Double)] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = runs.last, segment.start - last.end <= 1.2,
               !others.contains(where: { $0.start < segment.start && $0.end > last.end }),
               segment.start <= last.end || isPause(last.end, segment.start) {
                runs[runs.count - 1].end = max(last.end, segment.end)
            } else {
                runs.append((segment.start, segment.end))
            }
        }
        var windows: [(start: Double, end: Double)] = []
        for run in runs {
            var start = run.start
            while run.end - start >= 6 {
                let end = min(run.end, start + 20)
                windows.append((start, end))
                start = end
            }
        }
        if windows.count < 3 {
            let short = runs.filter { $0.end - $0.start >= 1.5 && $0.end - $0.start < 6 }
                .sorted { $0.end - $0.start > $1.end - $1.start }
            windows += short.prefix(max(0, count - windows.count))
        }
        if windows.isEmpty, let longest = runs.max(by: { $0.end - $0.start < $1.end - $1.start }) {
            windows = [longest]
        }
        windows = windows.map { (max(0, $0.start), min(length, $0.end)) }.sorted { $0.start < $1.start }
        return try ReferenceChoice.spread(windows, count: count, gapDB: gapDB)
    }

    /// Typical loudness of someone's speech (median 20 ms frame level, in dB, over up to 5 s
    /// of each of their 5 longest segments). Nil if silent.
    static func speechLevel(_ audio: URL, segments: [SpeechSegment]) -> Float? {
        var levels: [Float] = []
        for segment in segments.sorted(by: { $0.duration > $1.duration }).prefix(5) {
            let slice = AVAudioFile.readSlice(audio, from: segment.start, to: min(segment.end, segment.start + 5))
            levels += frameLevels(slice.samples, rate: slice.rate).filter { $0 > -60 }
        }
        guard !levels.isEmpty else { return nil }
        levels.sort()
        return levels[levels.count / 2]
    }

    /// The steady background under their speech: the quietest moments (10th percentile of
    /// 20 ms frames) inside their longest stretches, which fall between words.
    static func backgroundLevel(_ audio: URL, segments: [SpeechSegment]) -> Float? {
        var levels: [Float] = []
        for segment in segments.sorted(by: { $0.duration > $1.duration }).prefix(5) {
            let slice = AVAudioFile.readSlice(audio, from: segment.start, to: min(segment.end, segment.start + 5))
            levels += frameLevels(slice.samples, rate: slice.rate).map { max($0, -80) }
        }
        guard levels.count >= 20 else { return nil }
        levels.sort()
        return levels[levels.count / 10]
    }

    /// A gap is a pause when even its louder moments (90th percentile of 20 ms frames) stay
    /// 15 dB under the person's typical speech, or, over steady hiss or hum, hold nothing more
    /// than that `background` (within 4 dB), and always at least 8 dB under their speech.
    static func isPause(_ audio: URL, from start: Double, to end: Double, speechLevel: Float,
                        background: Float? = nil) -> Bool {
        let slice = AVAudioFile.readSlice(audio, from: start, to: end)
        let levels = frameLevels(slice.samples, rate: slice.rate).sorted()
        guard !levels.isEmpty else { return true }
        let quiet = max(speechLevel - 15, background.map { min($0 + 4, speechLevel - 8) } ?? -.infinity)
        return levels[Int(Double(levels.count - 1) * 0.9)] <= quiet
    }

    private static func frameLevels(_ samples: [Float], rate: Double) -> [Float] {
        let frame = max(1, Int(rate / 50))
        var levels: [Float] = []
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += samples[j] * samples[j] }
            levels.append(10 * log10(max(sum / Float(frame), 1e-12)))
            i += frame
        }
        return levels
    }
}

extension AVAudioFile {
    /// One stretch of the mono analysis audio (empty if unreadable). Clamps resampling and
    /// rounding edges first: macOS 27 reports an end-of-file error for a request even one frame
    /// beyond the real file.
    static func readSlice(_ url: URL, from start: Double, to end: Double) -> (samples: [Float], rate: Double) {
        guard start.isFinite, end.isFinite, end > start,
              let file = try? AVAudioFile(forReading: url) else { return ([], 24_000) }
        defer { file.close() }
        let rate = file.processingFormat.sampleRate
        guard rate.isFinite, rate > 0, file.length > 0 else { return ([], 24_000) }
        let duration = Double(file.length) / rate
        let lower = (max(0, min(duration, start)) * rate).rounded(.down)
        let upper = (max(0, min(duration, end)) * rate).rounded(.down)
        let requested = upper - lower
        guard lower >= 0, lower < Double(Int64.max), requested > 0,
              requested <= Double(AVAudioFrameCount.max) else { return ([], rate) }
        file.framePosition = AVAudioFramePosition(lower)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(requested)),
              (try? AudioFileReader.readAvailableFrames(from: file, into: buffer)) == true,
              let data = buffer.floatChannelData else { return ([], rate) }
        return (Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))), rate)
    }
}
