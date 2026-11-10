#if DEBUG
import AppKit
import AVFoundation
import Darwin
import Foundation
import os

/// `MACSPACES_QA_SCOPE=voices-live`: voices from recordings end to end, for real, on this Mac.
/// Opt-in only (never in CI or the default scopes): it downloads Finding voices (263 MB) and
/// Standard (small) (2.0 GB) from Hugging Face into the harness's temporary Voices folder, makes
/// synthetic recordings with the Mac's own voices (no real people): a two-voice conversation and
/// the first voice alone, dropped together with a third that's removed before it's sorted. Both
/// are listed and sorted in turn, and the voice heard in both becomes one voice with clips from
/// each. It approves that voice as "mine" for the agent, speaks a line in it through the helper
/// (its two clips joined into one reference), as Play and Save to Tray do, then makes Studio's
/// takes (two seeds, a seed again, a delivery, a pace) and removes the other voice's files. Every
/// step, timing and the helper's peak memory go in voices-live.txt. The several-recordings steps
/// are new, so they report (MEASURE lines) and don't fail the run yet.
@available(macOS 15, *)
@MainActor enum VoicesLiveCheck {
    /// The helper is stopped, and the run reported, past this footprint (the 4 GB job budget).
    static let memoryCeiling: UInt64 = 4_608 * 1_048_576

    static func run(to directory: URL) {
        let report = Report(file: directory.appendingPathComponent("voices-live.txt"))
        let sampler = HelperMemorySampler(ceiling: memoryCeiling)
        sampler.start()
        Task { @MainActor in
            await steps(directory: directory, report: report, sampler: sampler)
            sampler.stop()
            report.line("Helper peak footprint: \(sampler.summary)")
            report.line("Finished: \(report.failures == 0 ? "every step passed" : "\(report.failures) step(s) failed")")
            NSApp.terminate(nil)
        }
    }

