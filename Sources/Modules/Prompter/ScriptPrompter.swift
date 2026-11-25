import AppKit
import AVFoundation
import Combine
import PDFKit
import Speech

/// Studio's scripts, and the teleprompter that reads them from just under the camera.
/// Scripts are kept on this Mac (Application Support/MacSpaces/scripts.json).
/// The prompter scrolls at a set speed, or follows your voice using on-device
/// speech recognition (microphone and speech access are asked for only when
/// you choose that), and is hidden from screen sharing and recordings. A script's marks
/// (`PrompterScript`: # sections, [stage notes], > points) shape what it shows and hears.
@MainActor
final class ScriptPrompter: ObservableObject {
    static let shared = ScriptPrompter()

    /// Saved scripts (`SavedScript`, in Core so its checks can read old libraries).
    typealias Script = SavedScript

    enum Mode: String, CaseIterable, Identifiable {
        case scroll, voice
        var id: String { rawValue }
        var title: String { self == .scroll ? "Scroll" : "Follow my voice" }
        var shortTitle: String { self == .scroll ? "Scroll" : "Voice" }
    }

    /// The prompter's letters: SF Rounded (as before), New York or SF Mono.
    enum Typeface: String, CaseIterable, Identifiable {
        case rounded, serif, mono
        var id: String { rawValue }
        var title: String { switch self { case .rounded: return "Rounded"; case .serif: return "Serif"; case .mono: return "Mono" } }
        var design: NSFontDescriptor.SystemDesign { switch self { case .rounded: return .rounded; case .serif: return .serif; case .mono: return .monospaced } }
    }

