import Accelerate
import AVFoundation
import Foundation
@preconcurrency import MLX
import MLXAudioCore
@preconcurrency import MLXAudioSTS
@preconcurrency import MLXAudioVAD
import MLXNN

/// A stretch of one person talking alone, in seconds on `SourceAnalysis.audio`.
struct SpeechSegment: Codable, Sendable, Equatable {
    let start: Double
    let end: Double
    var duration: Double { end - start }
}

/// Everything one person said or sang on their own.
struct SpeakerTrack: Sendable {
    enum Kind: String, Sendable { case talk, singing }

    /// Stable within one analysis. Any number of people; not in any order.
    let index: Int
    /// Total single-speaker speech (or singing).
    let seconds: Double
    /// About 5–8 s of this person alone, for "which one is this?" A singer's
    /// preview has the music taken out.
    let preview: URL
    /// On the `SourceAnalysis.audio` timeline. A singer's segments are the sung
    /// parts of their songs.
    let segments: [SpeechSegment]
    /// Speaker embedding (256 floats, L2-normalised), compared with
    /// `SourceProcessor.similarity`. Nil if the 26 MB model couldn't be downloaded.
    let fingerprint: [Float]?
    var kind: Kind = .talk
    /// What to call them: "Host 1", "Guest 2", "Singer · song at 12:40".
    var label = ""
    /// Nobody passed the bar for a person, so this is the most-heard voice or
    /// the whole recording, kept rather than giving up on the file. Who it is
    /// was never established, so nothing from it counts as checked.
    var unverified = false
}

struct SourceAnalysis: Sendable {
    /// The recording decoded to mono 24 kHz WAV, not cleaned.
    let audio: URL
    let seconds: Double
    /// Most speech first.
    let speakers: [SpeakerTrack]
    /// Where music plays (songs and beds), for showing on a timeline.
    var music: [SpeechSegment] = []
    /// Coughs, laughs, breaths and other sounds that aren't words, kept out of samples.
    var noises: [SpeechSegment] = []
    /// Set when the file stopped being readable part-way (a cut-off download,
    /// a damaged copy): `audio` holds only the recording up to this point.
    var readableUntil: Double? = nil
    /// Laughs, sighs and breaths, for the coverage map.
    var vocalSounds: [VocalSound] = []
}

enum ProcessingStage: String, Sendable {
    case reading, findingSpeakers, removingMusic, reducingNoise, done
}

/// One stretch `SourceProcessor.clean` cleaned: a 24 kHz WAV of just that stretch.
struct CleanWindow: Sendable {
    let file: URL
    /// SAM-Audio found music under the talk and it was taken out.
    let musicRemoved: Bool
}

