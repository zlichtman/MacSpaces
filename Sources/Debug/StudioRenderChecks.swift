import SwiftUI
import CoreAudio

#if DEBUG
/// Check renders for Studio (`MACSPACES_DEMO_KIND=tools`, stopping here with
/// `MACSPACES_DEMO_ONLY=studio`): a script with words being read and takes, a script with no
/// takes, the voices (several recordings, one being sorted; voices to approve and approved, one
/// with its clips open; the consent question; Record My Voice's states, with a synthetic level),
/// Dictate, in dark and light Nooks and the Midnight and Everforest scenes. Never published; no
/// audio is made or recorded and nothing real is read.
extension WebsiteDemoClips {
    /// The teleprompter panel as drawn (`PrompterView`), since the real one is hidden from every
    /// capture: a script with sections, stage notes and a point, running and paused, in the
    /// default theme, Midnight and Everforest, then in Serif, Mono, All Caps, at 60% background
    /// over a picture, and with a two-minute target (fine, near, over): `check-prompter-<name>.png`.
    static func prompterChecks(shoot: (AnyView, NSSize, String) -> Void) {
        let theme = ThemeStore.shared
        let prompter = ScriptPrompter.shared
        let saved = (scripts: prompter.scripts, selection: prompter.selectedID, family: theme.family, face: prompter.typeface,
                     caps: prompter.allCaps, opacity: prompter.opacity, size: prompter.textSize)
        defer {
            prompter.scripts = saved.scripts; prompter.selectedID = saved.selection; theme.selectFamily(saved.family)
            prompter.typeface = saved.face; prompter.allCaps = saved.caps; prompter.opacity = saved.opacity; prompter.textSize = saved.size
        }
        let text = """
        # Opening
        Welcome back to the show. [smile] Today we're talking about slow mornings, and why the best ideas arrive when you stop chasing them.

        > Thank the listeners who wrote in
        [pause] First, a quick thank you to everyone who wrote in last week.
        # The news
        Three things happened this week, and only one of them was planned.
        """
        let script = ScriptPrompter.Script(title: "Episode 12", text: text)
        prompter.scripts = [script]
        prompter.selectedID = script.id
        prompter.textSize = .medium
        let size = PrompterPanel.size
        func render(_ name: String, at word: Double, running: Bool, backdrop: Bool = false, covered: Set<Int> = [], elapsed: TimeInterval = 0) {
            prompter.previewPlayback(at: word, running: running, covered: covered, elapsed: elapsed)
            shoot(AnyView(ZStack {
                if backdrop {
                    LinearGradient(colors: [.orange, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                PrompterView(prompter: prompter)
            }
            .frame(width: size.width, height: size.height)), size, "check-prompter-" + name)
        }
        for (name, family) in [("default", ThemeFamily.macspaces), ("midnight", .midnight), ("everforest", .everforest)] {
            theme.selectFamily(family)
            render(name + "-running", at: 6, running: true)
            render(name + "-paused", at: name == "default" ? 0 : 14, running: false)
        }
        theme.selectFamily(.macspaces)
        prompter.typeface = .serif
        render("serif", at: 6, running: true)
        prompter.typeface = .mono
        render("mono", at: 6, running: true)
        prompter.typeface = .rounded
        prompter.allCaps = true
        render("caps", at: 6, running: true)
        prompter.allCaps = false
        prompter.opacity = 0.6
        render("opacity", at: 6, running: true, backdrop: true)
        prompter.opacity = 1
        // A two-minute target: fine, close to it and over it, the point ticked in the last two.
        var timed = script
        timed.target = 120
        prompter.scripts = [timed]
        render("target-fine", at: 6, running: true, elapsed: 42)
        render("target-near", at: 20, running: true, covered: [0], elapsed: 104)
        render("target-over", at: 30, running: false, covered: [0], elapsed: 131)
    }

    /// The Status icon as the menu bar draws it, on a light and a dark bar at four times its
    /// size, each with its number: every reading at rest, the battery charging, low and
    /// critical, and a busy CPU: `check-status-icon.png`. The real icon shows only in MacSpaces itself.
    static func statusIconChecks(shoot: (AnyView, NSSize, String) -> Void) {
        var mac = StatusSnapshot(batteryLevel: 82, minutesToEmpty: 190, cpu: 0.24, memory: 0.56, memoryUsedBytes: 9.1e9, disk: 0.63,
                                 diskFreeBytes: 182e9, networkIn: 1.8e6, networkOut: 0.21e6, wifi: .connected(bars: 3), volume: 0.45)
        var gauges = StatusReading.allCases.map { StatusGauge.gauge($0, mac) }
        // All in One again: weak Wi-Fi and loud; Wi-Fi off, muted and a low battery.
        var other = mac
        other.wifi = .connected(bars: 1); other.volume = 0.9
        gauges.insert(StatusGauge.gauge(.combined, other), at: 1)
        other.wifi = .off; other.muted = true; other.batteryLevel = 15
        gauges.insert(StatusGauge.gauge(.combined, other), at: 2)
        mac.charging = true; mac.onPower = true; mac.batteryLevel = 46
        gauges.append(StatusGauge.gauge(.battery, mac))
        mac.charging = false; mac.onPower = false; mac.batteryLevel = 18
        gauges.append(StatusGauge.gauge(.battery, mac))
        mac.batteryLevel = 7
        gauges.append(StatusGauge.gauge(.battery, mac))
        mac.cpu = 0.97
        gauges.append(StatusGauge.gauge(.cpu, mac))
        func bar(_ dark: Bool) -> some View {
            HStack(spacing: 26) {
                ForEach(Array(gauges.enumerated()), id: \.offset) { _, gauge in
                    HStack(spacing: 8) {
                        let image = StatusIconImage.image(for: gauge, size: 72)
                        if image.isTemplate {
                            Image(nsImage: image).renderingMode(.template).foregroundColor(dark ? .white : .black)
                        } else {
                            Image(nsImage: image)
                        }
                        Text(gauge.value).font(.system(size: 44, weight: .medium)).monospacedDigit()
                            .foregroundColor(dark ? .white : .black)
                    }
                }
            }
            .padding(.horizontal, 30).frame(height: 110).frame(maxWidth: .infinity, alignment: .leading)
            .background(dark ? Color(white: 0.13) : Color(white: 0.93))
        }
        let size = NSSize(width: 3000, height: 220)
        shoot(AnyView(VStack(spacing: 0) { bar(false); bar(true) }.frame(width: size.width, height: size.height)), size, "check-status-icon")

        // The menu, filled without a menu-bar icon: its lines, ticks and what its clicks do.
        let menu = NSMenu(), entries = StatusIconMenu()
        var chosen = StatusReading.combined, number = false, off = false
        var output = AudioDeviceID(1)
        let outputs = [AudioOutput(id: 1, name: "MacBook Speakers", symbol: "laptopcomputer"), AudioOutput(id: 2, name: "Studio Monitors", symbol: "hifispeaker.fill")]
        let earbuds = BluetoothDeviceSnapshot(id: "a", name: "Keyboard", batteryPercent: 64)
        let mouse = BluetoothDeviceSnapshot(id: "b", name: "Mouse", batteryPercent: nil)
        mac = StatusSnapshot(batteryLevel: 82, minutesToEmpty: 190, cpu: 0.24, memory: 0.56, memoryUsedBytes: 9.1e9, disk: 0.63,
                             diskFreeBytes: 182e9, networkIn: 1.8e6, networkOut: 0.21e6, wifi: .connected(bars: 3), volume: 0.45)
        func fill(_ snapshot: StatusSnapshot) {
            entries.fill(menu, snapshot: snapshot, reading: chosen, showsValue: number, devices: [earbuds, mouse],
                         outputs: snapshot.volume == nil ? [] : outputs, currentOutput: output, selectOutput: { output = $0 },
                         choose: { chosen = $0 }, toggleValue: { number.toggle() }, turnOff: { off = true })
        }
        func lines() -> [String] {
            menu.items.map { $0.isSeparatorItem ? "---" : ($0.state == .on ? "✓ " : "  ") + ($0.attributedTitle?.string ?? $0.title) + ($0.isEnabled ? "" : "  (not clickable)") }
        }
        fill(mac)
        var report = ["A MacBook, All in One chosen:"] + lines()

        // The site's Status still (`page-status.png`, the stage's size): the icon in a menu bar
        // with its menu open, and large in four states beside it. The menu's lines are the real
        // menu's, read off it here; its frame is drawn, since an open menu can't be captured.
        var charging = mac, busy = mac, low = mac
        charging.charging = true; charging.onPower = true; charging.batteryLevel = 46
        busy.cpu = 0.97
        low.batteryLevel = 7
        let hero = [(StatusGauge.gauge(.combined, mac), "All in One"), (StatusGauge.gauge(.battery, charging), "Charging"),
                    (StatusGauge.gauge(.cpu, busy), "CPU"), (StatusGauge.gauge(.battery, low), "Low Battery")]
        // The bar shows the number, so the menu's Show the Number is ticked for the picture.
        number = true; fill(mac)
        shoot(AnyView(StatusStill(hero: hero, shown: StatusGauge.gauge(.combined, mac), rows: StatusStill.rows(of: menu))),
              NSSize(width: WebsiteDemoClips.stage.width, height: WebsiteDemoClips.stage.height), "page-status")
        number = false; fill(mac)
        entries.click("Disk", in: menu); entries.click("Show the Number", in: menu); entries.click("Studio Monitors", in: menu)
        fill(mac)
        report += ["", "After clicking Disk, Show the Number and Studio Monitors (chosen: \(chosen.rawValue), number: \(number), output: \(output)):"] + lines()
        chosen = .battery
        fill(StatusSnapshot(cpu: 0.5, memory: 0.4, disk: 0.3))
        report += ["", "A Mac without a battery, Battery still saved:"] + lines()
        entries.click("Turn Off Status Icon", in: menu)
        report += ["", "Turn Off Status Icon clicked: \(off)"]
        if let folder = ProcessInfo.processInfo.environment["MACSPACES_DEMO_OUTPUT"] {
            try? report.joined(separator: "\n").write(toFile: folder + "/check-status-menu.txt", atomically: true, encoding: .utf8)
        }
    }

    /// The Notes page on To-Dos, on synthetic notes in a throwaway file: a day's to-dos across
    /// three notes (times, priorities, estimates), and none, in the default theme, Midnight and
    /// Everforest: `check-todos-<name>.png`.
    static func todoChecks(shoot: (AnyView, NSSize, String) -> Void) {
        let theme = ThemeStore.shared
        let savedFamily = theme.family
        let fixtures = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            theme.selectFamily(savedFamily)
            NotesAppView.qaShowsTasks = false
            NoteTasksPane.preview = nil
            try? FileManager.default.removeItem(at: fixtures)
        }
        let service = NotesService(url: fixtures.appendingPathComponent("notes.json"), legacyText: "")
        for text in ["To-Dos\n- [ ] Call the plumber ~15m !! @14:30\n- [ ] Water the plants\n- [x] Pay rent",
                     "Launch video\nShot list for Friday.\n- [ ] Write the intro ~45m !!!\n- [ ] Record the voiceover ~1h30m\n- [ ] Pick the music ~20m !",
                     "Trip to Lisbon\n- [ ] Book the tram tour @9am\n- [ ] Find a table near the river ~10m",
                     "Book list\nThe long novel first, then the short stories."] {
            if let id = service.create() { service.save(id, text: text) }
        }
        let page = NSSize(width: 620, height: 346)
        func render(_ name: String, _ notes: NotesService) {
            shoot(AnyView(NotesAppView(service: notes).frame(width: page.width, height: page.height)
                    .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
                    .environment(\.colorScheme, theme.notch.colorScheme).tint(theme.notch.accent)),
                  page, "check-todos-" + name)
        }
        NotesAppView.qaShowsTasks = true
        for (name, family) in [("default", ThemeFamily.macspaces), ("midnight", .midnight), ("everforest", .everforest)] {
            theme.selectFamily(family)
            NoteTasksPane.preview = NoteTasksPane.groups(of: service.active)
            render(name, service)
        }
        theme.selectFamily(.macspaces)
        NoteTasksPane.preview = []
        render("none", NotesService(url: fixtures.appendingPathComponent("empty.json"), legacyText: ""))
    }

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
            // The last reading's summary over the editor.
            prompter.previewSummary(PrompterTakeSummary(duration: 96, spokenWords: 214, longestPause: 4.2, points: 2,
                                                        missed: ["Thank the listeners who wrote in"], target: 90), for: script.id)
            render("summary-" + look)
            prompter.previewSummary(nil, for: script.id)
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

/// The site's Status still: see `statusIconChecks`.
private struct StatusStill: View {
    struct Row: Identifiable {
        let id: Int
        var separator = false, ticked = false, enabled = true, header = false
        var image: NSImage?
        var name = "", value = ""
    }

    let hero: [(StatusGauge, String)]
    let shown: StatusGauge
    let rows: [Row]
    /// The menu at its real size: its fifteen lines just fit under the bar.
    private let k: CGFloat = 1
    /// The site shows a still's top 440 pt and fades its outer 6% each side, so everything keeps inside.
    private let inset: CGFloat = 56, visible: CGFloat = 440
    private let bar = WebsiteDemoProfile.notchSize.height

    /// A filled menu's lines: a name and its quieter value (`StatusIconMenu.line` joins them with three spaces).
    static func rows(of menu: NSMenu) -> [Row] {
        menu.items.enumerated().map { index, item in
            let parts = (item.attributedTitle?.string ?? item.title).components(separatedBy: "   ")
            return Row(id: index, separator: item.isSeparatorItem, ticked: item.state == .on, enabled: item.isEnabled,
                       header: item.title == "Sound Output", image: item.image, name: parts[0], value: parts.count > 1 ? parts[1] : "")
        }
    }

    var body: some View {
        let size = WebsiteDemoClips.stage, menuWidth: CGFloat = 336
        ZStack(alignment: .top) {
            DemoWallpaper(colors: ["#262A56", "#453C78", "#7A4E8C", "#C06C84"].map { Color(themeHex: $0) ?? .gray })
            HStack(spacing: 12 * k) {
                Spacer()
                HStack(spacing: 5 * k) {
                    icon(shown, 18 * k)
                    Text(shown.value).font(.system(size: 13 * k, weight: .medium)).monospacedDigit()
                }
                .padding(.horizontal, 8 * k).frame(height: bar - 6)
                .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 6 * k, style: .continuous))
                Text("Wed 25 Nov  9:41").font(.system(size: 13 * k, weight: .medium))
            }
            .foregroundColor(.white).padding(.trailing, inset)
            .frame(width: size.width, height: bar).background(Color.black.opacity(0.32))
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(.black).frame(width: WebsiteDemoProfile.notchSize.width, height: bar)
            menu.frame(width: menuWidth)
                .frame(width: size.width - inset * 2, alignment: .trailing).padding(.top, bar + 4)
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(hero.enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 12) {
                        icon(entry.0, 54).frame(height: 54)
                        Text(entry.1).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white.opacity(0.72))
                    }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 24)
            .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
            .position(x: (inset + size.width - inset - menuWidth) / 2, y: bar + (visible - bar) / 2)
        }
        .frame(width: size.width, height: size.height).clipped()
    }

    /// The icon in the bar's white, or its own colour when it warns.
    @ViewBuilder private func icon(_ gauge: StatusGauge, _ size: CGFloat) -> some View {
        let image = StatusIconImage.image(for: gauge, size: size)
        if image.isTemplate { Image(nsImage: image).renderingMode(.template).foregroundColor(.white) } else { Image(nsImage: image) }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                if row.separator {
                    Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1).padding(.horizontal, 12 * k).padding(.vertical, 3 * k)
                } else {
                    HStack(spacing: 6 * k) {
                        Image(systemName: "checkmark").font(.system(size: 10 * k, weight: .bold)).opacity(row.ticked ? 1 : 0).frame(width: 12 * k)
                        if let image = row.image {
                            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 17 * k, height: 14 * k).opacity(row.enabled ? 1 : 0.55)
                        }
                        Text(row.name).font(.system(size: (row.header ? 11 : 13) * k, weight: row.header ? .semibold : .regular))
                            .foregroundColor(.white.opacity(row.header ? 0.5 : 1))
                        if !row.value.isEmpty {
                            Text(row.value).font(.system(size: 13 * k)).monospacedDigit().foregroundColor(.white.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                    }
                    .lineLimit(1).frame(height: 21 * k).padding(.horizontal, 8 * k)
                }
            }
        }
        .foregroundColor(.white).padding(.vertical, 4 * k)
        .background(Color(red: 0.13, green: 0.13, blue: 0.16).opacity(0.94), in: RoundedRectangle(cornerRadius: 12 * k, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).strokeBorder(Color.white.opacity(0.16)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
#endif
