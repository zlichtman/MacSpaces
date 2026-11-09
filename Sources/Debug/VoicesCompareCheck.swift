#if DEBUG
import AppKit
import Foundation

/// `MACSPACES_QA_SCOPE=voices-compare`, run by `Scripts/compare-siren.sh` on the owner's Mac only
/// (never in preflight, CI or Feature QA): MacSpaces' voice engine side by side with Siren's on
/// real recordings. For each recording in `MACSPACES_COMPARE_INPUT` it sorts the recording through
/// the voice helper, keeps the most heard person's clip as the reference, reads each line (from
/// `MACSPACES_COMPARE_LINES`, else three of its own) Fast and with Best Quality on the same seed,
/// optionally runs Siren's `siren-check` command (`MACSPACES_COMPARE_SIREN`) on the same reference
/// and lines and picks up takes exported from the Siren app (`MACSPACES_COMPARE_SIREN_TAKES`,
/// named <recording>-<line>.wav), then scores every WAV's likeness to the reference with the
/// fingerprint model that sorts and joins voices. Models come from `MACSPACES_COMPARE_HUB` (the
/// script's clone of the downloaded ones, or several hubs separated by colons, each compared in
/// turn, such as one with Music removal and one without) and are never downloaded. With
/// `MACSPACES_COMPARE_TRUTH`, a folder of the same recordings without what was mixed into them,
/// each reference is also scored against its clean recording. Writes the WAVs, report.txt and
/// report.json to the output folder, and stops the helper past 4.5 GB.
@available(macOS 15, *)
@MainActor enum VoicesCompareCheck {
    static let defaultLines = [
        "Thanks for calling. I'll get back to you as soon as I can, probably later this afternoon.",
        "The forecast looks good for Saturday, so let's meet at the park around ten and bring something to eat.",
        "Honestly, I didn't expect it to work the first time. But here we are, and it sounds better than I hoped.",
    ]
    static let audioTypes: Set<String> = ["wav", "m4a", "mp3", "aif", "aiff", "caf", "flac", "mp4", "mov", "aac"]

    struct Row: Codable {
        var hub = ""
        let recording: String
        let line: Int
        let kind: String
        let file: String
        let seconds: Double
        let makeSeconds: Double?
        var likeness: Double?
    }

    static func run(to directory: URL) {
        Task { @MainActor in
            await steps(directory)
            NSApp.terminate(nil)
        }
    }