/// Finds everyone who speaks in a recording, then cleans only the stretches sorting
/// picks. Ported from Siren's engine without its singers: a voice is made from someone
/// talking on their own. Everything runs on this Mac.
///
/// `analyze` (about 1 s per minute of audio):
/// 1. **Reading**: any AVFoundation file, decoded once to mono 24 kHz (kept) and 16 kHz (scratch).
/// 2. **Listening**: `SoundMap` marks talk, singing, music and talk over music; songs and music are left out.
/// 3. **Finding speakers**: Sortformer (NVIDIA), streamed in 10 s chunks, says who
///    talks when, but it only has four voices to hand out. So its talk is cut into
///    pieces of up to 8 s, each piece gets a WeSpeaker ResNet34 fingerprint
///    (VoxCeleb-trained, 26 MB), and the pieces are grouped by voice across the whole
///    recording the way pyannote does. Any number of people.
///
/// `checkWindows` keeps only the parts of a chosen person's stretches that sound
/// like them and not like anyone else.
///
/// `clean` (Siren's, per stretch, each step only when its model is downloaded):
/// 1. **Removing music**: only where the gaps between words are loud compared with the
///    words (`MusicRemoval`). SAM-Audio (Meta) splits "speech" from the rest, and the split
///    is used as a time-frequency mask on the original audio, so the voice keeps its own
///    detail. If SAM finds no music after all, the original audio is kept.
/// 2. **Reducing noise**: DeepFilterNet 3 everywhere, capped so it only takes the edge off.
///
/// Each model is unloaded before the next loads, MLX's buffer cache is capped while this
/// runs, and long recordings are streamed through files, never held whole. Models load
/// only from `VoiceModelStore`: nothing is downloaded here.
actor SourceProcessor {
    enum Failure: LocalizedError {
        case unreadable, tooShort, silent, notEnoughSpace(gigabytes: Int), modelsUnavailable, couldNotSave, noClearSpeech

        var errorDescription: String? {
            switch self {
            case .unreadable:
                "That file couldn't be opened. Try an audio file like .m4a, .mp3 or .wav."
            case .tooShort:
                "That recording is under a second long. Use one with at least a second of someone talking."
            case .silent:
                "That recording is silent. Check that you picked the right file."
            case .notEnoughSpace(let gigabytes):
                "Your Mac is almost out of space. Free up about \(gigabytes) GB, then try again."
            case .modelsUnavailable:
                "The speaker-sorting model isn't downloaded. Download Finding voices in Settings, Tsukumo, Voice, then try again."
            case .couldNotSave:
                "MacSpaces couldn't save the audio it was working on. Make sure your Mac has free space, then try again."
            case .noClearSpeech:
                "MacSpaces couldn't find anyone talking on their own for long enough. Try a recording where one person speaks clearly for at least a few seconds at a time."
            }
        }
    }

    // MARK: - Settings

    static let workingRate = 48_000          // decoding and resampling
    static let audioRate = 24_000            // the voice models (Qwen3-TTS, CosyVoice)
    static let diarizationRate = 16_000      // Sortformer and WeSpeaker
    /// Anything with a second of sound is worth trying. There is no upper limit:
    /// everything streams through files.
    static let minimumSeconds = 1.0

    static let fingerprintRepo = VoiceModel.fingerprintRepo
    static let diarizerRepo = VoiceModel.diarizerRepo
    static let enhancerRepo = VoiceModel.enhancerRepo
    static let separatorRepo = VoiceModel.separatorRepo
    /// ODE solver for SAM-Audio, and how many codec frames (25 a second) it decodes at once
    /// (Siren's). Its output is only used as a mask, where 4 Euler steps do as well as 16
    /// midpoint steps in under two-thirds of the time. Decoding a whole stretch at once takes
    /// over 10 GB at 48 kHz; 25 frames keeps SAM-Audio at about 3.2 GB.
    static let separationODE = SAMAudioODEOptions(method: .euler, stepSize: 1.0 / 4.0)
    static let decodeFrames = 25
    /// DeepFilterNet lowers noise by at most this much (Siren's 12 dB): it takes the edge off
    /// without the watery sound of full noise removal, which the engines would copy.
    static let noiseLimitDB: Float = 12
    /// Extra audio either side of a stretch while cleaning, trimmed off afterwards.
    static let windowContextSeconds = 1.0

    /// Talk is fingerprinted in pieces this long (longer stretches are split
    /// evenly). Shorter bits give unreliable fingerprints, so they aren't grouped
    /// by voice; they go with the person their diarization voice was nearby.
    static let pieceSeconds = (shortest: 3.0, longest: 8.0)
    /// Pieces whose groups' average fingerprints are closer than this are one
    /// person: pyannote's tuned centroid-linkage threshold for this same model
    /// (Euclidean distance between means of unit embeddings).
    static let sameVoiceDistance: Float = 0.7046
    /// How far (seconds) a short bit looks for a piece of its own diarization voice.
    static let shortBitReach = 30.0
    /// A short bit with no piece of its voice nearby joins the person it sounds
    /// most like, if at least this alike; otherwise it's left out.
    static let shortBitSimilarity: Float = 0.5
    /// A short bit at least this long is fingerprinted, and goes to whoever it
    /// clearly sounds like (at least `voicedBitSimilarity`, and `voicedBitMargin`
    /// more than its neighbour's person) rather than by when it was said.
    /// Below 3 s a fingerprint is shaky, so the bar is high.
    static let voicedBitSeconds = 1.5
    static let voicedBitSimilarity: Float = 0.6
    static let voicedBitMargin: Float = 0.2
    /// Purity check: pieces this long, this far apart, are compared with everyone.
    static let purityPiece = 1.5, purityHop = 0.5
    /// A piece is nobody's when it is less like the person than this.
    static let purityFloor: Float = 0.3
    static let purityMinimumRun = 1.5

    /// Sortformer: a speaker counts as talking above this probability.
    static let speakingThreshold: Float = 0.5
    static let frameSeconds = 0.08            // one Sortformer output frame
    static let mergeGapSeconds = 0.5          // same-speaker pauses up to this stay inside a segment
    static let minimumSegmentSeconds = 1.0
    static let edgePadSeconds = 0.08          // added either side of a segment when nobody else is talking
    static let minimumSpeakerSeconds = 3.0
    static let previewSeconds = (shortest: 5.0, longest: 8.0)
    /// Fingerprints average the speaker's longest few segments, up to 10 s each.
    static let fingerprintSegments = 4, fingerprintPieceSeconds = 10.0

    private let log: (@Sendable (String) -> Void)?
    private let store: VoiceModelStore

    /// `log` receives short diagnostic lines (timings, decisions); leave it nil in the app.
    init(store: VoiceModelStore, log: (@Sendable (String) -> Void)? = nil) {
        self.store = store
        self.log = log
    }

    // MARK: - Analyze

    func analyze(_ source: URL, workDirectory: URL,
                 progress: @escaping @Sendable (ProcessingStage, Double?) -> Void) async throws -> SourceAnalysis {
        let cacheLimit = Self.capCache()
        defer { Memory.cacheLimit = cacheLimit; Memory.clearCache() }
        let fm = FileManager.default
        let scratch = try Self.scratchDirectory(in: workDirectory)
        defer { try? fm.removeItem(at: scratch) }

        progress(.reading, 0)
        let started = ContinuousClock.now
        let audio = workDirectory.appendingPathComponent("audio.wav")
        try? fm.removeItem(at: audio)
        let wav: StreamingWAVWriter
        do { wav = try StreamingWAVWriter(url: audio, sampleRate: Double(Self.audioRate)) } catch { throw Failure.couldNotSave }
        let speechWriter = try SampleWriter(scratch.appendingPathComponent("speech16k.f32"), rate: Self.diarizationRate)
        var to24k = Decimator(factor: Self.workingRate / Self.audioRate)
        var to16k = Decimator(factor: Self.workingRate / Self.diarizationRate)
        // A damaged file is never rejected: whatever can be read is used.
        var readableUntil: Double?
        let total = try decode(source, maximumSeconds: .infinity, checkSpaceIn: workDirectory,
                               recovered: { readableUntil = $0 },
                               progress: { progress(.reading, $0) }) { block in
            do { try wav.writeChunk(to24k.process(block)) } catch { throw Failure.couldNotSave }
            try speechWriter.append(to16k.process(block))
        }
        do { try wav.writeChunk(to24k.finish()) } catch { throw Failure.couldNotSave }
        try speechWriter.append(to16k.finish())
        _ = wav.finalize()
        let speech = try speechWriter.close()
        let seconds = Double(total) / Double(Self.workingRate)
        guard seconds >= Self.minimumSeconds else { throw Failure.tooShort }
        guard speech.peak > 0.000_1 else { throw Failure.silent }
        log?(String(format: "read %.1f s in %.1f s", seconds, Self.seconds(since: started)))
        if let readableUntil { log?(String(format: "file unreadable after %.1f s; using what came before", readableUntil)) }

        progress(.findingSpeakers, nil)
        // If the classifier can't run, everything counts as talk, as before songs were found.
        let map: SoundMap
        do {
            map = try await SoundMap.analyze(audio) { progress(.findingSpeakers, 0.1 * $0) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log?("sound map unavailable: \(error)")
            map = SoundMap(kinds: [])
        }
        let found = try await diarize(speech, gain: Self.speechGain(speech), map: map) {
            progress(.findingSpeakers, 0.1 + 0.6 * $0)
        }

        let reader = try WAVReader(audio)
        let encoder = await loadSpeakerEncoder()
        for old in (try? fm.contentsOfDirectory(at: workDirectory, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("speaker-") && old.pathExtension == "wav" {
            try? fm.removeItem(at: old)
        }
        let talkers = try talkPeople(found.voices, overlap: found.together, map: map, speech: SampleReader(speech), encoder: encoder) {
            progress(.findingSpeakers, 0.7 + 0.3 * $0)
        }
        try? fm.removeItem(at: speech.url)
        var speakers: [SpeakerTrack] = []
        for (index, person) in talkers.enumerated() {
            let total = person.segments.reduce(0) { $0 + $1.duration }
            guard total >= Self.minimumSpeakerSeconds else { continue }
            let preview = Self.previewURL(index, in: workDirectory)
            try writePreview(of: person.segments, from: reader, to: preview)
            speakers.append(SpeakerTrack(index: index, seconds: total, preview: preview, segments: person.segments,
                                         fingerprint: person.fingerprint))
        }
        Self.labelTalkers(&speakers)

        if speakers.isEmpty {
            // Nobody passed the bar: keep the most-heard voice, or failing that
            // the whole recording, rather than give up on the file.
            var fallback = (index: 0, segments: [SpeechSegment(start: 0, end: seconds)])
            var most = 0.0
            for (index, segments) in found.voices {
                let total = segments.reduce(0) { $0 + $1.duration }
                if total > most { most = total; fallback = (index, segments) }
            }
            let preview = Self.previewURL(fallback.index, in: workDirectory)
            try writePreview(of: fallback.segments, from: reader, to: preview)
            let fingerprint = try encoder.flatMap { try speakerFingerprint(of: fallback.segments, from: reader, encoder: $0) }
            speakers.append(SpeakerTrack(index: fallback.index, seconds: fallback.segments.reduce(0) { $0 + $1.duration },
                                         preview: preview, segments: fallback.segments, fingerprint: fingerprint,
                                         label: "Main voice", unverified: true))
        }
        Memory.clearCache()
        speakers.sort { $0.seconds > $1.seconds }
        for speaker in speakers {
            log?(String(format: "speaker %d (%@): %.1f s in %d segments", speaker.index, speaker.label, speaker.seconds,
                        speaker.segments.count))
        }
        progress(.done, 1)
        return SourceAnalysis(audio: audio, seconds: seconds, speakers: speakers,
                              music: map.stretches(of: [.music, .singing, .talkOverMusic], bridging: 2, minimum: 3),
                              noises: map.noiseStretches(), readableUntil: readableUntil, vocalSounds: map.vocalSounds())
    }

    /// "Host 1", "Host 2" for whoever does a fifth or more of the talking
    /// (just "Host" if one person does), "Guest 1", "Guest 2" for everyone else.
    /// A recording of one person is just their "Main voice".
    private static func labelTalkers(_ speakers: inout [SpeakerTrack]) {
        if speakers.count == 1 { speakers[0].label = "Main voice"; return }
        let total = speakers.reduce(0) { $0 + $1.seconds }
        let order = speakers.indices.sorted { speakers[$0].seconds > speakers[$1].seconds }
        let hosts = order.filter { total > 0 && speakers[$0].seconds / total >= 0.2 }.prefix(3)
        var guest = 0
        for (rank, i) in order.enumerated() {
            if hosts.contains(i) {
                speakers[i].label = hosts.count == 1 ? "Host" : "Host \(rank + 1)"
            } else {
                guest += 1
                speakers[i].label = "Guest \(guest)"
            }
        }
    }

    private static func previewURL(_ index: Int, in directory: URL) -> URL {
        directory.appendingPathComponent("speaker-\(index).wav")
    }

    // MARK: - Fingerprints

    /// A fingerprint for a clip (for example one recorded in the app). Nil if the
    /// fingerprint model couldn't be downloaded or the clip has no sound.
    func fingerprint(of file: URL) async throws -> [Float]? {
        var samples: [Float] = []
        var decimator = Decimator(factor: Self.workingRate / Self.diarizationRate)
        _ = try decode(file, maximumSeconds: 120, checkSpaceIn: nil, progress: { _ in }) { block in
            samples += decimator.process(block)
        }
        samples += decimator.finish()
        guard let encoder = await loadSpeakerEncoder() else { return nil }
        defer { Memory.clearCache() }
        let piece = Int(Self.fingerprintPieceSeconds * Double(Self.diarizationRate))
        var embeddings: [[Float]] = []
        var i = 0
        while i < samples.count {
            let part = Array(samples[i..<min(i + piece, samples.count)])
            if part.count >= Self.diarizationRate, vDSP.rootMeanSquare(part) > 0.000_3 {
                embeddings.append(Self.embed(part, with: encoder))
            }
            i += piece
        }
        return embeddings.isEmpty ? nil : Self.average(embeddings)
    }

    /// A fingerprint for 24 kHz samples already in memory (a generated take).
    /// Leaves MLX's buffer cache alone: this runs right after speech generation,
    /// whose own task may still be using the GPU, and clearing then can crash Metal.
    func fingerprint(of samples: [Float]) async -> [Float]? {
        guard samples.count >= Self.audioRate / 2, let encoder = await loadSpeakerEncoder() else { return nil }
        var to16k = Decimator(factor: Self.workingRate / Self.diarizationRate)
        return Self.embed(to16k.process(Self.upsample(samples)) + to16k.finish(), with: encoder)
    }

    /// Cosine similarity of two fingerprints; 0 if they don't match in size.
    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let norms = sqrt(vDSP.sumOfSquares(a) * vDSP.sumOfSquares(b))
        return norms > 0 ? vDSP.dot(a, b) / norms : 0
    }

    private func speakerFingerprint(of segments: [SpeechSegment], from reader: WAVReader,
                                    encoder: SpeakerEncoder) throws -> [Float]? {
        let longest = segments.sorted { $0.duration > $1.duration }.prefix(Self.fingerprintSegments)
        var embeddings: [[Float]] = []
        for segment in longest {
            // The middle of the segment, away from its edges, at 16 kHz.
            let length = min(segment.duration, Self.fingerprintPieceSeconds)
            let start = segment.start + (segment.duration - length) / 2
            let samples = try reader.read(Int(start * Double(Self.audioRate))..<Int((start + length) * Double(Self.audioRate)))
            var decimator = Decimator(factor: 3)
            let at48k = Self.upsample(samples)
            embeddings.append(Self.embed(decimator.process(at48k) + decimator.finish(), with: encoder))
        }
        return embeddings.isEmpty ? nil : Self.average(embeddings)
    }

    private static func average(_ vectors: [[Float]]) -> [Float] {
        var sum = [Float](repeating: 0, count: vectors[0].count)
        for v in vectors { sum = vDSP.add(sum, normalized(v)) }
        return normalized(sum)
    }

    private static func normalized(_ v: [Float]) -> [Float] {
        let norm = sqrt(vDSP.sumOfSquares(v))
        return norm > 0 ? vDSP.divide(v, norm) : v
    }

    /// WeSpeaker embedding of mono 16 kHz audio (Kaldi fbank front end, as pyannote runs it).
    private static func embed(_ samples: [Float], with encoder: SpeakerEncoder) -> [Float] {
        let (features, frames) = KaldiFbank.features(samples)
        guard frames >= 10 else { return [Float](repeating: 0, count: 256) }
        let embedding = encoder(MLXArray(features, [1, frames, KaldiFbank.bins]))
        return normalized(embedding.reshaped([-1]).asType(.float32).asArray(Float.self))
    }

    private var speakerEncoder: SpeakerEncoder?

    /// The fingerprint model (downloads 26 MB once, then stays loaded). Nil if that isn't possible.
    private func loadSpeakerEncoder() async -> SpeakerEncoder? {
        if let speakerEncoder { return speakerEncoder }
        do {
            guard store.isWhole(Self.fingerprintRepo) else { throw Failure.modelsUnavailable }
            let directory = store.folder(for: Self.fingerprintRepo)
            let encoder = SpeakerEncoder()
            let expected = Dictionary(uniqueKeysWithValues: encoder.parameters().flattened())
            let weights = try MLX.loadArrays(url: directory.appendingPathComponent("model.safetensors"))
                .filter { expected[$0.key]?.shape == $0.value.shape }
            guard weights.count == expected.count else {
                log?("fingerprint model: \(weights.count) of \(expected.count) weights matched")
                return nil
            }
            try encoder.update(parameters: ModuleParameters.unflattened(weights), verify: .all)
            eval(encoder.parameters())
            speakerEncoder = encoder
            return encoder
        } catch {
            log?("fingerprint model unavailable: \(error)")
            return nil
        }
    }

    // MARK: - Reading

    /// Streams any file AVFoundation reads to `sink` as mono 48 kHz blocks.
    /// Returns the number of samples produced, retaining the final partial block.
    /// With `recovered`, a file damaged part-way is read up to the damage.
    private func decode(_ source: URL, maximumSeconds: Double, checkSpaceIn directory: URL?,
                        recovered: ((Double) -> Void)? = nil,
                        progress: (Double) -> Void, sink: ([Float]) throws -> Void) throws -> Int {
        guard let file = try? AVAudioFile(forReading: source), file.length > 0,
              file.processingFormat.sampleRate.isFinite, file.processingFormat.sampleRate > 0 else { throw Failure.unreadable }
        let seconds = min(Double(file.length) / file.processingFormat.sampleRate, maximumSeconds)
        file.close()
        if let directory { try Self.checkSpace(for: seconds, at: directory) }
        return try AudioFileReader.streamMono(source, sampleRate: Double(Self.workingRate), maximumSeconds: maximumSeconds,
                                              blockFrames: 32_768, quality: .max, recovered: recovered,
                                              progress: progress, sink: sink)
    }

    /// The 24 kHz audio, the 16 kHz scratch copy and the previews, with room to spare.
    private static func checkSpace(for seconds: Double, at directory: URL) throws {
        let bytes = seconds * Double(audioRate + diarizationRate) * 4 * 1.5 + 300_000_000
        guard seconds.isFinite, seconds >= 0, bytes.isFinite, bytes < Double(Int64.max) else { throw Failure.unreadable }
        let needed = Int64(bytes)
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage, available < needed {
            throw Failure.notEnoughSpace(gigabytes: Int((Double(needed) / 1e9).rounded(.up)))
        }
    }

    private static func scratchDirectory(in workDirectory: URL) throws -> URL {
        let scratch = workDirectory.appendingPathComponent(".processing-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch { throw Failure.couldNotSave }
        return scratch
    }

    /// Gain that brings active speech to about -20 dBFS without clipping.
    private static func speechGain(_ file: SampleFile) -> Float {
        let loud = file.frameRMS.filter { $0 > 0.000_1 }.sorted()
        guard !loud.isEmpty, file.peak > 0 else { return 1 }
        let top = loud[Int(Double(loud.count - 1) * 0.95)]
        let active = loud.filter { $0 > top * 0.03 }
        let rms = sqrt(active.reduce(0) { $0 + $1 * $1 } / Float(max(active.count, 1)))
        return min(0.1 / max(rms, 1e-6), 0.95 / file.peak, 30)
    }

    // MARK: - Finding speakers

    /// Sortformer starts afresh every this many 10 s chunks: it has four voices to
    /// hand out, and over an hour of hosts and callers it starts giving two people
    /// the same one. Within a few minutes there are rarely more than four;
    /// fingerprints join everyone up across the stretches. Each fresh start first
    /// hears the `diarizationLeadInChunks` before its stretch, and that output is
    /// thrown away, so it has settled by the time it counts.
    static let diarizationStretchChunks = 18
    static let diarizationLeadInChunks = 2

    /// Single-speaker segments per diarization voice. Voices are numbered per
    /// stretch (stretch * 4 + voice), so a number never spans two stretches.
    /// Songs and music are muted first: singers are found separately and
    /// shouldn't use up Sortformer's four voices.
    /// Who talks when, per diarization voice, and how many seconds each pair of
    /// voices talked at the same time (`overlap[a][b]`), which tells a person
    /// split in two (never) from two people who sound alike (sometimes).
    struct Diarization {
        var voices: [Int: [SpeechSegment]] = [:]
        var overlap: [Int: [Int: Double]] = [:]
        func together(_ a: Int, _ b: Int) -> Double { overlap[a]?[b] ?? 0 }
    }

    private func diarize(_ speech: SampleFile, gain: Float, map: SoundMap,
                         progress: (Double) -> Void) async throws -> Diarization {
        let started = ContinuousClock.now
        var model: SortformerModel? = try await load {
            guard store.isWhole(Self.diarizerRepo) else { throw Failure.modelsUnavailable }
            return try SortformerModel.fromModelDirectory(store.folder(for: Self.diarizerRepo))
        }
        defer { model = nil; Memory.clearCache() }

        // 125 output frames (10 s) per chunk. A chunk of 125 * 1280 - 160 samples
        // gives exactly 125 frames, so chunk k starts at frame 125 k with no drift.
        let frameSamples = Int(Self.frameSeconds * Double(Self.diarizationRate))  // 1280
        let chunkFrames = 125
        let speakers = 4
        let stretchFrames = chunkFrames * Self.diarizationStretchChunks
        let totalFrames = (speech.count + frameSamples - 1) / frameSamples
        let reader = try SampleReader(speech)
        var result = Diarization()
        var stretch = 0
        while stretch * stretchFrames < totalFrames {
            guard var state = model?.initStreamingState() else { throw Failure.modelsUnavailable }
            let first = stretch * stretchFrames, last = min(totalFrames, first + stretchFrames)
            var probabilities = [Float](repeating: 0, count: (last - first) * speakers)
            var frame = max(0, first - Self.diarizationLeadInChunks * chunkFrames)
            while frame < last {
                try Task.checkCancellation()
                guard let model else { throw Failure.modelsUnavailable }
                let frames = min(chunkFrames, last - frame)
                let start = frame * frameSamples
                var samples = vDSP.multiply(gain, try reader.read(start..<(start + frames * frameSamples - 160)))
                Self.muteSongs(&samples, startingAt: start, map: map)
                let (output, next) = try await model.feed(chunk: MLXArray(samples), state: state,
                                                          sampleRate: Self.diarizationRate,
                                                          threshold: Self.speakingThreshold)
                state = next
                if frame >= first, let probs = output.speakerProbs, probs.ndim == 2 {
                    let values = probs.asType(.float32).asArray(Float.self)
                    let rows = min(frames, probs.dim(0)), columns = probs.dim(1)
                    for row in 0..<rows {
                        for s in 0..<min(columns, speakers) {
                            probabilities[(frame - first + row) * speakers + s] = values[row * columns + s]
                        }
                    }
                }
                frame += frames
                progress(Double(frame) / Double(totalFrames))
            }
            let offset = Double(first) * Self.frameSeconds
            let duration = Double(last - first) * Self.frameSeconds
            for (voice, segments) in Self.speakerSegments(probabilities: probabilities, speakers: speakers, duration: duration) {
                result.voices[stretch * speakers + voice] = segments.map {
                    SpeechSegment(start: $0.start + offset, end: $0.end + offset)
                }
            }
            for frame in 0..<(last - first) {
                let talking = (0..<speakers).filter { probabilities[frame * speakers + $0] > Self.speakingThreshold }
                guard talking.count > 1 else { continue }
                for a in talking { for b in talking where b != a {
                    result.overlap[stretch * speakers + a, default: [:]][stretch * speakers + b, default: 0] += Self.frameSeconds
                } }
            }
            stretch += 1
        }
        log?(String(format: "diarized in %.1f s", Self.seconds(since: started)))
        return result
    }

    /// Silences the parts of 16 kHz `samples` (starting at sample `start`) that
    /// are songs or music on its own.
    private static func muteSongs(_ samples: inout [Float], startingAt start: Int, map: SoundMap) {
        guard !map.kinds.isEmpty else { return }
        let rate = Double(diarizationRate)
        let step = Int(SoundMap.step * rate)
        var i = 0
        while i < samples.count {
            let t = Double(start + i) / rate
            let next = min(samples.count, (Int(t / SoundMap.step) + 1) * step - start)
            if [SoundMap.Kind.singing, .music].contains(map.kind(at: t)) {
                for j in i..<max(i + 1, next) where j < samples.count { samples[j] = 0 }
            }
            i = max(i + 1, next)
        }
    }

    /// Single-speaker segments per speaker from per-frame speaker probabilities
    /// (`frames x speakers`, row-major). Frames where two or more speakers talk are
    /// dropped; same-speaker runs split only by a short silence are joined; anything
    /// shorter than `minimumSegmentSeconds` is dropped.
    static func speakerSegments(probabilities: [Float], speakers: Int, duration: Double) -> [Int: [SpeechSegment]] {
        let frames = probabilities.count / speakers
        let silence = -1, overlap = -2
        var owner = [Int](repeating: silence, count: frames)
        for f in 0..<frames {
            var talking = 0, who = silence
            for s in 0..<speakers where probabilities[f * speakers + s] > speakingThreshold {
                talking += 1
                who = s
            }
            owner[f] = talking == 0 ? silence : (talking == 1 ? who : overlap)
        }

        // Runs of frames owned by one speaker.
        var runs: [Int: [Range<Int>]] = [:]
        var f = 0
        while f < frames {
            let who = owner[f]
            var end = f + 1
            while end < frames, owner[end] == who { end += 1 }
            if who >= 0 { runs[who, default: []].append(f..<end) }
            f = end
        }

        let maxGap = Int((mergeGapSeconds / frameSeconds).rounded())
        let minFrames = Int((minimumSegmentSeconds / frameSeconds).rounded(.up))
        let pad = Int((edgePadSeconds / frameSeconds).rounded())
        var result: [Int: [SpeechSegment]] = [:]
        for (who, list) in runs {
            var merged: [Range<Int>] = []
            for run in list {
                if let last = merged.last, run.lowerBound - last.upperBound <= maxGap,
                   owner[last.upperBound..<run.lowerBound].allSatisfy({ $0 == silence }) {
                    merged[merged.count - 1] = last.lowerBound..<run.upperBound
                } else {
                    merged.append(run)
                }
            }
            let segments: [SpeechSegment] = merged.compactMap { run in
                guard run.count >= minFrames else { return nil }
                // A little silence either side, so word edges aren't clipped.
                var lo = run.lowerBound, hi = run.upperBound
                for _ in 0..<pad where lo > 0 && owner[lo - 1] == silence { lo -= 1 }
                for _ in 0..<pad where hi < frames && owner[hi] == silence { hi += 1 }
                return SpeechSegment(start: Double(lo) * frameSeconds, end: min(duration, Double(hi) * frameSeconds))
            }
            if !segments.isEmpty { result[who] = segments }
        }
        return result
    }

    // MARK: - Everyone in the recording

    /// The people talking, most first: Sortformer's talk with songs left out, cut
    /// into pieces, fingerprinted and grouped by voice. Without the fingerprint
    /// model, Sortformer's own four voices.
    private func talkPeople(_ slots: [Int: [SpeechSegment]], overlap: (Int, Int) -> Double, map: SoundMap, speech: SampleReader,
                            encoder: SpeakerEncoder?,
                            progress: (Double) -> Void) throws -> [(segments: [SpeechSegment], fingerprint: [Float]?)] {
        let started = ContinuousClock.now
        let talk = slots.mapValues { $0.flatMap { Self.withoutSongs($0, map: map) } }
        guard let encoder else {
            return talk.values.filter { !$0.isEmpty }.map { ($0, nil) }
                .sorted { $0.0.reduce(0) { $0 + $1.duration } > $1.0.reduce(0) { $0 + $1.duration } }
        }

        struct Piece { let slot: Int; let span: SpeechSegment; let vector: [Float] }
        var pieces: [Piece] = []
        var short: [(slot: Int, span: SpeechSegment)] = []
        let all = talk.flatMap { slot, segments in segments.map { (slot, $0) } }
        let rate = Double(Self.diarizationRate)
        for (n, (slot, segment)) in all.enumerated() {
            try Task.checkCancellation()
            guard segment.duration >= Self.pieceSeconds.shortest else { short.append((slot, segment)); continue }
            let count = max(1, Int((segment.duration / Self.pieceSeconds.longest).rounded(.up)))
            let length = segment.duration / Double(count)
            for k in 0..<count {
                let span = SpeechSegment(start: segment.start + Double(k) * length, end: segment.start + Double(k + 1) * length)
                let samples = try speech.read(Int(span.start * rate)..<Int(span.end * rate))
                pieces.append(Piece(slot: slot, span: span, vector: Self.embed(samples, with: encoder)))
            }
            if n % 20 == 0 { Memory.clearCache(); progress(Double(n) / Double(max(1, all.count))) }
        }
        guard !pieces.isEmpty else {
            // Nobody spoke for 3 s at a time: Sortformer's voices as they are.
            return talk.values.filter { !$0.isEmpty }.map { ($0, nil) }
        }
        let clustered = Self.cluster(pieces.map(\.vector), weights: pieces.map(\.span.duration),
                                     distance: Self.sameVoiceDistance)
        // A second look: join a person split in two, move out pieces of someone else.
        let groups = VoiceSorting.refine(pieces.map { VoiceSorting.Piece(vector: $0.vector, seconds: $0.span.duration, slot: $0.slot) },
                                         groups: clustered, overlap: overlap)
        let people = (groups.max() ?? 0) + 1
        var segments = [[SpeechSegment]](repeating: [], count: people)
        var vectors = [[([Float], Double)]](repeating: [], count: people)
        for (piece, group) in zip(pieces, groups) {
            segments[group].append(piece.span)
            vectors[group].append((piece.vector, piece.span.duration))
        }
        let centroids = vectors.map { Self.weightedAverage($0) ?? [] }
        // Short bits go with the nearest piece of the same diarization voice (Sortformer
        // is reliable about who's who within a few minutes), unless a bit long enough
        // to fingerprint clearly sounds like someone else; failing both, with whoever
        // they sound most like.
        var placed = 0
        for bit in short {
            try Task.checkCancellation()
            let nearest = pieces.indices.filter { pieces[$0].slot == bit.slot }.min {
                Self.gap(pieces[$0].span, bit.span) < Self.gap(pieces[$1].span, bit.span)
            }
            if let nearest, Self.gap(pieces[nearest].span, bit.span) <= Self.shortBitReach {
                var group = groups[nearest]
                if bit.span.duration >= Self.voicedBitSeconds {
                    let vector = Self.embed(try speech.read(Int(bit.span.start * rate)..<Int(bit.span.end * rate)), with: encoder)
                    let mine = Self.similarity(centroids[group], vector)
                    if let best = centroids.indices.max(by: { Self.similarity(centroids[$0], vector) < Self.similarity(centroids[$1], vector) }),
                       best != group, Self.similarity(centroids[best], vector) >= Self.voicedBitSimilarity,
                       Self.similarity(centroids[best], vector) - mine >= Self.voicedBitMargin {
                        group = best
                    }
                }
                segments[group].append(bit.span)
                placed += 1
                continue
            }
            guard bit.span.duration >= Self.minimumSegmentSeconds else { continue }
            let vector = Self.embed(try speech.read(Int(bit.span.start * rate)..<Int(bit.span.end * rate)), with: encoder)
            let scored = centroids.indices.map { ($0, Self.similarity(centroids[$0], vector)) }
            if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= Self.shortBitSimilarity {
                segments[best.0].append(bit.span)
                placed += 1
            }
        }
        log?(String(format: "%d talk pieces from %d diarized voices -> %d people; %d of %d short bits placed; %.1f s",
                    pieces.count, slots.count, people, placed, short.count, Self.seconds(since: started)))
        progress(1)
        return (0..<people).map { group in
            (Self.joined(segments[group]), Self.weightedAverage(vectors[group]))
        }
    }

    /// The parts of `segment` that aren't a song or music on its own.
    private static func withoutSongs(_ segment: SpeechSegment, map: SoundMap) -> [SpeechSegment] {
        guard !map.kinds.isEmpty else { return [segment] }
        var parts: [SpeechSegment] = []
        var runStart: Double?
        var t = segment.start
        while t < segment.end {
            let next = min(segment.end, (floor(t / SoundMap.step) + 1) * SoundMap.step)
            let keep = ![SoundMap.Kind.singing, .music].contains(map.kind(at: t))
            if keep, runStart == nil { runStart = t }
            if !keep, let start = runStart { parts.append(SpeechSegment(start: start, end: t)); runStart = nil }
            t = next
        }
        if let start = runStart { parts.append(SpeechSegment(start: start, end: segment.end)) }
        return parts.filter { $0.duration >= minimumSegmentSeconds }
    }

    /// Seconds between two stretches (0 if they touch or overlap).
    private static func gap(_ a: SpeechSegment, _ b: SpeechSegment) -> Double {
        max(0, max(a.start, b.start) - min(a.end, b.end))
    }

    /// Sorted, with touching pieces of one stretch put back together.
    private static func joined(_ segments: [SpeechSegment]) -> [SpeechSegment] {
        var out: [SpeechSegment] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, segment.start - last.end <= 0.01 {
                out[out.count - 1] = SpeechSegment(start: last.start, end: max(last.end, segment.end))
            } else {
                out.append(segment)
            }
        }
        return out
    }
    /// "4:05" or "1:02:09".
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Groups unit fingerprints by voice: centroid linkage on the weighted means
    /// of each group's vectors, merging while the closest two means are nearer
    /// than `distance`. With `unitMeans`, means are normalised first, so the test
    /// is a cosine similarity of at least 1 - distance² / 2 however big a group
    /// grows. Returns a group per vector, 0 for the most weight.
    static func cluster(_ vectors: [[Float]], weights: [Double], distance: Float, unitMeans: Bool = false) -> [Int] {
        let n = vectors.count
        guard n > 1 else { return [Int](repeating: 0, count: n) }
        var sums = zip(vectors, weights).map { vDSP.multiply(Float(max($1, 1e-3)), normalized($0)) }
        var mass = weights.map { max($0, 1e-3) }
        func mean(_ sum: [Float], _ mass: Double) -> [Float] { unitMeans ? normalized(sum) : vDSP.divide(sum, Float(mass)) }
        var means = zip(sums, mass).map { mean($0, $1) }
        var alive = [Bool](repeating: true, count: n)
        var members = (0..<n).map { [$0] }
        func d(_ i: Int, _ j: Int) -> Float {
            let diff = vDSP.subtract(means[i], means[j])
            return sqrt(vDSP.sumOfSquares(diff))
        }
        var table = [Float](repeating: .infinity, count: n * n)
        for i in 0..<n { for j in (i + 1)..<n { let v = d(i, j); table[i * n + j] = v; table[j * n + i] = v } }
        var nearest = [Int](repeating: -1, count: n)
        func refresh(_ i: Int) {
            var best = -1, value = Float.infinity
            for j in 0..<n where j != i && alive[j] && table[i * n + j] < value { value = table[i * n + j]; best = j }
            nearest[i] = best
        }
        for i in 0..<n { refresh(i) }
        while true {
            var a = -1, value = Float.infinity
            for i in 0..<n where alive[i] && nearest[i] >= 0 && table[i * n + nearest[i]] < value {
                value = table[i * n + nearest[i]]; a = i
            }
            guard a >= 0, value < distance else { break }
            let b = nearest[a]
            sums[a] = vDSP.add(sums[a], sums[b])
            mass[a] += mass[b]
            means[a] = mean(sums[a], mass[a])
            members[a] += members[b]
            alive[b] = false
            for j in 0..<n where alive[j] && j != a { let v = d(a, j); table[a * n + j] = v; table[j * n + a] = v }
            refresh(a)
            for j in 0..<n where alive[j] && j != a {
                if nearest[j] == a || nearest[j] == b { refresh(j) }
                else if nearest[j] >= 0, table[j * n + a] < table[j * n + nearest[j]] { nearest[j] = a }
            }
        }
        let roots = (0..<n).filter { alive[$0] }.sorted { mass[$0] > mass[$1] }
        var group = [Int](repeating: 0, count: n)
        for (g, root) in roots.enumerated() { for m in members[root] { group[m] = g } }
        return group
    }

    private static func weightedAverage(_ vectors: [([Float], Double)]) -> [Float]? {
        guard let first = vectors.first else { return nil }
        var sum = [Float](repeating: 0, count: first.0.count)
        for (v, w) in vectors { sum = vDSP.add(sum, vDSP.multiply(Float(max(w, 1e-3)), normalized(v))) }
        return normalized(sum)
    }

    // MARK: - Purity

    /// How `checkWindows` went.
    enum PurityCheck: Sendable, Equatable {
        /// Every window was checked; only this person's stretches came back.
        case checked
        /// These windows came back unchecked, being shorter than one
        /// comparison piece (`purityPiece`); any other window that came back
        /// was checked.
        case partlyChecked(unchecked: [ClosedRange<Double>])
        /// A singer: the music under them throws the comparison off, so it isn't run.
        case notApplicable
        /// It couldn't run (no fingerprint for this person, no speaker encoder,
        /// or the person is only the recording's unverified fallback voice),
        /// so the windows came back unchecked.
        case unavailable
        /// Nothing passed, so the windows came back as they were (a mixed clip
        /// beats no clip).
        case keptUnchecked
    }

    /// Only the parts of `windows` that sound like `person` and not like anyone
    /// else found in the recording; see `checkWindows`.
    func cleanWindows(_ analysis: SourceAnalysis, person: Int,
                      windows: [(start: Double, end: Double)]) async throws -> [(start: Double, end: Double)] {
        try await checkWindows(analysis, person: person, windows: windows).windows
    }

    /// Only the parts of `windows` that sound like `person` and not like anyone
    /// else found in the recording, as runs of at least 1.5 s, and whether that
    /// check actually ran. Windows with nothing left are dropped; if that would
    /// drop them all, they come back unchanged (a mixed clip beats no clip).
    /// A window too short to compare is kept, and reported as unchecked.
    /// Singers' windows are kept as they are, since the music under them throws
    /// the comparison off.
    func checkWindows(_ analysis: SourceAnalysis, person: Int, windows: [(start: Double, end: Double)])
        async throws -> (windows: [(start: Double, end: Double)], check: PurityCheck) {
        guard let track = analysis.speakers.first(where: { $0.index == person }) else { return (windows, .unavailable) }
        guard track.kind == .talk else { return (windows, .notApplicable) }
        // An unverified fallback's fingerprint is of whatever the recording
        // holds, so comparing with it proves nothing.
        guard !track.unverified, let own = track.fingerprint,
              let encoder = await loadSpeakerEncoder() else { return (windows, .unavailable) }
        defer { Memory.clearCache() }
        let others = analysis.speakers.filter { $0.index != person }.compactMap(\.fingerprint)
        let reader = try WAVReader(analysis.audio)
        let rate = Double(Self.audioRate)
        let hops = Int((Self.purityPiece / Self.purityHop).rounded())
        var kept: [(start: Double, end: Double)] = []
        var unchecked: [ClosedRange<Double>] = []
        var dropped = 0.0
        for window in windows {
            try Task.checkCancellation()
            let raw = try reader.read(Int(window.start * rate)..<Int(window.end * rate))
            var to16k = Decimator(factor: Self.workingRate / Self.diarizationRate)
            let samples = to16k.process(Self.upsample(raw)) + to16k.finish()
            let piece = Int(Self.purityPiece * Double(Self.diarizationRate)), hop = Int(Self.purityHop * Double(Self.diarizationRate))
            let slots = max(1, samples.count / hop)
            // Votes per 0.5 s slot from every piece that covers it.
            var mine = [Int](repeating: 0, count: slots), votes = [Int](repeating: 0, count: slots)
            var start = 0
            while start + piece <= samples.count {
                let vector = Self.embed(Array(samples[start..<(start + piece)]), with: encoder)
                let like = Self.similarity(own, vector)
                let rival = others.map { Self.similarity($0, vector) }.max() ?? -1
                let belongs = like >= Self.purityFloor && like >= rival
                for s in (start / hop)..<min(slots, start / hop + hops) {
                    votes[s] += 1
                    if belongs { mine[s] += 1 }
                }
                start += hop
            }
            if votes.allSatisfy({ $0 == 0 }) {  // shorter than one piece: kept, but not checked
                kept.append(window)
                unchecked.append(window.start...max(window.start, window.end))
                continue
            }
            var s = 0
            while s < slots {
                guard votes[s] > 0, mine[s] * 2 > votes[s] else { s += 1; continue }
                var e = s + 1
                while e < slots, votes[e] > 0, mine[e] * 2 > votes[e] { e += 1 }
                let lo = window.start + Double(s) * Self.purityHop
                let hi = min(window.end, window.start + Double(e) * Self.purityHop)
                if hi - lo >= Self.purityMinimumRun { kept.append((lo, hi)) }
                s = e
            }
            dropped += (window.end - window.start) - kept.filter { $0.start >= window.start && $0.end <= window.end }
                .reduce(0) { $0 + $1.end - $1.start }
        }
        log?(String(format: "purity: kept %d stretches, dropped %.1f s", kept.count, dropped))
        if kept.isEmpty { return (windows, .keptUnchecked) }
        return (kept, unchecked.isEmpty ? .checked : .partlyChecked(unchecked: unchecked))
    }

    // MARK: - Previews

    /// 5–8 s of the speaker alone: their longest segment, or a few of their longest
    /// strung together with short pauses, cut at a quiet moment.
    private func writePreview(of segments: [SpeechSegment], from reader: WAVReader, to url: URL) throws {
        let byLength = segments.sorted { $0.duration > $1.duration }
        var picked: [(piece: SpeechSegment, trimmed: Bool)] = []
        var total = 0.0
        for segment in byLength where total < Self.previewSeconds.shortest {
            let room = Self.previewSeconds.longest - total
            guard room >= Self.minimumSegmentSeconds else { break }
            let length = min(segment.duration, room)
            picked.append((SpeechSegment(start: segment.start, end: segment.start + length), length < segment.duration))
            total += length
        }
        picked.sort { $0.piece.start < $1.piece.start }

        let rate = Double(Self.audioRate)
        var preview: [Float] = []
        for (i, pick) in picked.enumerated() {
            var end = Int(pick.piece.end * rate)
            if pick.trimmed { end = try Self.quietestPoint(in: reader, before: end, within: Int(1.5 * rate)) }
            var samples = try reader.read(Int(pick.piece.start * rate)..<end)
            Self.fade(&samples, length: Self.audioRate / 50)
            if i > 0 { preview += [Float](repeating: 0, count: Self.audioRate * 3 / 10) }
            preview += samples
        }
        do {
            try AudioUtils.writeWavFile(samples: Self.loudnessMatched(preview), sampleRate: Self.audioRate, fileURL: url)
        } catch { throw Failure.couldNotSave }
    }

    /// The quietest 20 ms point in the `within` samples before `sample`.
    private static func quietestPoint(in reader: WAVReader, before sample: Int, within: Int) throws -> Int {
        let lo = max(0, sample - within)
        let samples = try reader.read(lo..<sample)
        let frame = audioRate / 50
        var best = sample, quietest = Float.infinity
        var i = 0
        while i + frame <= samples.count {
            let e = vDSP.sumOfSquares(samples[i..<(i + frame)])
            if e < quietest { quietest = e; best = lo + i + frame / 2 }
            i += frame / 2
        }
        return best
    }

    // MARK: - Cleaning (Siren's)

    /// Whether DeepFilterNet is downloaded (an extra of Finding voices, `VoiceModel.extras`).
    var canReduceNoise: Bool { store.isWhole(Self.enhancerRepo) }
    /// Whether SAM-Audio is downloaded (Music removal, its own optional download).
    var canRemoveMusic: Bool { store.isWhole(Self.separatorRepo) }
    var canClean: Bool { canReduceNoise || canRemoveMusic }

    /// `windows` (seconds on `audio`, the 24 kHz analysis audio) cleaned as Siren cleans them,
    /// each written to its own 24 kHz WAV in `workDirectory`; nil for a window under half a
    /// second. Each window gets a second of context either side at 48 kHz. Then, with Music
    /// removal downloaded, windows whose gaps between words are loud (`MusicRemoval.gateDB`) go
    /// through SAM-Audio, used as a mask on the original (`masked`, never below
    /// `MusicRemoval.maskFloorDB`), and keep the result only if SAM put enough into the residual
    /// (`MusicRemoval.foundMusic`); SAM-Audio (about 3.2 GB) is let go before anything else
    /// loads. Then, with DeepFilterNet downloaded, every window gets its light noise reduction
    /// (`capped` at `noiseLimitDB`; 9 MB of weights). Then back to 24 kHz without the context.
    func clean(_ audio: URL, windows: [(start: Double, end: Double)], workDirectory: URL,
               progress: @escaping @Sendable (ProcessingStage) -> Void = { _ in }) async throws -> [CleanWindow?] {
        guard !windows.isEmpty else { return [] }
        let cacheLimit = Self.capCache()
        defer { Memory.cacheLimit = cacheLimit; Memory.clearCache() }
        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        } catch { throw Failure.couldNotSave }
        let reader = try WAVReader(audio)
        let context = Int(Self.windowContextSeconds * Double(Self.audioRate))
        let removesMusic = canRemoveMusic
        var jobs: [CleanJob] = []
        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            let start = max(0, window.start), end = min(reader.seconds, window.end)
            guard end - start >= 0.5 else { continue }
            let lo = Int(start * Double(Self.audioRate)), hi = Int(end * Double(Self.audioRate))
            let raw = try reader.read((lo - context)..<(hi + context))
            let gap = removesMusic ? MusicRemoval.gapLevelDB(Array(raw[context..<(raw.count - context)]), rate: Self.audioRate) : -120
            jobs.append(CleanJob(index: index, start: start, end: end, samples: Self.upsample(raw),
                            separate: removesMusic && MusicRemoval.needsSeparation(gapDB: gap)))
        }

        // Music: SAM-Audio, only on the windows that need it, let go before DeepFilterNet loads.
        let toSeparate = jobs.indices.filter { jobs[$0].separate }
        if !toSeparate.isEmpty {
            progress(.removingMusic)
            try await removeMusic(from: &jobs, at: toSeparate)
        }

        // Noise: DeepFilterNet everywhere, lightly, then back to 24 kHz without the context.
        var enhancer: DeepFilterNetModel?
        if canReduceNoise {
            progress(.reducingNoise)
            let directory = store.folder(for: Self.enhancerRepo)
            enhancer = try await load { try DeepFilterNetModel.fromLocal(directory, subfolder: "v3") }
        }
        defer { enhancer = nil; Memory.clearCache() }
        var files = [CleanWindow?](repeating: nil, count: windows.count)
        for job in jobs {
            try Task.checkCancellation()
            let enhanced = try enhancer.map { try Self.denoise(job.samples, with: $0, limitDB: Self.noiseLimitDB) } ?? job.samples
            var decimator = Decimator(factor: Self.workingRate / Self.audioRate)
            let out = decimator.process(enhanced) + decimator.finish()
            let length = Int(job.end * Double(Self.audioRate)) - Int(job.start * Double(Self.audioRate))
            let trimmed = Array(out[min(context, out.count)..<min(context + length, out.count)])
            let file = workDirectory.appendingPathComponent(String(format: "clean-%07d-%07d.wav", Int(job.start * 1000), Int(job.end * 1000)))
            do {
                try AudioUtils.writeWavFile(samples: trimmed, sampleRate: Self.audioRate, fileURL: file)
            } catch { throw Failure.couldNotSave }
            files[job.index] = CleanWindow(file: file, musicRemoved: job.musicRemoved)
        }
        return files
    }

    /// One window being cleaned: at 48 kHz with its context.
    private struct CleanJob {
        let index: Int, start: Double, end: Double
        var samples: [Float]
        let separate: Bool
        var musicRemoved = false
    }

    /// SAM-Audio over `jobs[indices]` (Siren's music stage): separated in overlapping 24 s
    /// pieces, each piece's split used as a mask on the original; a job keeps the result only
    /// when SAM found music. The model is loaded for this call alone.
    private func removeMusic(from jobs: inout [CleanJob], at indices: [Int]) async throws {
        let started = ContinuousClock.now
        let directory = store.folder(for: Self.separatorRepo)
        var model: SAMAudio? = try await load { try SAMAudio.fromDirectory(directory) }
        defer { model = nil; Memory.clearCache() }
        let (features, mask) = try Self.promptConditioning()
        MLXRandom.seed(20_260_924)
        for i in indices {
            try Task.checkCancellation()
            guard let separator = model else { throw Failure.modelsUnavailable }
            let began = ContinuousClock.now
            let input = jobs[i].samples
            var speechEnergy: Float = 0, residualEnergy: Float = 0
            func separateAndMask(_ part: [Float]) async throws -> [Float] {
                try Task.checkCancellation()
                let (speech, residual) = try await Self.separate(part, with: separator, features: features, mask: mask)
                speechEnergy += vDSP.sumOfSquares(speech)
                residualEnergy += vDSP.sumOfSquares(residual)
                return Self.masked(part, speech: speech, residual: residual, floorDB: MusicRemoval.maskFloorDB)
            }
            let piece = Int(MusicRemoval.pieceSeconds * Double(Self.workingRate))
            let filtered = input.count <= piece
                ? try await separateAndMask(input)
                : try await MusicRemoval.overlapped(input, step: piece - 2 * Self.workingRate, context: Self.workingRate,
                                                    fade: Self.workingRate / 10, transform: separateAndMask)
            let share = MusicRemoval.residualShareDB(speechEnergy: speechEnergy, residualEnergy: residualEnergy,
                                                     samples: input.count)
            if MusicRemoval.foundMusic(residualShareDB: share) {
                jobs[i].samples = filtered
                jobs[i].musicRemoved = true
            }
            log?(String(format: "music: %.1f-%.1f s separated in %.1f s, residual %.1f dB -> %@", jobs[i].start, jobs[i].end,
                        Self.seconds(since: began), share, jobs[i].musicRemoved ? "music removed" : "kept original"))
        }
        log?(String(format: "music stage %.1f s for %d windows", Self.seconds(since: started), indices.count))
    }

    private static func separate(_ samples: [Float], with model: SAMAudio, features: MLXArray,
                                 mask: MLXArray) async throws -> (speech: [Float], residual: [Float]) {
        defer { Memory.clearCache() }
        let audio = MLXArray(samples).reshaped([1, 1, samples.count])
        let result = try await model.separate(audios: audio, descriptions: [SpeechPrompt.text], ode: separationODE,
                                              odeDecodeChunkSize: decodeFrames,
                                              _textFeatures: features, _textMask: mask)
        let speech = result.target[0].reshaped([-1]).asType(.float32).asArray(Float.self)
        let residual = result.residual[0].reshaped([-1]).asType(.float32).asArray(Float.self)
        return (fitted(speech, samples.count), fitted(residual, samples.count))
    }

    /// Keeps the original recording but filters it with SAM-Audio's separation: each
    /// time-frequency cell is scaled by speech / (speech + residual) power, never below
    /// `floorDB`. The voice keeps its own fine detail instead of SAM's re-synthesis.
    private static func masked(_ input: [Float], speech: [Float], residual: [Float], floorDB: Float) -> [Float] {
        let n = 2048, hop = 512
        let window = hanningWindow(size: n, periodic: true)
        func spectrum(_ x: [Float]) -> MLXArray {
            MossFormer2DSP.stft(audio: MLXArray(x), fftLen: n, hopLength: hop, winLen: n, window: window, center: true)
        }
        let mix = spectrum(input)
        let s = MLX.abs(spectrum(speech)).square(), r = MLX.abs(spectrum(residual)).square()
        let mask = MLX.maximum(s / (s + r + 1e-12), pow(10, floorDB / 20))
        let filtered = mix * mask
        let out = MossFormer2DSP.istft(real: filtered.realPart().transposed(1, 0).expandedDimensions(axis: 0),
                                       imag: filtered.imaginaryPart().transposed(1, 0).expandedDimensions(axis: 0),
                                       fftLen: n, hopLength: hop, winLen: n, window: window, center: true,
                                       audioLength: input.count)
        defer { Memory.clearCache() }
        return fitted(out.asArray(Float.self), input.count)
    }

    /// SAM-Audio's conditioning for "speech", from the T5 features embedded in `SpeechPrompt`
    /// (MacSpaces never downloads T5).
    private static func promptConditioning() throws -> (MLXArray, MLXArray) {
        guard let data = Data(base64Encoded: SpeechPrompt.features, options: .ignoreUnknownCharacters),
              !data.isEmpty, data.count % (768 * 4) == 0 else { throw Failure.modelsUnavailable }
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let tokens = floats.count / 768
        return (MLXArray(floats, [1, tokens, 768]), MLXArray.ones([1, tokens]).asType(.bool))
    }

    /// DeepFilterNet with its attenuation capped at `limitDB` (`capped`).
    private static func denoise(_ samples: [Float], with model: DeepFilterNetModel, limitDB: Float) throws -> [Float] {
        capped(samples, enhanced: try enhance(samples, with: model), limitDB: limitDB)
    }

    /// DeepFilterNet's whole output for 48 kHz `samples`.
    private static func enhance(_ samples: [Float], with model: DeepFilterNetModel) throws -> [Float] {
        defer { Memory.clearCache() }
        return fitted(try model.enhance(MLXArray(samples)).asArray(Float.self), samples.count)
    }

    /// At most `limitDB` of DeepFilterNet's attenuation, as a dry mix:
    /// enhanced + dry * (input - enhanced), with dry = 10^(-limitDB / 20).
    /// 0 gives the input back; nil gives DeepFilterNet's whole output.
    static func capped(_ input: [Float], enhanced: [Float], limitDB: Float?) -> [Float] {
        guard let limitDB else { return enhanced }
        let dry = pow(10, -limitDB / 20)
        return vDSP.add(vDSP.multiply(dry, vDSP.subtract(input, enhanced)), enhanced)
    }

    // MARK: - Shared helpers

    /// Caps MLX's buffer cache while processing; returns the old limit to restore.
    private static func capCache() -> Int {
        let previous = Memory.cacheLimit
        Memory.cacheLimit = 256 * 1_048_576
        return previous
    }

    /// Loads a model; any failure (usually the first download) becomes one plain message.
    private func load<T>(_ body: () async throws -> T) async throws -> T {
        Memory.clearCache()
        do {
            return try await body()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log?("model load failed: \(error)")
            throw Failure.modelsUnavailable
        }
    }

    /// 24 kHz to 48 kHz: zero-stuffing and the same zero-phase low-pass the decimator uses.
    private static func upsample(_ samples: [Float]) -> [Float] {
        let taps = Decimator.lowPass(factor: 2).map { $0 * 2 }
        let half = taps.count / 2
        var stuffed = [Float](repeating: 0, count: samples.count * 2 + 2 * half)
        for (i, x) in samples.enumerated() { stuffed[half + 2 * i] = x }
        var out = [Float](repeating: 0, count: samples.count * 2)
        vDSP_conv(stuffed, 1, taps, 1, &out, 1, vDSP_Length(out.count), vDSP_Length(taps.count))
        return out
    }

    private static func fitted(_ samples: [Float], _ count: Int) -> [Float] {
        if samples.count == count { return samples }
        if samples.count > count { return Array(samples.prefix(count)) }
        return samples + [Float](repeating: 0, count: count - samples.count)
    }

    private static func fade(_ samples: inout [Float], length: Int) {
        let n = min(length, samples.count / 2)
        for i in 0..<n {
            let w = Float(i) / Float(n)
            samples[i] *= w
            samples[samples.count - 1 - i] *= w
        }
    }

    /// About -20 dBFS without clipping, like the reference clips.
    private static func loudnessMatched(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let peak = vDSP.maximumMagnitude(samples)
        let rms = vDSP.rootMeanSquare(samples)
        guard peak > 0, rms > 0 else { return samples }
        return vDSP.multiply(min(0.1 / rms, 0.95 / peak), samples)
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

// MARK: - Speaker fingerprints

/// WeSpeaker ResNet34-LM (pyannote's speaker embedding model), BatchNorm fused, as
/// converted to MLX by aufklarer/WeSpeaker-ResNet34-LM-MLX.
private final class SpeakerEncoder: Module {
    @ModuleInfo var conv1: Conv2d
    @ModuleInfo var layer1: [SpeakerBlock]
    @ModuleInfo var layer2: [SpeakerBlock]
    @ModuleInfo var layer3: [SpeakerBlock]
    @ModuleInfo var layer4: [SpeakerBlock]
    @ModuleInfo var embedding: Linear

    override init() {
        func layer(_ count: Int, _ input: Int, _ output: Int, stride: Int) -> [SpeakerBlock] {
            (0..<count).map { SpeakerBlock($0 == 0 ? input : output, output, stride: $0 == 0 ? stride : 1) }
        }
        _conv1.wrappedValue = Conv2d(inputChannels: 1, outputChannels: 32, kernelSize: 3, padding: 1)
        _layer1.wrappedValue = layer(3, 32, 32, stride: 1)
        _layer2.wrappedValue = layer(4, 32, 64, stride: 2)
        _layer3.wrappedValue = layer(6, 64, 128, stride: 2)
        _layer4.wrappedValue = layer(3, 128, 256, stride: 2)
        _embedding.wrappedValue = Linear(5120, 256)
    }

    /// `fbank`: (batch, frames, 80) -> (batch, 256).
    func callAsFunction(_ fbank: MLXArray) -> MLXArray {
        var x = fbank.transposed(0, 2, 1).expandedDimensions(axis: -1)  // (B, 80 freq, T, 1)
        x = relu(conv1(x))
        for block in layer1 + layer2 + layer3 + layer4 { x = block(x) }
        // (B, 10, T/8, 256) -> (B, T/8, 256 * 10), channel-major like the PyTorch original.
        x = x.transposed(0, 2, 3, 1).reshaped([x.dim(0), x.dim(2), -1])
        let average = mean(x, axis: 1)
        let spread = sqrt(variance(x, axis: 1, ddof: 1) + 1e-7)
        return embedding(concatenated([average, spread], axis: -1))
    }
}

private final class SpeakerBlock: Module {
    @ModuleInfo var conv1: Conv2d
    @ModuleInfo var conv2: Conv2d
    @ModuleInfo var shortcut: Conv2d?

    init(_ input: Int, _ output: Int, stride: Int) {
        _conv1.wrappedValue = Conv2d(inputChannels: input, outputChannels: output, kernelSize: 3,
                                     stride: .init(integerLiteral: stride), padding: 1)
        _conv2.wrappedValue = Conv2d(inputChannels: output, outputChannels: output, kernelSize: 3, padding: 1)
        _shortcut.wrappedValue = stride != 1 || input != output
            ? Conv2d(inputChannels: input, outputChannels: output, kernelSize: 1, stride: .init(integerLiteral: stride))
            : nil
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        relu(conv2(relu(conv1(x))) + (shortcut.map { $0(x) } ?? x))
    }
}

/// Kaldi log-mel filterbank exactly as pyannote feeds WeSpeaker: 16 kHz audio scaled
/// to 16-bit range, 25 ms Hamming frames every 10 ms (no padding), DC removed,
/// pre-emphasis 0.97, 512-point power spectrum, 80 Kaldi mel bins from 20 Hz to
/// 8 kHz, natural log, then the mean over time subtracted.
private enum KaldiFbank {
    static let bins = 80
    static let frameLength = 400, frameShift = 160, fftLength = 512

    static let window: [Float] = (0..<frameLength).map {
        Float(0.54 - 0.46 * cos(2 * Double.pi * Double($0) / Double(frameLength - 1)))
    }

    /// (bins x 256) triangular weights in the Kaldi mel domain.
    static let filters: [Float] = {
        func mel(_ f: Double) -> Double { 1127 * log(1 + f / 700) }
        let low = mel(20), high = mel(8_000), delta = (high - low) / Double(bins + 1)
        var weights = [Float](repeating: 0, count: bins * fftLength / 2)
        for b in 0..<bins {
            let left = low + Double(b) * delta, center = left + delta, right = center + delta
            for k in 0..<(fftLength / 2) {
                let m = mel(Double(k) * 16_000 / Double(fftLength))
                let w = min((m - left) / (center - left), (right - m) / (right - center))
                weights[b * fftLength / 2 + k] = Float(max(0, w))
            }
        }
        return weights
    }()

    /// Row-major (frames x 80) features and the frame count.
    static func features(_ samples: [Float]) -> ([Float], Int) {
        guard samples.count >= frameLength else { return ([], 0) }
        let frames = 1 + (samples.count - frameLength) / frameShift
        let half = fftLength / 2
        guard let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else { return ([], 0) }
        defer { vDSP_destroy_fftsetup(setup) }
        var out = [Float](repeating: 0, count: frames * bins)
        var frame = [Float](repeating: 0, count: fftLength)
        var real = [Float](repeating: 0, count: half), imag = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        for f in 0..<frames {
            let start = f * frameShift
            var x = (0..<frameLength).map { samples[start + $0] * 32_768 }
            let dc = vDSP.mean(x)
            x = vDSP.add(-dc, x)
            for i in stride(from: frameLength - 1, to: 0, by: -1) { x[i] -= 0.97 * x[i - 1] }
            x[0] -= 0.97 * x[0]
            frame.replaceSubrange(0..<frameLength, with: vDSP.multiply(x, window))
            for i in frameLength..<fftLength { frame[i] = 0 }
            for i in 0..<half { real[i] = frame[2 * i]; imag[i] = frame[2 * i + 1] }
            real.withUnsafeMutableBufferPointer { r in
                imag.withUnsafeMutableBufferPointer { im in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: im.baseAddress!)
                    vDSP_fft_zrip(setup, &split, 1, 9, FFTDirection(kFFTDirection_Forward))
                }
            }
            // vDSP's packed result is twice the DFT; bin 0's imaginary slot holds Nyquist (weight 0 here).
            power[0] = real[0] * real[0] / 4
            for k in 1..<half { power[k] = (real[k] * real[k] + imag[k] * imag[k]) / 4 }
            for b in 0..<bins {
                let energy = filters.withUnsafeBufferPointer {
                    vDSP.dot(UnsafeBufferPointer(rebasing: $0[(b * half)..<((b + 1) * half)]), power)
                }
                out[f * bins + b] = log(max(energy, 1.1920929e-07))
            }
        }
        // Mean over time per bin.
        for b in 0..<bins {
            var sum: Float = 0
            for f in 0..<frames { sum += out[f * bins + b] }
            let average = sum / Float(frames)
            for f in 0..<frames { out[f * bins + b] -= average }
        }
        return (out, frames)
    }
}

// MARK: - Audio files

/// Raw mono float32 samples on disk, with a little level information.
private struct SampleFile {
    let url: URL
    let rate: Int
    let count: Int
    let peak: Float
    /// RMS of each 50 ms frame.
    let frameRMS: [Float]
}

private final class SampleWriter {
    private let url: URL
    private let rate: Int
    private let handle: FileHandle
    private(set) var count = 0
    private var peak: Float = 0
    private var frameRMS: [Float] = []
    private var frameEnergy: Float = 0
    private var frameFill = 0
    private let frameLength: Int

    init(_ url: URL, rate: Int) throws {
        self.url = url
        self.rate = rate
        frameLength = rate / 20
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { throw SourceProcessor.Failure.couldNotSave }
        self.handle = handle
    }

    func append(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        do {
            try samples.withUnsafeBufferPointer { try handle.write(contentsOf: Data(buffer: $0)) }
        } catch { throw SourceProcessor.Failure.couldNotSave }
        count += samples.count
        peak = max(peak, vDSP.maximumMagnitude(samples))
        for x in samples {
            frameEnergy += x * x
            frameFill += 1
            if frameFill == frameLength {
                frameRMS.append(sqrt(frameEnergy / Float(frameLength)))
                frameEnergy = 0
                frameFill = 0
            }
        }
    }

    func close() throws -> SampleFile {
        do { try handle.close() } catch { throw SourceProcessor.Failure.couldNotSave }
        return SampleFile(url: url, rate: rate, count: count, peak: peak, frameRMS: frameRMS)
    }
}

private final class SampleReader {
    private let handle: FileHandle
    private let count: Int

    init(_ file: SampleFile) throws {
        guard let handle = try? FileHandle(forReadingFrom: file.url) else { throw SourceProcessor.Failure.couldNotSave }
        self.handle = handle
        count = file.count
    }

    deinit { try? handle.close() }

    /// Samples in `range`, with silence before the start and after the end.
    func read(_ range: Range<Int>) throws -> [Float] {
        var out = [Float](repeating: 0, count: range.count)
        let lo = max(0, range.lowerBound), hi = min(count, range.upperBound)
        guard hi > lo else { return out }
        let data: Data
        do {
            try handle.seek(toOffset: UInt64(lo * 4))
            data = try handle.read(upToCount: (hi - lo) * 4) ?? Data()
        } catch { throw SourceProcessor.Failure.couldNotSave }
        out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                let offset = (lo - range.lowerBound) * 4
                dst.baseAddress!.advanced(by: offset).copyMemory(from: src.baseAddress!, byteCount: min(src.count, dst.count - offset))
            }
        }
        return out
    }
}