    private static func steps(directory: URL, report: Report, sampler: HelperMemorySampler) async {
        let root = VoicePaths.root
        report.line("Voices folder: \(root.path)")
        report.line("Bundle: \(Bundle.main.bundleIdentifier ?? "?"), helper bundle: \(Bundle(url: RecordedVoiceSupport.helperURL)?.bundleIdentifier ?? "missing")")
        guard !root.path.contains("/Library/Application Support/") else {
            report.fail("Fixtures", "the Voices folder is the real one; stopping before anything is written"); return
        }
        // From nothing, as on a Mac that never downloaded a voice model.
        try? FileManager.default.removeItem(at: root)
        let voices = RecordedVoices(root: root)
        guard voices.isAvailable else { report.fail("Available", RecordedVoiceSupport.unavailableNote); return }
        let store = VoiceModelStore(hub: VoicePaths.models(in: root))

        // 1. The recordings: the conversation, the first voice alone, and a third (the second
        // copied) that's removed while it waits.
        let recording = directory.appendingPathComponent("voices-live-recording.wav")
        let made = await timed { try await SyntheticConversation.write(to: recording) }
        switch made.result {
        case .success(let summary): report.pass("Recording", "\(summary) in \(seconds(made.time))")
        case .failure(let error): report.fail("Recording", error.localizedDescription); return
        }
        let solo = directory.appendingPathComponent("voices-live-solo.wav")
        let soloMade = await timed { try await SyntheticConversation.writeSolo(to: solo) }
        switch soloMade.result {
        case .success(let summary): report.pass("Second recording", "\(summary) in \(seconds(soloMade.time))")
        case .failure(let error): report.fail("Second recording", error.localizedDescription); return
        }
        let extra = directory.appendingPathComponent("voices-live-removed.wav")
        try? FileManager.default.removeItem(at: extra)
        try? FileManager.default.copyItem(at: solo, to: extra)

        // 2. The downloads: Finding voices and the small engine only.
        for model in [VoiceModel.sorting, .standardSmall] {
            sampler.phase = "download \(model.id)"
            let start = Date()
            voices.download(model)
            await wait(for: voices, limit: 3600, report: report, sampler: sampler)
            let state = store.state(of: model)
            if state.isDownloaded, voices.problem == nil {
                if case .downloaded(let bytes) = state {
                    // What Settings shows as on this Mac should be about the download's size.
                    let shown = Double(bytes) / Double(model.downloadBytes)
                    (shown < 1.15 ? report.pass : report.fail)("Download \(model.title)", "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) in \(seconds(Date().timeIntervalSince(start))), \(String(format: "%.2f", shown))x the listed \(ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file))")
                }
            } else {
                report.fail("Download \(model.title)", "\(voices.problem ?? "not whole") (state \(state)) after \(seconds(Date().timeIntervalSince(start)))")
                return
            }
            if sampler.overCeiling { report.fail("Memory", "over the ceiling during the download"); return }
        }
        voices.refreshModels()
        try? await Task.sleep(for: .seconds(1))
        report.line("Downloaded models: \(store.downloaded().sorted().joined(separator: ", ")); Models folder \(ByteCountFormatter.string(fromByteCount: VoiceModelStore.size(of: store.hub), countStyle: .file))")

        // 3. Sorting several recordings at once: every one listed, the third removed before it's
        // sorted, the other two sorted in turn, and the voice heard in both joined into one.
        sampler.phase = "sort"
        var start = Date()
        voices.add([recording, solo, extra])
        for _ in 0..<40 where voices.recordings.count < 3 { try? await Task.sleep(for: .milliseconds(250)) }
        report.line("MEASURE Listed: \(voices.recordings.count) of 3 recordings dropped at once (\(voices.recordings.map { "\($0.name) \($0.state.rawValue)" }.joined(separator: ", ")))")
        if let third = voices.recordings.first(where: { $0.path == extra.path }) {
            report.line("MEASURE Remove while waiting: the third was \(third.state.rawValue) when removed")
            voices.removeRecording(third)
        }
        while voices.isBusy || voices.recordings.contains(where: { $0.state == .waiting || $0.state == .sorting }) {
            await wait(for: voices, limit: 1800, report: report, sampler: sampler)
            if sampler.overCeiling || Date().timeIntervalSince(start) > 3600 { break }
            try? await Task.sleep(for: .milliseconds(500))
            if !voices.isBusy, voices.paused { break }
        }
        if sampler.overCeiling { report.fail("Sort", "stopped: the helper went over \(memoryCeiling / 1_048_576) MB"); return }
        for item in voices.recordings {
            report.line("  recording \(item.name): \(item.state.rawValue), \(item.people) people, note: \(item.note ?? "none")")
        }
        report.line("MEASURE Recordings after sorting: \(voices.recordings.count) listed (2 expected), \(voices.recordings.filter { $0.state == .sorted }.count) sorted; the removed one never sorted: \(!voices.recordings.contains { $0.path == extra.path })")
        for voice in voices.voices {
            report.line("  voice \"\(voice.name)\": \(voice.clips.count) clips from \(voice.recordingCount) recordings, approved \(voice.isApproved)")
            for sample in voice.clips {
                report.line("    \(sample.delivery.title) \(String(format: "%.1f", sample.seconds)) s from \(sample.recordingName ?? "?"), included \(sample.included): \(sample.transcript)")
            }
        }
        if voices.voices.count >= 2, let a = VoiceSamples.fingerprint(voices.voices[0].clips), let b = VoiceSamples.fingerprint(voices.voices[1].clips) {
            report.line(String(format: "  fingerprint similarity between the first two voices: %.3f", VoiceGrouping.similarity(a, b)))
        }
        let joined = voices.voices.first { $0.recordingCount >= 2 }
        report.line("MEASURE Joined across recordings: \(joined.map { "\($0.name), \($0.clips.count) clips from \($0.recordingCount) recordings" } ?? "no voice has clips from both") ; \(voices.voices.count) voices (2 expected)")
        if voices.voices.isEmpty {
            report.fail("Sort", "no voices (\(voices.problem ?? "no error")) in \(seconds(Date().timeIntervalSince(start)))")
            return
        }
        report.pass("Sort", "\(voices.voices.count) voices in \(seconds(Date().timeIntervalSince(start)))")

        // 4. Approving, as "mine", for the agent: the voice heard in both recordings when there is one.
        guard let picked = joined ?? voices.voices.first(where: { !$0.transcript.isEmpty }) else { report.fail("Approve", "no voice has words"); return }
        voices.approve(picked, name: "Live check voice", consent: "mine")
        UserDefaults.standard.set(picked.voiceID, forKey: WidgetOptions.Keys.wispVoice)
        guard let voice = voices.voice(id: picked.voiceID) else { report.fail("Approve", voices.problem ?? "not approved"); return }
        let agentVoice = UserDefaults.standard.string(forKey: WidgetOptions.Keys.wispVoice)
        if agentVoice == voice.voiceID, voice.consent == "mine", voice.isApproved,
           FileManager.default.fileExists(atPath: voice.clip(in: root).path) {
            report.pass("Approve", "\(voice.name) approved as \(voice.voiceID), consent mine, agent voice set")
        } else {
            report.fail("Approve", "agent voice \(agentVoice ?? "nil"), consent \(voice.consent ?? "nil")")
        }
        let reference = voice.reference(for: .natural, in: root)
        report.line("MEASURE Reference: Natural reads \(reference?.clip.lastPathComponent ?? "no clip"), \(String(format: "%.1f", reference.map { StudioAudio.seconds(of: $0.clip) } ?? 0)) s, of \(voice.clips.count) clip(s)")

        // 5. Speaking, through the helper as Play and Save to Tray do.
        voices.useEngine(.standardSmall)
        report.line("Engine for replies: \(voices.engine?.id ?? "none")")
        let before = VoiceModelStore.size(of: store.hub)
        sampler.phase = "speak"
        start = Date()
        let line = "Hello, this is a test of a voice made from a recording, speaking a whole sentence on this Mac."
        do {
            let file = try await voices.speech(line, in: voice)
            let time = Date().timeIntervalSince(start)
            let kept = directory.appendingPathComponent("voices-live-spoken.wav")
            try? FileManager.default.removeItem(at: kept)
            try FileManager.default.moveItem(at: file, to: kept)
            let audio = try AVAudioFile(forReading: kept)
            let duration = Double(audio.length) / audio.fileFormat.sampleRate
            let peak = peakLevel(kept)
            let ok = duration > 2 && peak > 0.01
            (ok ? report.pass : report.fail)("Speak", String(format: "%.2f s of audio at %.0f Hz, peak %.3f, made in %@ (%.2fx real time)",
                                                              duration, audio.fileFormat.sampleRate, peak, seconds(time), time / max(0.01, duration)))
        } catch {
            report.fail("Speak", "\(error.localizedDescription) after \(seconds(Date().timeIntervalSince(start)))")
        }
        if sampler.overCeiling { report.fail("Memory", "the helper went over \(memoryCeiling / 1_048_576) MB while speaking") }
        let after = VoiceModelStore.size(of: store.hub)
        report.line("Models folder while speaking: \(after == before ? "unchanged (nothing downloaded)" : "changed by \(after - before) bytes")")

        // 6. Studio's takes: the same words with two seeds, then the first seed again, as Another
        // Take does; a take in another delivery when the voice has one; and Siren's pace change.
        sampler.phase = "takes"
        let words = "Each take of the same words should sound a little different."
        var takes: [(seed: UInt64, file: URL)] = []
        for (index, seed) in [UInt64(11), 22, 11].enumerated() {
            start = Date()
            do {
                let file = try await voices.speech(words, in: voice, seed: seed)
                let kept = directory.appendingPathComponent("voices-live-take-\(index + 1)-seed\(seed).wav")
                try? FileManager.default.removeItem(at: kept)
                try FileManager.default.moveItem(at: file, to: kept)
                takes.append((seed, kept))
                report.line(String(format: "  take %d (seed %llu): %.2f s, peak %.3f, made in %@", index + 1, seed,
                                   StudioAudio.seconds(of: kept), peakLevel(kept), seconds(Date().timeIntervalSince(start))))
            } catch {
                report.fail("Take \(index + 1)", error.localizedDescription)
            }
            if sampler.overCeiling { report.fail("Memory", "the helper went over \(memoryCeiling / 1_048_576) MB making takes"); return }
        }
        if takes.count == 3 {
            let differ = difference(takes[0].file, takes[1].file), same = difference(takes[0].file, takes[2].file)
            report.line(String(format: "  seed 11 vs 22: %@; seed 11 vs 11 again: %@", differ.text, same.text))
            (differ.differs ? report.pass : report.fail)("Takes differ", "two seeds made two different takes")
            (!same.differs ? report.pass : report.fail)("Takes repeat", same.differs ? "the same seed made a different take (the engine isn't deterministic)" : "the same seed made the same take")
        }
        if let delivery = voice.availableDeliveries.first(where: { $0 != .natural }) {
            start = Date()
            do {
                let file = try await voices.speech(words, in: voice, delivery: delivery, seed: 11)
                let kept = directory.appendingPathComponent("voices-live-take-\(delivery.rawValue).wav")
                try? FileManager.default.removeItem(at: kept)
                try FileManager.default.moveItem(at: file, to: kept)
                report.pass("Delivery", String(format: "%@: %.2f s in %@", delivery.title, StudioAudio.seconds(of: kept), seconds(Date().timeIntervalSince(start))))
            } catch {
                report.fail("Delivery", error.localizedDescription)
            }
        } else {
            report.line("  this voice has no other delivery (fewer than three clear stretches that differ)")
        }
        // 7. Clips and removal: leaving Natural's clip out changes what it reads; Remove Voice
        // deletes the other voice's folder.
        if let current = voices.voice(id: voice.voiceID), let used = VoiceSamples.reference(current.clips, for: .natural),
           VoiceSamples.canExclude(current.clips, at: used) {
            voices.setIncluded(current.clips[used], in: current, false)
            let after = voices.voice(id: voice.voiceID)?.reference(for: .natural, in: root)?.clip.lastPathComponent ?? "no clip"
            report.line("MEASURE Clip left out: Natural now reads \(after) instead of \(current.clips[used].file)")
        }
        if let other = voices.voices.first(where: { $0.id != voice.id }) {
            let folder = other.folder(in: root)
            voices.delete(other)
            report.line("MEASURE Remove Voice: \(other.name)'s folder \(FileManager.default.fileExists(atPath: folder.path) ? "is still there" : "is gone"), \(voices.voices.count) voice(s) left")
        }
        if let first = takes.first?.file {
            let paced = directory.appendingPathComponent("voices-live-take-paced-0.85.wav")
            try? FileManager.default.removeItem(at: paced)
            do {
                try StudioAudio.paced(first, rate: 0.85, to: paced)
                let ratio = StudioAudio.seconds(of: paced) / max(0.01, StudioAudio.seconds(of: first))
                (abs(ratio - 1 / 0.85) < 0.08 ? report.pass : report.fail)("Pace", String(format: "0.85x pace is %.2fx as long (%.2f expected), peak %.3f", ratio, 1 / 0.85, peakLevel(paced)))
            } catch {
                report.fail("Pace", error.localizedDescription)
            }
        }

        // 7. Record My Voice, with a Mac voice reading the passage into a file in place of the
        // microphone: the take made into a voice that's yours and approved, the take deleted.
        // New, so it reports (MEASURE) and doesn't fail the run yet.
        sampler.phase = "record my voice"
        let take = voices.takesFolder.appendingPathComponent("voices-live-take.wav")
        try? FileManager.default.createDirectory(at: voices.takesFolder, withIntermediateDirectories: true)
        let read = await timed { try await SyntheticConversation.writeSolo(to: take, text: OwnVoiceTake.passage) }
        if case .failure(let error) = read.result { report.line("MEASURE Record My Voice: the take couldn't be written: \(error.localizedDescription)"); return }
        start = Date()
        let outcome = await voices.makeOwnVoice(from: take)
        switch outcome {
        case .made(let mine):
            let clip = mine.clips.first
            report.line(String(format: "MEASURE Record My Voice: \"%@\", consent %@, approved %@, clip %.1f s, background %.0f dB, in %@: %@",
                               mine.name, mine.consent ?? "none", mine.isApproved ? "yes" : "no", clip?.seconds ?? 0,
                               clip?.evidence?.backgroundDB ?? 0, seconds(Date().timeIntervalSince(start)), clip?.transcript ?? ""))
        case .failed(let reason):
            report.line("MEASURE Record My Voice: not made (\(reason)) in \(seconds(Date().timeIntervalSince(start)))")
        }
        report.line("MEASURE Record My Voice: take deleted \(!FileManager.default.fileExists(atPath: take.path)), working folder gone \(!FileManager.default.fileExists(atPath: take.deletingPathExtension().path))")
    }

