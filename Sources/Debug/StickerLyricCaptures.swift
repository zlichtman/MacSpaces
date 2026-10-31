#if DEBUG
import SwiftUI
import AppKit

/// Scenes (the Stickers style) on the Music page, for review before it ships: for each
/// subject a 30 fps PNG sequence of one line's whole life (a plain lead-in,
/// the subject's line arriving at 0.5 s, its entrance, action and hold over the line's
/// sung span (extended to fit natural WebP playback), then the next plain line
/// arriving so its exit plays) and a still frame as Reduce Motion shows it. Synthetic track and lines; each line gets a sung length
/// (`StickerCapture.spans`) and the scene clock is pinned to the frame, so every run
/// matches. Frames: `stickers/<subject>/f00000.png` at 2x the page (1144 × 544).
/// `MACSPACES_STICKERS_THEME` picks the theme (default MacSpaces).
/// `MACSPACES_STICKERS_SUBJECTS=drive,rose` limits sequences for a quick review;
/// the settled contact sheet always includes every subject.
@MainActor
enum StickerLyricCaptures {
    static let fps = 30.0
    static let page = NSSize(width: 572, height: 272)
    static let scale: CGFloat = 2
    /// When the subject's line arrives, and how long the capture runs past its exit.
    static let arrival = 0.5
    static let tail = 0.6

    /// Folder, subject, line and its pace (words a second): fast and slow songs.
    static let samples: [(String, LyricSubject, String, Double)] = [
        ("money", .money, "Cash in my pocket and we're spending it all", 4.2),
        ("money-slow", .money, "All the money I saved is on the shelf", 1.5),
        ("heartbreak", .heartbreak, "Slowly you broke my heart in two", 1.4),
        ("cards", .cards, "Lay your cards down on the table", 2.4),
        ("crowd", .crowd, "The whole crowd is singing our name tonight", 3.6),
        ("rose", .rose, "Roses on the windowsill in May", 1.6),
        ("drive", .drive, "Headlights on the highway, heading west", 2.2),
        ("dance", .dance, "Dancing till the last of us goes home", 3.5),
        ("heart", .heart, "My heartbeat keeps on calling out to you", 2.4),
        ("fire", .fire, "The fire keeps burning into the morning", 3.1),
        ("rain", .rain, "Raindrops falling softly on the pavement", 1.8),
        ("sun", .sun, "Sunshine spilling through the open curtains", 2.2),
        ("moon", .moon, "Moonlight follows every step you take", 1.7),
        ("stars", .stars, "Starlight scattered all along the way", 2.3),
        ("phone", .phone, "Your phone is ringing on the table", 3.2),
        ("ocean", .ocean, "The ocean carries everything away", 1.6),
        ("city", .city, "City lights are coming on below", 2.7),
        ("crown", .crown, "Wear your crown and keep your head up", 3.4),
        ("diamond", .diamond, "Diamonds catching every little ray", 2.4),
        ("drink", .drink, "Raise your wine and say it once again", 2.0),
        ("smoke", .smoke, "Smoke hit my brain, I can feel it in my eyelids(yo-yo-yo-yo-yo", 3.8),
        ("cup", .cup, "Sipping on that lean, a rebellious child(rebellious child)", 3.2),
        ("sneakers", .sneakers, "Fresh kicks on my feet, laces tied", 2.5),
        ("guitar", .guitar, "Your guitar is leaning by the bed", 1.8),
        ("microphone", .microphone, "Take the mic and tell them how it feels", 3.0),
        ("time", .time, "The clock keeps ticking on the wall", 2.8),
        ("plane", .plane, "Airplane taking off into the blue", 2.5),
        ("home", .home, "Coming home to find you waiting there", 1.8),
        ("tears", .tears, "Teardrops running slowly down your cheek", 1.6),
        ("music", .music, "The vinyl plays our favourite melody", 2.2),
        ("snow", .snow, "Snowflakes settle softly on the ground", 1.7),
        ("eyes", .eyes, "Your eyes have said it all before", 2.4),
    ]
    static let leadIn = "Say it again, say it slower"
    static let after = "And we keep going like before"