    enum TextSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var points: CGFloat { switch self { case .small: return 20; case .medium: return 26; case .large: return 34 } }
        var title: String { rawValue.capitalized }
    }

    @Published var scripts: [Script] = [] { didSet { save() } }
    @Published var selectedID: UUID?
    @Published var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: "prompter.mode") } }
    /// Words per minute while scrolling: the last speed used, and the speed of any script that
    /// has none of its own (`SavedScript.speed`).
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "prompter.speed") } }
    @Published var textSize: TextSize { didSet { defaults.set(textSize.rawValue, forKey: "prompter.size"); wrapLines() } }
    @Published var countdown: Bool { didSet { defaults.set(countdown, forKey: "prompter.countdown") } }
    @Published var typeface: Typeface { didSet { defaults.set(typeface.rawValue, forKey: "prompter.font"); wrapLines() } }
    @Published var allCaps: Bool { didSet { defaults.set(allCaps, forKey: "prompter.caps"); wrapLines() } }
    /// The panel's background, 0.5 to 1 (solid, as before).
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "prompter.opacity") } }

    // Playback
    @Published private(set) var isShowing = false
    @Published private(set) var isRunning = false
    /// Position in the script, in words (fractional while scrolling).
    @Published private(set) var position: Double = 0
    @Published private(set) var countdownValue: Int?
    @Published private(set) var listening = false
    @Published private(set) var voiceProblem: String?
    /// Voice mode was refused (no on-device recognition), so this run scrolls.
    @Published private(set) var scrollingInstead = false
    /// Set when scripts.json exists but couldn't be read: it is left untouched and
    /// nothing is saved over it until `startNewLibrary()`.
    @Published private(set) var libraryProblem: String?
    /// The script being prompted, its marks read.
    @Published private(set) var script = PrompterScript("")
    /// Its words wrapped to the panel, measured only when they, the size or the letters change.
    @Published private(set) var lines: [PrompterLayout.Line] = []
    /// Each line as runs drawn one way, made with the lines.
    @Published private(set) var lineRuns: [[PrompterLayout.Segment]] = []
    /// The speed this run scrolls at: the script's own, else `speed`.
    @Published private(set) var runSpeed: Double = 140
    /// The script's points ticked off this take: heard in voice mode, or clicked.
    @Published private(set) var covered: Set<Int> = []
    /// How long the script should take, from its saved target; nil is none.
    @Published private(set) var target: TimeInterval?
    /// The last take's summary, for the script it was of, until dismissed or the next take.
    @Published private(set) var summary: (script: UUID, take: PrompterTakeSummary)?

    /// The script on the prompter.
    private var promptedID: UUID?
    /// Reading time before the last pause, and when this stretch began (nil while paused).
    private var ranBefore: TimeInterval = 0
    private var runStarted: Date?
    /// Every word heard this take, and when words were heard (in reading time).
    private var heardEver: Set<String> = []
    private var heardTimes: [TimeInterval] = []
    private var lastHeardCount = 0
    /// Spoken words already behind the place this take began, and whether it jumped about
    /// (a section, back to the top): then words passed no longer says how fast it was read.
    private var spokenAtStart = 0
    private var jumped = false
    /// This run scrolls unless voice following is already allowed (Prompt in MacSpaces).
    private var scrollUnlessAllowed = false
    /// Speeds set but not yet written to scripts.json: saved once the changes stop.
    @Published private var unsavedSpeeds: [UUID: Double] = [:]
    private var speedSave: DispatchWorkItem?

    private let defaults: UserDefaults
    private var tick: Timer?
    private var lastTick = Date()
    private var countdownID = UUID()
    private let speech = VoiceFollower()
    private var store = ProtectedFile(url: ScriptPrompter.storeURL)

    var selected: Script? { scripts.first { $0.id == selectedID } ?? scripts.first }

    /// Where scripts.json lives, and Studio's Takes folder beside it. Debug harnesses (any other
    /// bundle identifier) use a temporary fixtures folder instead.
    static var directory: URL {
        let isolated = Bundle.main.bundleIdentifier != "dev.opensource.MacSpaces"
        return isolated ? FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpaces")
    }

    private static var storeURL: URL { directory.appendingPathComponent("scripts.json") }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = Mode(rawValue: defaults.string(forKey: "prompter.mode") ?? "") ?? .scroll
        speed = defaults.object(forKey: "prompter.speed") as? Double ?? 140
        textSize = TextSize(rawValue: defaults.string(forKey: "prompter.size") ?? "") ?? .medium
        countdown = defaults.object(forKey: "prompter.countdown") as? Bool ?? true
        typeface = Typeface(rawValue: defaults.string(forKey: "prompter.font") ?? "") ?? .rounded
        allCaps = defaults.bool(forKey: "prompter.caps")
        opacity = min(1, max(0.5, defaults.object(forKey: "prompter.opacity") as? Double ?? 1))
        switch store.load({ try JSONDecoder().decode([Script].self, from: SecureStorage.open($0)) }) {
        case .loaded(let saved): scripts = saved
        case .missing: break
        case .unreadable(let reason):
            libraryProblem = "Your saved scripts couldn't be opened (\(reason)), so they were left as they are. Changes here aren't saved until you start a new library."
        }
        if scripts.isEmpty, libraryProblem == nil {
            scripts = [Script(title: "Welcome", text: "This is Studio. Write or paste a script here. Select some words and press Read to hear them in a voice: each reading is a take you can play, star and save. Press Prompt to read it yourself, just under your camera, hidden from screen sharing and recordings. [Start a line with # for a section, put stage notes in brackets, and start a line with > for a point to cover in your own words.]")]
        }
        selectedID = scripts.first?.id
        speech.onHeard = { [weak self] heard in self?.follow(heard) }
        speech.onProblem = { [weak self] problem in self?.voiceProblem = problem; self?.listening = false }
        speech.onListening = { [weak self] value in self?.listening = value }
    }

    /// Never writes over a library that failed to load (see `libraryProblem`). A save
    /// that fails says so on the page rather than losing the changes quietly.
    private func save() {
        guard store.isWritable else { return }
        do {
            try store.write(SecureStorage.seal(JSONEncoder().encode(scripts)))
            libraryProblem = nil
        } catch {
            libraryProblem = "Scripts can't be saved: \(error.localizedDescription)"
        }
    }

    /// The owner's explicit reset after a failed load: the unreadable file is kept
    /// beside the original (renamed, never deleted) and the scripts here are saved.
    func startNewLibrary() {
        do {
            try store.setAside()
            libraryProblem = nil
            save()
        } catch {
            libraryProblem = "The unreadable scripts file couldn't be set aside: \(error.localizedDescription)"
        }
    }

#if DEBUG
    /// QA captures: the selected script laid out as if read up to `word`, running or paused (its
    /// controls showing).
    func previewPlayback(at word: Double, running: Bool = true, covered: Set<Int> = [], elapsed: TimeInterval = 0) {
        script = PrompterScript(selected?.text ?? "")
        wrapLines()
        position = word
        isRunning = running
        self.covered = covered
        target = selected?.target
        runSpeed = selected?.speed ?? speed
        ranBefore = elapsed
        runStarted = nil
    }

    func previewSummary(_ take: PrompterTakeSummary?, for script: UUID) { summary = take.map { (script, $0) } }