    /// Whether two takes differ: lengths, then the mean sample difference over the shorter.
    private static func difference(_ a: URL, _ b: URL) -> (differs: Bool, text: String) {
        func samples(_ url: URL) -> [Float] {
            guard let file = try? AVAudioFile(forReading: url),
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData else { return [] }
            return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }
        let x = samples(a), y = samples(b)
        let count = min(x.count, y.count)
        guard count > 0 else { return (true, "unreadable") }
        var total: Float = 0
        for i in 0..<count { total += abs(x[i] - y[i]) }
        let mean = total / Float(count)
        return (x.count != y.count || mean > 0.0005, String(format: "%d vs %d samples, mean difference %.5f", x.count, y.count, mean))
    }

    /// Until the running job ends, logging its stage every 15 s.
    private static func wait(for voices: RecordedVoices, limit: TimeInterval, report: Report, sampler: HelperMemorySampler) async {
        let start = Date()
        var logged = Date.distantPast
        try? await Task.sleep(for: .milliseconds(200))
        while voices.isBusy {
            if sampler.overCeiling {
                voices.cancel(); sampler.killHelper()
                report.line("  stopped: the helper went over \(memoryCeiling / 1_048_576) MB")
                return
            }
            if Date().timeIntervalSince(start) > limit {
                voices.cancel()
                report.line("  stopped: over \(Int(limit)) s")
                try? await Task.sleep(for: .seconds(5))
                return
            }
            if Date().timeIntervalSince(logged) >= 15, let job = voices.job {
                logged = Date()
                print(String(format: "voices-live %@: %@ %.0f%% (%@)", sampler.phase, job.stage, job.fraction * 100, sampler.summary))
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func timed<T>(_ body: () async throws -> T) async -> (result: Result<T, Error>, time: TimeInterval) {
        let start = Date()
        do { return (.success(try await body()), Date().timeIntervalSince(start)) } catch { return (.failure(error), Date().timeIntervalSince(start)) }
    }

    private static func seconds(_ time: TimeInterval) -> String { String(format: "%.1f s", time) }

    private static func clipSeconds(_ path: String) -> String {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return "unreadable" }
        return String(format: "%.1f s", Double(file.length) / file.fileFormat.sampleRate)
    }

    private static func peakLevel(_ url: URL) -> Float {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[0][i])) }
        return peak
    }

    /// voices-live.txt, written after every line so a crash leaves what ran.
    @MainActor final class Report {
        let file: URL
        private var lines: [String] = []
        private(set) var failures = 0
        init(file: URL) { self.file = file }
        func line(_ text: String) {
            print("voices-live: " + text)
            lines.append(text)
            try? lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        }
        func pass(_ step: String, _ detail: String) { line("PASS \(step): \(detail)") }
        func fail(_ step: String, _ detail: String) { failures += 1; line("FAIL \(step): \(detail)") }
    }
}