    private static func steps(_ output: URL) async {
        // The script passes every option, empty when not given.
        let env = ProcessInfo.processInfo.environment.filter { !$0.value.isEmpty }
        var log: [String] = []
        func say(_ text: String) {
            print("voices-compare: " + text)
            log.append(text)
            try? log.joined(separator: "\n").appending("\n").write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        }
        let fm = FileManager.default
        guard let inputPath = env["MACSPACES_COMPARE_INPUT"] else { say("FAIL no MACSPACES_COMPARE_INPUT folder"); return }
        let input = URL(fileURLWithPath: inputPath, isDirectory: true)
        let recordings = ((try? fm.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)) ?? [])
            .filter { audioTypes.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !recordings.isEmpty else { say("FAIL no recordings in \(input.path)"); return }
        let lines = env["MACSPACES_COMPARE_LINES"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            .map { $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            .flatMap { $0.isEmpty ? nil : $0 } ?? defaultLines
        let hubs = (env["MACSPACES_COMPARE_HUB"] ?? VoicePaths.models().path).split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        let truth = env["MACSPACES_COMPARE_TRUTH"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard let hub = hubs.first else { say("FAIL no hub"); return }
        let store = VoiceModelStore(hub: hub)
        guard store.state(of: .sorting).isDownloaded else { say("FAIL Finding voices isn't downloaded in \(hub.path)"); return }
        let downloaded = store.downloaded()
        guard let engine = VoiceModel.named(env["MACSPACES_COMPARE_ENGINE"]).flatMap({ downloaded.contains($0.id) && $0.speaks ? $0 : nil })
                ?? VoiceModel.speakingEngine(chosen: nil, downloaded: downloaded) else {
            say("FAIL no voice engine is downloaded in \(hub.path)"); return
        }
        let siren = env["MACSPACES_COMPARE_SIREN"].map { URL(fileURLWithPath: $0) }
        let sirenTakes = env["MACSPACES_COMPARE_SIREN_TAKES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        say("Engine: \(engine.title) (\(engine.modelName)); \(recordings.count) recording(s); \(lines.count) line(s)")
        say("Siren: \(siren?.path ?? "no siren-check given"); Siren app takes: \(sirenTakes?.path ?? "none given")")

        let client = VoiceHelperClient()
        let sampler = HelperMemorySampler(ceiling: VoicesLiveCheck.memoryCeiling, killsAtCeiling: true)
        sampler.start()
        defer { sampler.stop() }
        var rows: [Row] = []
        for hub in hubs {
            let hubName = hubs.count > 1 ? hub.lastPathComponent : ""
            if hubs.count > 1 {
                say("")
                say("==== Hub \(hubName): \(VoiceModelStore(hub: hub).downloaded().sorted().joined(separator: ", "))")
            }
            for (number, recording) in recordings.enumerated() {
                let base = recording.deletingPathExtension().lastPathComponent
                let safe = String(base.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.prefix(40))
                let folder = output.appendingPathComponent((hubName.isEmpty ? "" : hubName + "-") + String(format: "%02d-", number + 1) + safe,
                                                           isDirectory: true)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                // The helper traces each speak request's memory into this file (Debug builds only).
                fm.createFile(atPath: folder.appendingPathComponent("helper-memory.txt").path, contents: nil)
                say("")
                say("== \(recording.lastPathComponent)")

                // The reference: the most heard person's clip, as sorting chooses it.
                sampler.phase = "sort \(number + 1)" + (hubName.isEmpty ? "" : " " + hubName)
                let sorting = folder.appendingPathComponent("sorting", isDirectory: true)
                defer { try? fm.removeItem(at: sorting) }
                let started = Date()
                let result: VoiceHelperMessage.SortResult
                do {
                    result = try await client.sort(.init(files: [recording.path], output: sorting.path, hub: hub.path))
                } catch {
                    say("FAIL sort: \(error.localizedDescription)"); continue
                }
                for skipped in result.skipped { say("  skipped: \(skipped)") }
                guard let person = result.people.first, !person.transcript.isEmpty else { say("FAIL nobody with words was found"); continue }
                let reference = folder.appendingPathComponent("reference.wav")
                try? fm.removeItem(at: reference)
                guard (try? fm.copyItem(at: URL(fileURLWithPath: person.clip), to: reference)) != nil else { say("FAIL the clip couldn't be kept"); continue }
                try? person.transcript.write(to: folder.appendingPathComponent("reference.txt"), atomically: true, encoding: .utf8)
                say(String(format: "Reference: %@, %.1f s of them heard, clip %.1f s, sorted in %.0f s: %@", person.label, person.seconds,
                           StudioAudio.seconds(of: reference), Date().timeIntervalSince(started), person.transcript))
                if let note = person.note { say("  note: \(note)") }
                if let evidence = person.evidence {
                    say(String(format: "  clip: likeness to the person %@, %@ dB above its background",
                               evidence.likeness.map { String(format: "%.3f", $0) } ?? "-",
                               evidence.backgroundDB.map { String(format: "%.1f", $0) } ?? "-"))
                }
                // The same recording without what was mixed in: how like the clean voice the reference is.
                if let truth {
                    let clean = truth.appendingPathComponent(recording.lastPathComponent)
                    let file = folder.appendingPathComponent("clean-recording.wav")
                    try? fm.removeItem(at: file)
                    if (try? fm.copyItem(at: clean, to: file)) != nil {
                        rows.append(Row(recording: base, line: 0, kind: "Clean recording", file: file.lastPathComponent,
                                        seconds: StudioAudio.seconds(of: file), makeSeconds: nil))
                    }
                }
                if result.people.count > 1 { say("  \(result.people.count) people found; the most heard is compared") }

                // MacSpaces: Fast and Best Quality on the same seed.
                for (index, line) in lines.enumerated() {
                    for best in [false, true] {
                        if sampler.overCeiling { break }
                        sampler.phase = best ? "best quality" : "fast"
                        let file = folder.appendingPathComponent("macspaces-\(best ? "best" : "fast")-\(index + 1).wav")
                        let start = Date()
                        do {
                            let made = try await client.speak(.init(text: line, clip: reference.path, transcript: person.transcript,
                                                                    engine: engine.id, hub: hub.path, output: file.path,
                                                                    seed: UInt64(100 + index), takes: best ? TakeChoice.attempts : nil))
                            rows.append(Row(recording: base, line: index + 1, kind: best ? "MacSpaces Best Quality" : "MacSpaces Fast",
                                            file: made.lastPathComponent, seconds: StudioAudio.seconds(of: made),
                                            makeSeconds: Date().timeIntervalSince(start)))
                        } catch {
                            say("FAIL \(best ? "Best Quality" : "Fast") line \(index + 1): \(error.localizedDescription)")
                        }
                    }
                }
                if sampler.overCeiling { say("FAIL the helper went past \(VoicesLiveCheck.memoryCeiling / 1_048_576) MB; stopped"); sampler.killHelper(); break }

                // Siren: its command on the same reference and lines, and takes exported from the app.
                for (index, line) in lines.enumerated() {
                    if let siren {
                        let file = folder.appendingPathComponent("siren-check-\(index + 1).wav")
                        var arguments = [reference.path, person.transcript, line, file.path]
                        if engine == .standardSmall { arguments.append("--small") }
                        let start = Date()
                        let log = folder.appendingPathComponent("siren-check.log")
                        let status = await Task.detached(priority: .userInitiated) { [siren, arguments, log] in
                            runProcess(siren, arguments, log: log)
                        }.value
                        if status == 0, fm.fileExists(atPath: file.path) {
                            rows.append(Row(recording: base, line: index + 1, kind: "Siren siren-check", file: file.lastPathComponent,
                                            seconds: StudioAudio.seconds(of: file), makeSeconds: Date().timeIntervalSince(start)))
                        } else {
                            say("FAIL siren-check line \(index + 1): exit \(status) (siren-check.log)")
                        }
                    }
                    if let sirenTakes {
                        let exported = sirenTakes.appendingPathComponent("\(base)-\(index + 1).wav")
                        let file = folder.appendingPathComponent("siren-app-\(index + 1).wav")
                        try? fm.removeItem(at: file)
                        if (try? fm.copyItem(at: exported, to: file)) != nil {
                            rows.append(Row(recording: base, line: index + 1, kind: "Siren app", file: file.lastPathComponent,
                                            seconds: StudioAudio.seconds(of: file), makeSeconds: nil))
                        }
                    }
                }

                // Likeness to the reference, every WAV with the same measure (the voice model is let go first).
                sampler.phase = "likeness"
                for index in rows.indices where rows[index].recording == base && rows[index].hub.isEmpty { rows[index].hub = hubName }
                let mine = rows.indices.filter { rows[$0].recording == base && rows[$0].hub == hubName }
                do {
                    let scores = try await client.likeness(.init(reference: reference.path,
                                                                 files: mine.map { folder.appendingPathComponent(rows[$0].file).path },
                                                                 hub: hub.path))
                    for (row, score) in zip(mine, scores) { rows[row].likeness = score }
                } catch {
                    say("FAIL likeness: \(error.localizedDescription)")
                }
                say("line  kind                      length  made in  likeness")
                for row in mine.map({ rows[$0] }) {
                    say(String(format: "%4d  %@  %5.1f s  %@  %@", row.line, padded(row.kind) as NSString, row.seconds,
                               row.makeSeconds.map { String(format: "%5.0f s", $0) } ?? "      -",
                               row.likeness.map { String(format: "%.3f", $0) } ?? "-"))
                }
            }
            if sampler.overCeiling { break }
        }

        say("")
        say("Average likeness to the reference (higher is more like them):")
        for hub in hubs {
            let hubName = hubs.count > 1 ? hub.lastPathComponent : ""
            if !hubName.isEmpty { say("  \(hubName):") }
            for kind in ["Clean recording", "MacSpaces Fast", "MacSpaces Best Quality", "Siren siren-check", "Siren app"] {
                let scores = rows.filter { $0.kind == kind && $0.hub == hubName }.compactMap(\.likeness)
                guard !scores.isEmpty else { continue }
                say(String(format: "  %@ %.3f over %d take(s)", padded(kind) as NSString, scores.reduce(0, +) / Double(scores.count), scores.count))
            }
        }
        say("Helper peak footprint: \(sampler.summary)")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(rows).write(to: output.appendingPathComponent("report.json"))
    }

    private static func padded(_ text: String) -> String { text.padding(toLength: 24, withPad: " ", startingAt: 0) }

    /// Runs a command to the end, its output into `log`; its exit status (-1 if it couldn't start).
    nonisolated private static func runProcess(_ executable: URL, _ arguments: [String], log: URL) -> Int32 {
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: log) else { return -1 }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
#endif