#endif

    // MARK: Library

    func newScript() {
        let script = Script(title: "Untitled script", text: "")
        scripts.insert(script, at: 0)
        selectedID = script.id
    }

    /// Its takes go with it.
    func delete(_ script: Script) {
        scripts.removeAll { $0.id == script.id }
        StudioModel.shared.removeTakes(of: script.id)
        if selectedID == script.id { selectedID = scripts.first?.id }
    }

    /// Changed words lose the saved place: it pointed into the old text.
    func update(_ script: Script) {
        guard let index = scripts.firstIndex(where: { $0.id == script.id }) else { return }
        var edited = script
        edited.edited = Date()
        if edited.text != scripts[index].text { edited.lastPosition = nil }
        scripts[index] = edited
    }

    /// A script's speed, place or target: saved without counting as an edit.
    private func remember(for id: UUID?, _ change: (inout Script) -> Void) {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        var script = scripts[index]
        change(&script)
        if script != scripts[index] { scripts[index] = script }
    }

    /// The selected script's scroll speed: its own, else the last one used.
    var selectedSpeed: Double { selected.flatMap { unsavedSpeeds[$0.id] ?? $0.speed } ?? speed }

    /// Sets the selected script's speed, which is also the speed new scripts start with.
    func setSelectedSpeed(_ value: Double) {
        let clamped = min(260, max(60, value))
        speed = clamped
        if let id = selected?.id { keep(speed: clamped, for: id) }
        if promptedID == selected?.id { runSpeed = clamped }
    }

    /// A slider drag or held arrow key changes the speed many times: scripts.json is written
    /// once, a moment after the last change (and when the prompter starts or closes).
    private func keep(speed value: Double, for id: UUID) {
        unsavedSpeeds[id] = value
        speedSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveSpeeds() }
        speedSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func saveSpeeds() {
        speedSave?.cancel()
        speedSave = nil
        guard !unsavedSpeeds.isEmpty else { return }
        var all = scripts
        for index in all.indices { if let value = unsavedSpeeds[all[index].id] { all[index].speed = value } }
        unsavedSpeeds = [:]
        if all != scripts { scripts = all }
    }

    /// The selected script's target length in seconds, in 30 s steps up to an hour; nil is none.
    func setSelectedTarget(_ seconds: TimeInterval?) {
        let value = seconds.flatMap { $0 < 30 ? nil : min(3600, ($0 / 30).rounded() * 30) }
        remember(for: selected?.id) { $0.target = value }
        if promptedID == selected?.id { target = value }
    }

    func dismissSummary() { summary = nil }

    /// Plain text, Markdown, RTF, Word and PDF files become scripts. They're read off the main
    /// thread (a long PDF takes a moment) and added in the order chosen.
    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, .rtf, .rtfd, .pdf, .init(filenameExtension: "md")!,
                                     .init(filenameExtension: "docx")!, .init(filenameExtension: "doc")!].compactMap { $0 }
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task.detached(priority: .userInitiated) {
            let read = urls.compactMap { url -> Script? in
                guard let text = Self.text(of: url) else { return nil }
                return Script(title: url.deletingPathExtension().lastPathComponent, text: text)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                for script in read {
                    self.scripts.insert(script, at: 0)
                    self.selectedID = script.id
                }
            }
        }
    }

    /// A file's words: a PDF's text layer joined into paragraphs (a scanned PDF has none, so
    /// nothing is added), else whatever AppKit reads as a document, else plain text.
    nonisolated private static func text(of url: URL) -> String? {
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            text = ScriptImport.paragraphs(fromPrinted: PDFDocument(url: url)?.string ?? "")
        } else {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil).string)
                ?? (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// Words selected in another app (the Services menu's Prompt in MacSpaces): they replace the
    /// words of the script this made before (remembered by its id, so a script you named
    /// Selected Text yourself is never touched), or make it, and the prompter starts on them. It
    /// never asks for anything: it follows your voice only if that's already allowed.
    func prompt(selection text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        if isShowing { close() }
        let known = defaults.string(forKey: Self.selectionScriptKey).flatMap(UUID.init)
        if let index = scripts.firstIndex(where: { $0.id == known }) {
            var script = scripts[index]
            script.text = words
            script.lastPosition = nil
            script.edited = Date()
            scripts[index] = script
            selectedID = script.id
        } else {
            let script = Script(title: "Selected Text", text: words)
            scripts.insert(script, at: 0)
            selectedID = script.id
            defaults.set(script.id.uuidString, forKey: Self.selectionScriptKey)
        }
        start(scrollUnlessAllowed: true)
    }

    private static let selectionScriptKey = "prompter.selectionScript"

    // MARK: Playback

    /// From the top, or with `resume` from where this script's last take stopped.
    /// `scrollUnlessAllowed` never asks for the microphone: it follows the voice only when that
    /// is already allowed.
    func start(resume: Bool = false, scrollUnlessAllowed: Bool = false) {
        saveSpeeds()
        self.scrollUnlessAllowed = scrollUnlessAllowed
        guard let saved = selected else { return }
        let parsed = PrompterScript(saved.text)
        guard !parsed.words.isEmpty else { return }
        script = parsed
        wrapLines()
        promptedID = saved.id
        runSpeed = saved.speed ?? speed
        target = saved.target
        summary = nil
        resetTake()
        // Resuming starts at the top of the line it stopped on.
        let place = resume ? min(saved.lastPosition ?? 0, Double(parsed.words.count - 1)) : 0
        position = Double(lines.last { Double($0.first) <= place }?.first ?? 0)
        spokenAtStart = script.spokenPassed(by: position)
        voiceProblem = nil
        scrollingInstead = false
        isShowing = true
        PrompterPanel.shared.show()
        countdownID = UUID()
        if countdown {
            runCountdown(3, id: countdownID)
        } else {
            begin()
        }
    }

    /// Measured with the letters drawn: the size, typeface, caps, notes in italics and headings
    /// smaller in capitals.
    private func wrapLines() {
        let size = textSize.points
        let fonts = (spoken: Self.font(typeface, size: size), note: Self.font(typeface, size: size, italic: true),
                     heading: Self.font(typeface, size: size * Self.headingScale, weight: .bold))
        let space = (" " as NSString).size(withAttributes: [.font: fonts.spoken]).width
        let words = script.words
        let wrapped = PrompterLayout.wrap(words, width: Double(PrompterPanel.size.width - 48), space: Double(space)) { index in
            let word = words[index]
            let font = word.kind == .heading ? fonts.heading : word.kind == .note ? fonts.note : fonts.spoken
            return Double((shown(word) as NSString).size(withAttributes: [.font: font]).width)
        }
        lineRuns = PrompterLayout.segments(wrapped, words: words, shown: shown)
        lines = wrapped
    }

    /// A word as drawn: headings always in capitals, the rest when All Caps is on.
    func shown(_ word: PrompterScript.Word) -> String {
        word.kind == .heading || allCaps ? word.text.uppercased() : word.text
    }

    static let headingScale: CGFloat = 0.62

    static func font(_ typeface: Typeface, size: CGFloat, weight: NSFont.Weight = .semibold, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = base.fontDescriptor.withDesign(typeface.design) ?? base.fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: The take

    private func resetTake() {
        spokenAtStart = 0
        jumped = false
        ranBefore = 0
        runStarted = nil
        covered = []
        heardEver = []
        heardTimes = []
        lastHeardCount = 0
    }

    /// Reading time so far: the countdown and pauses don't count.
    func elapsed(at date: Date = Date()) -> TimeInterval {
        ranBefore + (runStarted.map { date.timeIntervalSince($0) } ?? 0)
    }

    /// Ticks a point off, or back on: for scrolling, where nothing is heard.
    func togglePoint(_ index: Int) {
        guard script.points.indices.contains(index) else { return }
        if covered.contains(index) { covered.remove(index) } else { covered.insert(index) }
    }

    /// Words heard: remembered for the points and the longest pause.
    private func note(heard: [String]) {
        if heard.count != lastHeardCount {
            lastHeardCount = heard.count
            let now = elapsed()
            if now - (heardTimes.last ?? -1) >= 0.25 { heardTimes.append(now) }
        }
        let before = heardEver.count
        heardEver.formUnion(heard)
        guard heardEver.count != before else { return }
        for (index, point) in script.points.enumerated() where !covered.contains(index) && PrompterScript.covered(point, heard: heardEver) {
            covered.insert(index)
        }
    }

    // MARK: Sections

    func jump(toSection index: Int) {
        guard isShowing, script.sections.indices.contains(index) else { return }
        jumped = true
        position = Double(script.sections[index].firstWord)
        speech.resetHeard()
    }

    /// Tab: the next section's heading.
    func nextSection() {
        if let index = script.nextSection(after: position) { jump(toSection: index) }
    }

    /// Shift-Tab: back to the start of this section, or the one before.
    func previousSection() {
        if let index = script.previousSection(before: position) { jump(toSection: index) } else { skip(-position) }
    }

    /// `id` ends a count left over from an earlier Start.
    private func runCountdown(_ value: Int, id: UUID) {
        guard isShowing, id == countdownID else { return }
        guard value > 0 else { countdownValue = nil; begin(); return }
        countdownValue = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.runCountdown(value - 1, id: id) }
    }

    private func begin() {
        isRunning = true
        runStarted = Date()
        guard mode == .voice, !scrollingInstead else { startTicking(); return }
        if scrollUnlessAllowed, SFSpeechRecognizer.authorizationStatus() != .authorized
            || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            voiceProblem = "Scrolling: voice following hasn't been allowed yet. Press Prompt in Studio to allow it."
            scrollingInstead = true
            startTicking()
            return
        }
        WispModel.shared.voice.stopListening(deliver: false)
        // Audio stays on this Mac: without on-device recognition, scroll instead.
        if case .refuse(let reason) = speech.decision {
            voiceProblem = reason
            scrollingInstead = true
            startTicking()
            return
        }
        speech.start()
    }

    func togglePause() {
        guard isShowing, countdownValue == nil else { return }
        if isRunning {
            stopClock()
            isRunning = false
            tick?.invalidate(); tick = nil
            speech.stop()
        } else {
            // Play at the end starts again from the top, as a new take; otherwise the first tick pauses again.
            if position >= Double(script.words.count) {
                position = 0
                resetTake()
                speech.resetHeard()
            }
            begin()
        }
    }

    private func stopClock() {
        if let runStarted { ranBefore += Date().timeIntervalSince(runStarted) }
        runStarted = nil
    }

    /// Back to the first word (Home).
    func restart() {
        guard isShowing else { return }
        jumped = true
        position = 0
        speech.resetHeard()
    }

    func close() {
        stopClock()
        if isShowing, let promptedID {
            // A take long enough to say anything about gets a summary on the Studio page.
            let duration = ranBefore
            if duration >= 5 {
                let followed = mode == .voice && !scrollingInstead
                // Points can only be judged when they could be ticked: heard, or clicked.
                let judged = followed || !covered.isEmpty
                let take = PrompterTakeSummary(
                    duration: duration,
                    // Words passed since the take began; nothing after jumping about.
                    spokenWords: jumped ? 0 : max(0, script.spokenPassed(by: position) - spokenAtStart),
                    longestPause: followed ? PrompterTakeSummary.longestPause(heardTimes, start: 0) : nil,
                    points: judged ? script.points.count : 0,
                    missed: judged ? script.points.enumerated().filter { !covered.contains($0.offset) }.map(\.element.text) : [],
                    target: target)
                summary = (promptedID, take)
            }
            saveSpeeds()
            // The place to carry on from: none at the very start or once it's finished.
            let place: Double? = position >= 1 && position < Double(script.words.count) ? position.rounded(.down) : nil
            remember(for: promptedID) { $0.lastPosition = place }
        }
        promptedID = nil
        isRunning = false
        isShowing = false
        countdownValue = nil
        countdownID = UUID()
        tick?.invalidate(); tick = nil
        speech.stop()
        PrompterPanel.shared.hide()
    }

    /// Back (or forward) by about one line.
    func skip(_ wordsToMove: Double) {
        position = min(max(0, position + wordsToMove), Double(script.words.count))
        speech.resetHeard()
    }

    /// The running script's speed, saved as its own and as the last one used.
    func changeSpeed(by delta: Double) {
        let value = min(260, max(60, runSpeed + delta))
        runSpeed = value
        speed = value
        if let promptedID { keep(speed: value, for: promptedID) }
    }

    private func startTicking() {
        tick?.invalidate()
        lastTick = Date()
        tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                let now = Date()
                let words = self.script.words
                // Headings and stage notes aren't read, so they pass quickly.
                let here = Int(self.position)
                let quick = words.indices.contains(here) && words[here].kind != .spoken ? PrompterScript.quickPass : 1
                self.position = min(Double(words.count), self.position + now.timeIntervalSince(self.lastTick) * self.runSpeed / 60 * quick)
                self.lastTick = now
                if self.position >= Double(words.count) { self.togglePause() }
            }
        }
    }

    private func follow(_ heard: [String]) {
        guard isRunning, mode == .voice else { return }
        note(heard: heard)
        // Compared with the spoken words only, so headings and stage notes are skipped.
        guard let next = ScriptAligner.position(script: script.spoken, heard: heard, from: script.spoken(atOrAfter: Int(position))) else { return }
        // Resting just after the last word heard, so a note or heading that's next is still shown.
        position = Double(script.word(afterSpoken: next))
    }
}