/// Two of the Mac's voices taking turns (`AVSpeechSynthesizer.write`), mono 24 kHz, each with
/// one long stretch on their own and nothing but speech.
@available(macOS 15, *)
enum SyntheticConversation {
    struct Failure: LocalizedError { let errorDescription: String? }

    static let rate = 24_000.0

    /// (speaker, words): 0 and 1 alternate; the first turn of each runs well over 10 s.
    static let turns: [(Int, String)] = [
        (0, "Good morning. I wanted to walk you through the plan for the garden this spring, because there is a lot to get done. First we clear the old beds along the fence, then we turn the soil, add compost, and wait a week before planting anything at all."),
        (1, "That sounds sensible to me. I have been reading about the north corner, where the shade lasts most of the afternoon. Ferns and hostas would do well there, and we could put a small bench under the old apple tree so someone can sit and read in the cool. My sister grew foxgloves in a spot just like it, and they came back taller every single year without any help from her at all."),
        (0, "I like the bench. What about the vegetables? Tomatoes need full sun, so they should go by the south wall."),
        (1, "Agreed. Beans and peas can climb the trellis next to them, and the herbs can stay in pots by the kitchen door, where they are easy to reach while cooking."),
        (0, "Then we only need to decide on the path. Gravel is cheap and drains well, but stone looks better and lasts longer, even if it takes a whole weekend to lay."),
        (1, "Let us go with stone. If we start on Saturday morning, we can have the path finished by Sunday evening, and celebrate with dinner outside."),
    ]

