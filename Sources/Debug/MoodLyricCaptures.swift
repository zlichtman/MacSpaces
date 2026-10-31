#if DEBUG
import SwiftUI
import AppKit

/// Mood on the Music page, for review before it ships: in MacSpaces (a white accent,
/// so the cover carries the colour) and a coloured theme, each with its own synthetic
/// cover, every treatment as a 4 s, 30 fps PNG sequence (a lead-in line, then the
/// treatment's line arriving at 0.5 s, so the crossfade, the line's hit and each
/// word's accent show) and a still frame as Reduce Motion draws it. Each line is held
/// to its treatment and pace (`MoodCapture`), and Mood's clock is pinned to the frame,
/// so every run matches. The theme photograph and page-level Mood light sit behind
/// the full player, matching the live shell. Frames: `mood/<theme>/<treatment>/f00000.png` and
/// `mood/<theme>/still-<treatment>.png` at 2x the page (1144 × 544), for CI to encode
/// into clips. `MACSPACES_MOOD_THEMES` (comma-separated) picks other themes.
@MainActor
enum MoodLyricCaptures {
    static let fps = 30.0
    static let length = 4.0
    static let page = NSSize(width: 572, height: 272)
    static let scale: CGFloat = 2

    /// The line for each treatment and the pace it's sung at (words a second).
    static let samples: [(MoodTreatment, String, Double)] = [
        (.drift, "Slow light moving on the water", 1.4),
        (.pulse, "We run the streets until the city lights come up", 4.2),
        (.bloom, "You make the morning feel like summer", 2.2),
        (.rain, "I keep your letters where the light can't reach", 2),
        (.sweep, "Hold on", 2),
        (.aurora, "Over the hills the northern sky is turning", 2.4),
        (.embers, "Burn it bright, we're dancing in the fire tonight", 4),
        (.haze, "Fog on the river where you used to wait", 1.2),
    ]
    static let leadIn = "Till the harbour lamps come on"