/// On-device speech recognition feeding the words heard so far. Restarts the
/// recognition task when macOS ends it (about once a minute).
@MainActor
final class VoiceFollower {
    var onHeard: ([String]) -> Void = { _ in }
    var onProblem: (String) -> Void = { _ in }
    var onListening: (Bool) -> Void = { _ in }
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var active = false
    private var hasTap = false
    /// Only the newest recognition task's callbacks count.
    private var generation = UUID()
    /// Tasks in a row that failed just after starting.
    private var quickFailures = 0

    /// Whether voice following may run here: only with on-device recognition.
    var decision: OnDeviceSpeech.Decision {
        OnDeviceSpeech.decide(hasRecognizer: recognizer != nil, isAvailable: recognizer?.isAvailable ?? false,
                              supportsOnDevice: recognizer?.supportsOnDeviceRecognition ?? false)
    }

    func start() {
        guard !active else { return }
        guard !DictationModel.shared.listening, !DictationModel.shared.starting else {
            onProblem("Stop dictation before starting voice following.")
            return
        }
        guard decision == .listen else {
            if case .refuse(let reason) = decision { onProblem(reason) }
            return
        }
        active = true
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard self.active else { return }
                guard status == .authorized else {
                    self.active = false
                    self.onProblem("Allow Speech Recognition for MacSpaces in System Settings → Privacy & Security.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard self.active else { return }
                        guard granted else {
                            self.active = false
                            self.onProblem("Allow the Microphone for MacSpaces in System Settings → Privacy & Security.")
                            return
                        }
                        self.listen()
                    }
                }
            }
        }
    }

    func stop() {
        active = false
        generation = UUID()
        quickFailures = 0
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        removeTap()
        if engine.isRunning { engine.stop() }
        onListening(false)
    }

    /// The engine stops itself on a device change and leaves its tap on, so this doesn't
    /// depend on it running; a second tap on the bus would crash.
    private func removeTap() {
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
    }

    func resetHeard() {
        guard active else { return }
        quickFailures = 0
        task?.finish()
    }

    private func listen() {
        guard active, let recognizer, decision == .listen else {
            if active, case .refuse(let reason) = decision { stop(); onProblem(reason) }
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stop()
            onProblem("No usable microphone was found.")
            return
        }
        let token = UUID()
        generation = token
        task?.cancel()
        self.request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Never a server request: on-device only (checked above), always required.
        request.requiresOnDeviceRecognition = true
        self.request = request
        // Each tap feeds only its own request, so the audio thread never reads `self.request`.
        removeTap()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        hasTap = true
        if !engine.isRunning {
            do { try engine.start() } catch {
                stop()
                onProblem("The microphone couldn't start: \(error.localizedDescription)")
                return
            }
        }
        onListening(true)
        let started = Date()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result.map { ScriptAligner.words($0.bestTranscription.formattedString) } ?? []
            let finished = (result?.isFinal ?? false) || error != nil
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == token else { return }
                if !words.isEmpty { self.onHeard(words) }
                if finished {
                    // Recognition tasks end on their own; carry on with a fresh one. One that
                    // keeps failing as soon as it starts won't recover, so stop and say why.
                    if let failure, Date().timeIntervalSince(started) < 2 {
                        self.quickFailures += 1
                        if self.quickFailures >= 3 {
                            self.stop()
                            self.onProblem(failure)
                            return
                        }
                    } else {
                        self.quickFailures = 0
                    }
                    self.task = nil
                    self.listen()
                }
            }
        }
    }
}