    /// Writes the conversation; returns a one-line summary.
    @MainActor static func write(to url: URL) async throws -> String {
        let voices = try pick()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        var samples: [Float] = []
        var spoken = [0.0, 0.0], longest = [0.0, 0.0]
        samples += [Float](repeating: 0, count: Int(rate * 0.5))
        for (speaker, text) in turns {
            let piece = try await speak(text, voice: voices[speaker], format: format)
            let length = Double(piece.count) / rate
            spoken[speaker] += length
            longest[speaker] = max(longest[speaker], length)
            samples += piece
            samples += [Float](repeating: 0, count: Int(rate * 0.7))
        }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw Failure(errorDescription: "no buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
        let total = Double(samples.count) / rate
        guard (60...90).contains(total), longest.allSatisfy({ $0 >= 10 }) else {
            throw Failure(errorDescription: String(format: "the recording is %.1f s with longest turns %.1f and %.1f s", total, longest[0], longest[1]))
        }
        return String(format: "%.1f s, %@ (%.1f s, longest turn %.1f s) and %@ (%.1f s, longest turn %.1f s)",
                      total, voices[0].name, spoken[0], longest[0], voices[1].name, spoken[1], longest[1])
    }

    /// The first voice alone, a different passage, for the second recording.
    static let solo = "This is a second recording, made on another day, of the same person reading on their own. It has no one else in it, just a steady voice telling a short story about a lighthouse keeper who kept a garden on the rocks, and who planted rows of lavender that the wind carried across the bay every summer evening."

    /// The first voice of the conversation alone reading `text`; returns a one-line summary.
    @MainActor static func writeSolo(to url: URL, text: String = SyntheticConversation.solo) async throws -> String {
        let voice = try pick()[0]
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        var samples = [Float](repeating: 0, count: Int(rate * 0.5))
        samples += try await speak(text, voice: voice, format: format)
        samples += [Float](repeating: 0, count: Int(rate * 0.5))
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw Failure(errorDescription: "no buffer")
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try file.write(from: buffer)
        return String(format: "%.1f s of %@ alone", Double(samples.count) / rate, voice.name)
    }

    /// Samantha (US) and Daniel (UK), or else any two English voices of different genders.
    private static func pick() throws -> [AVSpeechSynthesisVoice] {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice) }
        let first = english.first { $0.name == "Samantha" } ?? english.first { $0.gender == .female }
        let second = english.first { $0.name == "Daniel" } ?? english.first { $0.gender == .male && $0 != first }
        guard let first, let second else { throw Failure(errorDescription: "two English voices aren't installed") }
        return [first, second]
    }

    /// One utterance as mono samples at `format`'s rate.
    @MainActor private static func speak(_ text: String, voice: AVSpeechSynthesisVoice, format: AVAudioFormat) async throws -> [Float] {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let buffers: [AVAudioPCMBuffer] = await withCheckedContinuation { continuation in
            let collected = Collected(continuation)
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                // An empty buffer can come between sentences too: done once nothing follows it.
                if pcm.frameLength == 0 { collected.settle() } else { collected.append(copy(pcm)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { collected.finish() }
        }
        _ = synthesizer
        guard let source = buffers.first?.format, let converter = AVAudioConverter(from: source, to: format) else {
            throw Failure(errorDescription: "\(voice.name) wrote no audio")
        }
        let frames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        let capacity = AVAudioFrameCount(Double(frames) * format.sampleRate / source.sampleRate) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw Failure(errorDescription: "no buffer") }
        var queue = buffers[...]
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            guard let next = queue.popFirst() else { status.pointee = .endOfStream; return nil }
            status.pointee = .haveData
            return next
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in 0..<min(source.count, target.count) {
            memcpy(target[index].mData, source[index].mData, Int(min(source[index].mDataByteSize, target[index].mDataByteSize)))
        }
        return copy
    }

    private final class Collected: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock()
        private var buffers: [AVAudioPCMBuffer] = []
        private var continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>?
        init(_ continuation: CheckedContinuation<[AVAudioPCMBuffer], Never>) { self.continuation = continuation }
        private var generation = 0
        func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { buffers.append(buffer); generation += 1 } }
        func settle() {
            let seen = lock.withLock { generation }
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [self] in
                if lock.withLock({ generation }) == seen { finish() }
            }
        }
        func finish() {
            let (continuation, buffers) = lock.withLock { () -> (CheckedContinuation<[AVAudioPCMBuffer], Never>?, [AVAudioPCMBuffer]) in
                defer { self.continuation = nil }
                return (self.continuation, self.buffers)
            }
            continuation?.resume(returning: buffers)
        }
    }
}