/// Random access to the first channel of a WAV (the analysis audio).
private final class WAVReader {
    private let file: AVAudioFile
    private let count: Int

    init(_ url: URL) throws {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              Int(file.processingFormat.sampleRate) == SourceProcessor.audioRate else { throw SourceProcessor.Failure.unreadable }
        self.file = file
        count = Int(file.length)
    }

    var seconds: Double { Double(count) / Double(SourceProcessor.audioRate) }

    /// Samples in `range`, with silence before the start and after the end.
    func read(_ range: Range<Int>) throws -> [Float] {
        var out = [Float](repeating: 0, count: range.count)
        let lo = max(0, range.lowerBound), hi = min(count, range.upperBound)
        guard hi > lo else { return out }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(hi - lo))
        else { throw SourceProcessor.Failure.unreadable }
        file.framePosition = AVAudioFramePosition(lo)
        try AudioFileReader.readAvailableFrames(from: file, into: buffer)
        if let data = buffer.floatChannelData {
            let n = min(Int(buffer.frameLength), hi - lo)
            out.replaceSubrange((lo - range.lowerBound)..<(lo - range.lowerBound + n),
                                with: UnsafeBufferPointer(start: data[0], count: n))
        }
        return out
    }
}

/// Integer-factor downsampler: a zero-phase windowed-sinc low-pass (Blackman,
/// 32 taps per side per factor) with no delay, so times stay exact.
private struct Decimator {
    let factor: Int
    private let taps: [Float]
    private var buffer: [Float]
    private var consumed = 0
    private var produced = 0

