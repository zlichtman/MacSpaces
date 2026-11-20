import SwiftUI

#if DEBUG
/// Check renders for Studio (`MACSPACES_DEMO_KIND=tools`, stopping here with
/// `MACSPACES_DEMO_ONLY=studio`): a script with words being read and takes, a script with no
/// takes, the voices (several recordings, one being sorted; voices to approve and approved, one
/// with its clips open; the consent question; Record My Voice's states, with a synthetic level),
/// Dictate, in dark and light Nooks and the Midnight and Everforest scenes. Never published; no
/// audio is made or recorded and nothing real is read.
extension WebsiteDemoClips {
    static func studioChecks(shoot: (AnyView, NSSize, String) -> Void) {
        let theme = ThemeStore.shared
        let prompter = ScriptPrompter.shared
        let studio = StudioModel.shared
        let voices = RecordedVoices.shared
        let recorder = OwnVoiceRecorder.shared
        let savedScripts = prompter.scripts, savedSelection = prompter.selectedID, savedFamily = theme.family
        let savedVoice = studio.voiceID, savedSection = studio.section
        defer {
            prompter.scripts = savedScripts
            prompter.selectedID = savedSelection
            theme.selectFamily(savedFamily)
            studio.voiceID = savedVoice
            studio.section = savedSection
            voices.setPreview(states: [:], voices: [])
            recorder.setPreview(.closed)
            DictationModel.shared.text = ""
        }

        let intro = """
        Welcome back to the show. Today we're talking about slow mornings, \
        and why the best ideas arrive when you stop chasing them.

        First, a quick thank you to everyone who wrote in last week.
        """
        let script = ScriptPrompter.Script(title: "Episode 12 intro", text: intro)
        let blank = ScriptPrompter.Script(title: "Launch video", text: "Hi, I'm Sam. In the next two minutes I'll show you what we built.")
        prompter.scripts = [script, blank, ScriptPrompter.Script(title: "Wedding toast", text: "To the two of you.")]
        prompter.selectedID = script.id

        let gb: Int64 = 1_000_000_000
        let sam = RecordedVoice(id: UUID(), name: "Sam", transcript: "Welcome back to the show.", fingerprint: nil,
                                seconds: 18, created: Date(), consent: "mine",
                                deliveries: [.init(delivery: .soft, file: "", transcript: "Take your time.", seconds: 9),
                                             .init(delivery: .upbeat, file: "", transcript: "This is so good!", seconds: 7)])
        let ada = RecordedVoice(id: UUID(), name: "Ada", transcript: "Thanks for having me.", fingerprint: nil,
                                seconds: 12, created: Date(), consent: "permission")
        let models: [String: VoiceModelStore.State] = ["sorting": .downloaded(bytes: 263_000_000), "standard-small": .downloaded(bytes: 2 * gb)]
        let reading = (intro as NSString).range(of: "First, a quick thank you to everyone who wrote in last week.")
        let making = StudioModel.Making(scriptID: script.id, text: "First, a quick thank you to everyone who wrote in last week.",
                                        range: reading, voiceName: "Sam", recorded: true)
        func take(_ text: String, _ voice: String, minutes: Double, seconds: Double, starred: Bool = false, pace: Double = 1,
                  delivery: String? = nil) -> StudioTake {
            let recorded = voice == "Sam"
            let id: String = recorded ? sam.voiceID : ""
            let engine: String? = recorded ? "Qwen3-TTS 0.6B" : nil
            let seed: UInt64? = recorded ? UInt64(minutes * 977) : nil
            let created = Date(timeIntervalSinceNow: -minutes * 60)
            return StudioTake(id: UUID(), text: text, voice: id, voiceName: voice, engine: engine, seed: seed, style: nil,
                              pace: pace, seconds: seconds, created: created, starred: starred, delivery: delivery)
        }
        let first = "Welcome back to the show."
        let takes = [
            take(first, "Sam", minutes: 1, seconds: 2.4, starred: true),
            take(first, "Sam", minutes: 2, seconds: 2.7, delivery: "upbeat"),
            take(first, "Sam", minutes: 3, seconds: 2.5, pace: 0.9),
            take(intro, "Automatic", minutes: 6, seconds: 14.2),
        ]
        let page = NSSize(width: 620, height: 346)
        func render(_ name: String, size: NSSize = page) {
            let view = AnyView(StudioPage(prompter: prompter))
            shoot(AnyView(view.frame(width: size.width, height: size.height)
                    .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                    .environment(\.colorScheme, theme.notch.colorScheme).tint(theme.notch.accent)),
                  size, "check-studio-" + name)
        }

        for (look, family) in [("dark", ThemeFamily.macspaces), ("light", .paper), ("midnight", .midnight), ("everforest", .everforest)] {
            theme.selectFamily(family)
            studio.section = .scripts
            voices.setPreview(states: models, voices: [sam, ada],
                              job: RecordedVoices.Job(kind: .speak, stage: "Speaking", fraction: 0.45))
            studio.voiceID = sam.voiceID
            studio.setPreview(scriptID: script.id, takes: takes, making: making)
            render("reading-" + look)
            guard look == "dark" || look == "light" else { continue }
            shoot(AnyView(StudioPage(prompter: prompter).menuPanels.padding(12).frame(width: 820, height: 560, alignment: .topLeading)
                    .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                    .environment(\.colorScheme, theme.notch.colorScheme).tint(theme.notch.accent)),
                  NSSize(width: 820, height: 560), "check-studio-menus-" + look)
            voices.setPreview(states: models, voices: [sam, ada])
            studio.setPreview(scriptID: script.id, takes: takes, making: nil)
            render("takes-" + look)
            prompter.selectedID = blank.id
            studio.voiceID = ""
            studio.setPreview(scriptID: blank.id, takes: [], making: nil)
            render("empty-" + look)
            prompter.selectedID = script.id
            studio.section = .voices
            // Three recordings dropped at once: one sorted, one being sorted, one waiting; the same
            // host heard in two of them is one voice with two clips.
            let first = UUID(), second = UUID(), third = UUID()
            let recordings = [
                VoiceRecording(id: first, name: "Episode 11.m4a", path: "/dev/null", added: Date(), state: .sorted, people: 2),
                VoiceRecording(id: second, name: "Episode 12.m4a", path: "/dev/null", added: Date(), state: .sorting),
                VoiceRecording(id: third, name: "Interview.mov", path: "/dev/null", added: Date(), state: .waiting),
            ]
            func clip(_ file: String, _ words: String, _ seconds: Double, _ recording: UUID, _ name: String,
                      included: Bool = true, delivery: VoiceDelivery = .natural) -> VoiceSamples.Sample {
                VoiceSamples.Sample(file: file, transcript: words, seconds: seconds, delivery: delivery, included: included,
                                    fingerprint: nil, recording: recording, recordingName: name)
            }
            let host = RecordedVoice(id: UUID(), name: "Host", transcript: "Welcome back to the show.", fingerprint: nil, seconds: 14,
                                     created: Date(), samples: [clip("a.wav", "Welcome back to the show.", 14, first, "Episode 11.m4a"),
                                                                clip("b.wav", "Thanks for listening, see you next week.", 9, second, "Episode 12.m4a"),
                                                                clip("c.wav", "Take a breath with me.", 8, first, "Episode 11.m4a",
                                                                     included: false, delivery: .soft)],
                                     approved: false)
            let guest = RecordedVoice(id: UUID(), name: "Guest 1", transcript: "Thanks for having me.", fingerprint: nil, seconds: 11,
                                      created: Date(), samples: [clip("d.wav", "Thanks for having me.", 11, first, "Episode 11.m4a")],
                                      approved: false)
            voices.setPreview(states: models, recordings: recordings, voices: [host, guest, sam, ada],
                              job: RecordedVoices.Job(kind: .sort, stage: "Finding who's speaking", fraction: 0.3),
                              folderBytes: 2_480_000_000)
            render("voices-" + look)
            shoot(AnyView(StudioVoicesList(onRead: { _ in }, open: [host.id]).padding(12).frame(width: 460, height: 330)
                    .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                    .environment(\.colorScheme, theme.notch.colorScheme).tint(theme.notch.accent)),
                  NSSize(width: 460, height: 330), "check-studio-clips-" + look)
            shoot(AnyView(StudioVoicesList(onRead: { _ in }, asking: host.id).padding(12).frame(width: 460, height: 300)
                    .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                    .environment(\.colorScheme, theme.notch.colorScheme).tint(theme.notch.accent)),
                  NSSize(width: 460, height: 300), "check-studio-consent-" + look)
            // Record My Voice: ready, recording (a synthetic level, no microphone), recorded, being
            // made and failed, then the whole page while recording.
            let takeStates: [(String, OwnVoiceRecorder.Phase, Float, Double, RecordedVoices.Job?)] = [
                ("ready", .ready, 0, 0, nil),
                ("recording", .recording, 0.62, 11, nil),
                ("recorded", .recorded, 0, 18, nil),
                ("preparing", .preparing, 0, 18,
                 RecordedVoices.Job(kind: .prepare, stage: "Writing down what you said", fraction: 0.55)),
                ("failed", .failed(OwnVoiceTake.Problem.tooNoisy.message), 0, 18, nil),
            ]
            for (state, phase, level, seconds, job) in takeStates {
                voices.setPreview(states: models, voices: [sam, ada], job: job)
                recorder.setPreview(phase, level: level, seconds: seconds)
                shoot(AnyView(StudioVoicesList(onRead: { _ in }).padding(12).frame(width: 460, height: 330)
                        .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                        .environment(\.colorScheme, theme.notch.colorScheme).tint(theme.notch.accent)),
                      NSSize(width: 460, height: 330), "check-studio-record-\(state)-" + look)
            }
            recorder.setPreview(.recording, level: 0.4, seconds: 6)
            voices.setPreview(states: models, voices: [sam, ada], folderBytes: 2_480_000_000)
            render("voices-record-" + look)
            recorder.setPreview(.closed)
            voices.setPreview(states: models, voices: [])
            render("voices-empty-" + look)
            studio.section = .dictate
            DictationModel.shared.text = "Here's the plan for Friday: record the intro first, then the interview."
            render("dictate-" + look)
            studio.section = .voices
            voices.setPreview(states: [:], voices: [])
            render("voices-no-models-" + look)
        }
        theme.selectFamily(.macspaces)
        studio.section = .scripts
        voices.setPreview(states: models, voices: [sam, ada])
        studio.voiceID = sam.voiceID
        studio.setPreview(scriptID: script.id, takes: takes, making: nil)
    }
}
#endif