/// The voice helper's memory, sampled twice a second: its physical footprint (what Activity
/// Monitor shows) and the kernel's lifetime peak for each helper process seen, with the phase in
/// which that peak rose (it catches what falls between two samples). With `killsAtCeiling` the
/// helper is stopped at the first sample past the ceiling rather than when the caller looks.
final class HelperMemorySampler: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let ceiling: UInt64
    private let killsAtCeiling: Bool
    private var rises: [String: UInt64] = [:]
    private var timer: DispatchSourceTimer?
    private var peaks: [String: UInt64] = [:]
    private var lifetime: UInt64 = 0
    private var pids: Set<pid_t> = []
    private var over = false
    private var currentPhase = "start"

    init(ceiling: UInt64, killsAtCeiling: Bool = false) {
        self.ceiling = ceiling
        self.killsAtCeiling = killsAtCeiling
    }

    var phase: String {
        get { lock.withLock { currentPhase } }
        set { lock.withLock { currentPhase = newValue } }
    }
    var overCeiling: Bool { lock.withLock { over } }

    var summary: String {
        lock.withLock {
            let phases = peaks.sorted { $0.key < $1.key }.map { "\($0.key) \(Self.mb($0.value))" }.joined(separator: ", ")
            let risen = rises.sorted { $0.key < $1.key }.map { "\($0.key) \(Self.mb($0.value))" }.joined(separator: ", ")
            return "lifetime max \(Self.mb(lifetime)) across \(pids.count) process(es); sampled by phase: \(phases.isEmpty ? "none" : phases)"
                + "; lifetime max reached by phase: \(risen.isEmpty ? "none" : risen)"
        }
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    func stop() { timer?.cancel(); timer = nil; sample() }

    func killHelper() { for pid in Self.helpers() { kill(pid, SIGKILL) } }

    private func sample() {
        for pid in Self.helpers() {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { continue }
            let kill = lock.withLock { () -> Bool in
                pids.insert(pid)
                peaks[currentPhase] = max(peaks[currentPhase] ?? 0, info.ri_phys_footprint)
                if info.ri_lifetime_max_phys_footprint > lifetime {
                    lifetime = info.ri_lifetime_max_phys_footprint
                    rises[currentPhase] = max(rises[currentPhase] ?? 0, lifetime)
                }
                if info.ri_phys_footprint > ceiling { over = true }
                return over && killsAtCeiling
            }
            if kill { Darwin.kill(pid, SIGKILL) }
        }
    }

    private static func helpers() -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }
        return pids.prefix(count).filter { pid in
            var name = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return false }
            return String(cString: name) == "MacSpacesVoiceHelper"
        }
    }

    private static func mb(_ bytes: UInt64) -> String { "\(bytes / 1_048_576) MB" }
}
#endif