    static func capture(to directory: URL) {
        // Every subject has a bundled Fluent image, and each sample line shows it. The
        // catalog loads first so every frame matches the same way; nothing downloads.
        for subject in LyricSubject.allCases {
            precondition(StickerStore.bundledURL(StickerMatch.subjectEmoji[subject]!) != nil, "Missing Fluent scene: \(subject)")
        }
        precondition(StickerStore.shared.index != nil, "The sticker catalog is bundled")
        for (_, subject, line, _) in samples {
            precondition(LyricSubject.match(line) == subject && StickerChoice.emoji(for: line) == StickerMatch.subjectEmoji[subject],
                         "\(line) → \(subject)")
        }
        precondition(StickerChoice.emoji(for: leadIn) == nil && StickerChoice.emoji(for: after) == nil, "The plain lines draw nothing")

        let root = directory.appendingPathComponent("stickers", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let player = NowPlayingController()
        let lyrics = TeleprompterService(nowPlaying: player)
        var track = NowPlayingInfo()
        track.title = "Neon Weather"; track.artist = "Sample Artist"; track.album = "Night Drive"
        track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
        track.duration = 214; track.elapsed = 63; track.isPlaying = true
        // Original, synthetic cover art.
        track.artwork = NSImage(size: NSSize(width: 360, height: 360), flipped: false) { rect in
            NSGradient(colors: [.init(srgbRed: 0.1, green: 0.1, blue: 0.2, alpha: 1),
                                .init(srgbRed: 0.55, green: 0.25, blue: 0.4, alpha: 1)])?.draw(in: rect, angle: 60)
            NSColor(srgbRed: 1, green: 0.75, blue: 0.45, alpha: 0.85).setFill()
            NSBezierPath(rect: NSRect(x: 60, y: 150, width: 240, height: 6)).fill()
            NSBezierPath(ovalIn: NSRect(x: 130, y: 160, width: 100, height: 100)).fill()
            return true
        }
        player.setPreviewInfo(track)

        let store = ThemeStore.shared
        let capture = StickerCapture.shared
        let saved = (store.family, store.lyricStyle, store.reduceMotionPreference)
        let family = ProcessInfo.processInfo.environment["MACSPACES_STICKERS_THEME"].flatMap(ThemeFamily.init(rawValue:)) ?? .macspaces
        store.selectFamily(family); store.lyricStyle = .stickers
        defer {
            capture.pinnedTime = nil; capture.spans = [:]; capture.images = [:]
            store.selectFamily(saved.0)
            store.lyricStyle = saved.1; store.reduceMotionPreference = saved.2
        }

        contactSheet(to: root.appendingPathComponent("contact-sheet.png"))
        let requested = ProcessInfo.processInfo.environment["MACSPACES_STICKERS_SUBJECTS"]
            .map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
        let selected = samples.filter { folder, subject, _, _ in
            requested == nil || requested!.contains(folder) || requested!.contains(subject.rawValue)
        }
        var total = 0
        for (folder, subject, line, pace) in selected {
            let emoji = StickerMatch.subjectEmoji[subject]!
            let images = prepareImages(emoji)
            capture.images = [emoji: images]
            // Give every animated showcase enough time for the complete natural
            // playback plus a held pose before the next line triggers its exit.
            let sung = max(Double(MoodTreatment.wordCount(line)) / pace,
                           images.animated ? 0.4 + images.duration + 0.7 : 0)
            let timing = LyricChoreography.timing(span: 0...sung, words: MoodTreatment.wordCount(line))
            capture.spans = [leadIn: 2, line: sung, after: 3]
            // The still frame, as Reduce Motion (and an unhovered Settings preview) shows it.
            store.reduceMotionPreference = true
            capture.pinnedTime = nil
            lyrics.setPreview(current: line, upcoming: "", source: .lyrics)
            frames(player: player, lyrics: lyrics, to: root.appendingPathComponent("still-\(folder).png"), length: 0)

            store.reduceMotionPreference = false
            capture.pinnedTime = 0
            lyrics.setPreview(current: leadIn, upcoming: line, source: .lyrics)
            let length = arrival + sung + timing.exit + tail
            let output = root.appendingPathComponent(folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            frames(player: player, lyrics: lyrics, to: output, length: length) { t in
                if t >= arrival, t < arrival + sung, lyrics.currentText != line {
                    lyrics.setPreview(current: line, upcoming: after, source: .lyrics)
                } else if t >= arrival + sung, lyrics.currentText != after {
                    lyrics.setPreview(current: after, upcoming: "", source: .lyrics)
                }
            }
            total += Int((length * fps).rounded(.up))
        }
        print("Scenes captures passed: \(LyricSubject.allCases.count) Fluent subjects decoded, \(selected.count) showcase lines, \(total) frames and their still frames.")
    }

    /// Only the debug harness waits; decoding still happens on the image worker.
    private static func prepareImages(_ emoji: String, settledOnly: Bool = false) -> StickerImages {
        guard let result = StickerImages.loadForCapture(emoji, settledOnly: settledOnly) else {
            preconditionFailure("Could not decode Fluent scene: \(emoji)")
        }
        return result
    }

    /// A single sheet compares every subject's final Fluent frame. Retain only one
    /// image per subject here, rather than all 31 decoded animation sequences.
    private static func contactSheet(to url: URL) {
        let store = ThemeStore.shared
        let subjects = LyricSubject.allCases
        let settled = subjects.map { prepareImages(StickerMatch.subjectEmoji[$0]!, settledOnly: true).frame(at: .infinity) }
        let columns = 5
        let rows = (subjects.count + columns - 1) / columns
        let sheetSize = NSSize(width: 600, height: CGFloat(rows) * 112 + 24)
        let content = VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        VStack(spacing: 5) {
                            if index < subjects.count {
                                Image(decorative: settled[index], scale: 1)
                                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                Text(subjects[index].rawValue.capitalized)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(store.nookForeground.opacity(0.65))
                            }
                        }
                        .frame(width: 116, height: 112)
                    }
                }
            }
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
        .background(store.notch.surface)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: sheetSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        if let png = snapshot(host)?.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }

    /// Renders the Music page offscreen: one PNG at `url` when `length` is 0, otherwise
    /// a numbered sequence into the folder `url`, calling `beat` before each frame.
    private static func frames(player: NowPlayingController, lyrics: TeleprompterService, to url: URL, length: Double,
                               beat: (Double) -> Void = { _ in }) {
        let store = ThemeStore.shared
        let host = NSHostingView(rootView: MediaPlayerView(nowPlaying: player, largeArtwork: true, lyricsService: lyrics)
            .frame(width: page.width, height: page.height)
            .background(store.notch.surface)
            .foregroundStyle(store.nookForeground)
            .environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: page)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        defer { window.contentView = nil }
        // Let the page and the first line settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))

        guard length > 0 else {
            if let png = snapshot(host)?.representation(using: .png, properties: [:]) { try? png.write(to: url) }
            return
        }
        let writer = DispatchQueue(label: "sticker-frame-writer")
        let group = DispatchGroup()
        let pending = DispatchSemaphore(value: 3)
        let start = Date()
        for n in 0..<Int((length * fps).rounded(.up)) {
            let t = Double(n) / fps
            StickerCapture.shared.pinnedTime = t
            beat(t)
            // Real time between frames, so SwiftUI's own transitions (the poster's entrance) move as in the app.
            RunLoop.main.run(until: start.addingTimeInterval(t))
            pending.wait()
            guard let bitmap = snapshot(host) else { pending.signal(); continue }
            let frame = url.appendingPathComponent(String(format: "f%05d.png", n))
            group.enter()
            writer.async {
                defer { pending.signal(); group.leave() }
                autoreleasepool { try? bitmap.representation(using: .png, properties: [:])?.write(to: frame) }
            }
        }
        group.wait()
    }

    /// The view drawn at `scale`, whatever the screen's own scale.
    private static func snapshot(_ host: NSView) -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                                            pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}
#endif