    init(factor: Int) {
        self.factor = factor
        taps = Self.lowPass(factor: factor)
        buffer = [Float](repeating: 0, count: taps.count / 2)
    }

    /// Unit-gain low-pass at 0.46 of the lower rate's Nyquist band.
    static func lowPass(factor: Int) -> [Float] {
        let half = 32 * factor
        let length = 2 * half + 1
        let cutoff = 0.46 / Double(factor)
        var taps = [Float](repeating: 0, count: length)
        for i in 0..<length {
            let n = Double(i - half)
            let sinc = n == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * n) / (.pi * n)
            let phase = Double(i) / Double(length - 1)
            let window = 0.42 - 0.5 * cos(2 * .pi * phase) + 0.08 * cos(4 * .pi * phase)
            taps[i] = Float(sinc * window)
        }
        let sum = taps.reduce(0, +)
        return taps.map { $0 / sum }
    }

    mutating func process(_ input: [Float]) -> [Float] {
        guard factor > 1 else { return input }
        consumed += input.count
        buffer += input
        return drain()
    }

    mutating func finish() -> [Float] {
        guard factor > 1 else { return [] }
        let expected = (consumed + factor - 1) / factor
        let before = produced
        buffer += [Float](repeating: 0, count: taps.count)
        return Array(drain().prefix(max(0, expected - before)))
    }

    private mutating func drain() -> [Float] {
        guard buffer.count >= taps.count else { return [] }
        let n = (buffer.count - taps.count) / factor + 1
        var out = [Float](repeating: 0, count: n)
        vDSP_desamp(buffer, vDSP_Stride(factor), taps, &out, vDSP_Length(n), vDSP_Length(taps.count))
        buffer.removeFirst(n * factor)
        produced += n
        return out
    }
}