    static func capture(to directory: URL) {
        validateScenes()
        let root = directory.appendingPathComponent("mood", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let player = NowPlayingController()
        let lyrics = TeleprompterService(nowPlaying: player)
        let store = ThemeStore.shared
        let capture = MoodCapture.shared
        let saved = (store.family, store.lyricStyle, store.reduceMotionPreference)
        defer {
            capture.pinnedTime = nil; capture.holds = [:]
            store.selectFamily(saved.0)
            store.lyricStyle = saved.1; store.reduceMotionPreference = saved.2
        }
        let families = (ProcessInfo.processInfo.environment["MACSPACES_MOOD_THEMES"] ?? "macspaces,blossom")
            .split(separator: ",").compactMap { ThemeFamily(rawValue: String($0)) }

        for (index, family) in families.enumerated() {
            store.selectFamily(family); store.lyricStyle = .mood
            var track = NowPlayingInfo()
            track.title = "Harbour Lights"; track.artist = "Sample Artist"; track.album = "Low Tide"
            track.sourceName = "Music"; track.capabilities = [.playPause, .previous, .next, .seek]
            track.duration = 236; track.elapsed = 81; track.isPlaying = true
            track.artwork = cover(index % 2 == 0 ? .sunset : .night)
            player.setPreviewInfo(track)
            // The cover's palette is made off the main thread.
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            let themeRoot = root.appendingPathComponent(family.rawValue, isDirectory: true)
            try? FileManager.default.createDirectory(at: themeRoot, withIntermediateDirectories: true)

            for (treatment, line, pace) in samples {
                capture.holds = [leadIn: .init(treatment: treatment == .drift ? .aurora : .drift, wordsPerSecond: 2),
                                 line: .init(treatment: treatment, wordsPerSecond: pace)]
                // The still frame, as Reduce Motion (and an unhovered Settings preview) shows it.
                store.reduceMotionPreference = true
                capture.pinnedTime = nil
                lyrics.setPreview(current: line, upcoming: "", source: .lyrics)
                frames(player: player, lyrics: lyrics, to: themeRoot.appendingPathComponent("still-\(treatment.rawValue).png"), still: true)

                store.reduceMotionPreference = false
                capture.pinnedTime = 0
                lyrics.setPreview(current: leadIn, upcoming: line, source: .lyrics)
                let folder = themeRoot.appendingPathComponent(treatment.rawValue, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                frames(player: player, lyrics: lyrics, to: folder, still: false) { t in
                    if t >= 0.5, lyrics.currentText != line { lyrics.setPreview(current: line, upcoming: "", source: .lyrics) }
                }
            }
        }
        print("Mood captures passed: \(samples.count) treatments in \(families.count) themes, \(Int(length * fps)) frames each, and their still frames.")
    }

    /// Exercise the same geometry used by both renderers, including the small
    /// Settings preview, right-aligned type and dark ink on a light surface.
    private static func validateScenes() {
        let words = MoodTreatment.words("We were running through the streets tonight")
        let configurations: [(CGSize, CGFloat, Color)] = [
            (CGSize(width: 318, height: 125), 0.27, .white),
            (CGSize(width: 318, height: 125), 0.74, .white),
            (CGSize(width: 224, height: 76), 0.27, .white),
            (CGSize(width: 318, height: 125), 0.74, .black),
        ]
        for (size, focus, ink) in configurations {
            let palette = MoodPalette(accent: ink, ink: ink, cover: nil)
            for treatment in MoodTreatment.allCases {
                let scene = MoodScene(treatment: treatment, tempo: 1, focus: focus, palette: palette, size: size)
                let beats = MoodScene.beats(treatment: treatment, words: words,
                                            delays: MoodTreatment.wordDelays(words: words, span: 1...4, songTime: 0.75),
                                            hero: PosterLyric.heroIndex(words), hit: 1, focus: focus, palette: palette, size: size)
                precondition(scene.elements.count >= 6, "\(treatment) draws three depths")
                precondition(beats.count > words.count, "\(treatment) lands the line and accents every word")
                for element in scene.elements + beats {
                    precondition(element.keyTimes.count == element.opacities.count && element.keyTimes.first == 0
                                 && element.keyTimes.last == 1 && element.keyTimes == element.keyTimes.sorted(), "\(treatment) keyframes")
                    precondition(element.opacities.allSatisfy { $0.isFinite && (0...0.9).contains($0) }, "\(treatment) stays under the type")
                    precondition(element.duration > 0 && (0..<1).contains(element.phase), "\(treatment) timing")
                    precondition(element.shape.size.width > 0 && element.shape.size.height > 0, "\(treatment) geometry")
                    if let path = element.shape.lightPath {
                        let bounds = path.boundingBoxOfPath
                        precondition(!bounds.isEmpty && !bounds.isInfinite && !bounds.isNull, "\(treatment) light path")
                    }
                    for progress in [0.0, 0.1, 0.5, 0.9, 1.0] {
                        let position = element.position(at: progress, time: scene.stillTime)
                        precondition(position.x.isFinite && position.y.isFinite && element.scale(at: progress) > 0,
                                     "\(treatment) renders a finite frame")
                    }
                }
                precondition(beats.allSatisfy { $0.once && $0.opacities.first == 0 && $0.opacities.last == 0 }
                             && !scene.elements.contains(where: \.once), "Beats finish cleanly; the scene loops")
            }
        }
    }

    private enum Cover { case sunset, night }

    /// Original, synthetic cover art that looks like a record sleeve: a sky gradient,
    /// a low sun or moon with a glow, and layered hills.
    private static func cover(_ look: Cover) -> NSImage {
        NSImage(size: NSSize(width: 360, height: 360), flipped: false) { rect in
            let sky: [NSColor], sun: NSColor, hills: [NSColor]
            switch look {
            case .sunset:
                sky = [NSColor(srgbRed: 0.98, green: 0.62, blue: 0.32, alpha: 1), NSColor(srgbRed: 0.86, green: 0.3, blue: 0.42, alpha: 1),
                       NSColor(srgbRed: 0.3, green: 0.12, blue: 0.4, alpha: 1)]
                sun = NSColor(srgbRed: 1, green: 0.88, blue: 0.6, alpha: 1)
                hills = [NSColor(srgbRed: 0.42, green: 0.13, blue: 0.32, alpha: 1), NSColor(srgbRed: 0.18, green: 0.06, blue: 0.2, alpha: 1)]
            case .night:
                sky = [NSColor(srgbRed: 0.08, green: 0.1, blue: 0.26, alpha: 1), NSColor(srgbRed: 0.1, green: 0.38, blue: 0.5, alpha: 1),
                       NSColor(srgbRed: 0.42, green: 0.78, blue: 0.74, alpha: 1)]
                sun = NSColor(srgbRed: 0.95, green: 0.9, blue: 0.7, alpha: 1)
                hills = [NSColor(srgbRed: 0.06, green: 0.24, blue: 0.3, alpha: 1), NSColor(srgbRed: 0.03, green: 0.1, blue: 0.16, alpha: 1)]
            }
            NSGradient(colors: sky.reversed())?.draw(in: rect, angle: 90)
            NSGradient(colors: [sun.withAlphaComponent(0.55), sun.withAlphaComponent(0)])?
                .draw(in: NSBezierPath(ovalIn: NSRect(x: 100, y: 110, width: 160, height: 160)), relativeCenterPosition: .zero)
            sun.setFill()
            NSBezierPath(ovalIn: NSRect(x: 145, y: 155, width: 70, height: 70)).fill()
            for (layer, color) in hills.enumerated() {
                let path = NSBezierPath()
                let base = CGFloat(120 - layer * 45)
                path.move(to: NSPoint(x: 0, y: 0))
                path.line(to: NSPoint(x: 0, y: base))
                path.curve(to: NSPoint(x: 360, y: base - 20 + CGFloat(layer) * 30),
                           controlPoint1: NSPoint(x: 110, y: base + 60), controlPoint2: NSPoint(x: 240, y: base - 50))
                path.line(to: NSPoint(x: 360, y: 0))
                path.close()
                color.setFill()
                path.fill()
            }
            return true
        }
    }

    /// Renders the Music page offscreen: one PNG at `url` when `still`, otherwise a
    /// numbered sequence into the folder `url`, calling `beat` before each frame.
    private static func frames(player: NowPlayingController, lyrics: TeleprompterService, to url: URL, still: Bool, beat: (Double) -> Void = { _ in }) {
        let store = ThemeStore.shared
        let host = NSHostingView(rootView: MediaPlayerView(nowPlaying: player, largeArtwork: true, lyricsService: lyrics)
            .frame(width: page.width, height: page.height)
            .background {
                ZStack {
                    store.notch.surface
                    LinearGradient(colors: [store.notch.surfaceSecondary, .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let motif = store.activeMotif {
                        ThemeMotifView(motif: motif, accent: store.notch.accent,
                                       ink: store.nookForeground, animated: false)
                    }
                    MusicArtworkAmbience(nowPlaying: player, lyricsService: lyrics)
                }
            }
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

        if still {
            if let png = snapshot(host)?.representation(using: .png, properties: [:]) { try? png.write(to: url) }
            return
        }
        let writer = DispatchQueue(label: "mood-frame-writer")
        let group = DispatchGroup()
        let start = Date()
        for n in 0..<Int(length * fps) {
            let t = Double(n) / fps
            MoodCapture.shared.pinnedTime = t
            beat(t)
            // Real time between frames, so SwiftUI's own transitions (the poster's entrance,
            // the crossfade) move as they do in the app.
            RunLoop.main.run(until: start.addingTimeInterval(t))
            guard let bitmap = snapshot(host) else { continue }
            let frame = url.appendingPathComponent(String(format: "f%05d.png", n))
            group.enter()
            writer.async { try? bitmap.representation(using: .png, properties: [:])?.write(to: frame); group.leave() }
        }
        group.wait()
    }

    /// The view drawn at `scale`, whatever the screen's own scale.
    private static func snapshot(_ host: NSView) -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(page.width * scale),
                                            pixelsHigh: Int(page.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }
}
#endif
