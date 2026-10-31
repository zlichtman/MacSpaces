import AppKit
import ImageIO
import NaturalLanguage
import QuartzCore
import SwiftUI
import os

// MARK: - Scenes (the Stickers style)

/// Poster with a Fluent Emoji beside the measured headline: whatever the line is
/// clearly about (`StickerChoice`), from the whole Fluent set. Each sticker enters,
/// plays Microsoft's animation once (or one small gesture for a still), then holds.
/// Live playback runs entirely in Core Animation; previews and captures use the
/// same images, frame delays and transforms at a fixed moment.
struct StickerLyric: View {
    let line: String
    let accent: Color
    let ink: Color
    let size: CGSize
    let animated: Bool
    /// The scene holds while the song is paused.
    var playing = true
    /// The line's sung span, for its pace; untimed lyrics move at a medium pace.
    var span: ClosedRange<TimeInterval>?
    /// The song's position as the view was built, so a scene that opens mid-line
    /// starts where the line is.
    var songTime: TimeInterval?
    let composition: PosterLyric.Composition
    var identity = 0
    @ObservedObject private var capture = StickerCapture.shared

    var body: some View {
        let emoji = StickerChoice.emoji(for: line)
        let side = Self.side(for: size)
        let onLeft = composition == .flushRight
        let held = capture.spans[line].map { 0...$0 }
        let parts = PosterLyric.split(line)
        let hero = min(size.height * (composition == .leadAbove ? 0.56 : 0.48), 72)
        let textWidth = max(0, size.width - side - 6)
        let alignment: HorizontalAlignment = onLeft ? .trailing : .leading
        // The stage shares the headline's row, rather than the lyric area's outer
        // edge. The row measures the actual headline, keeping short words and art
        // together. Lead and tail have their own rows, so no text can meet the art.
        VStack(alignment: alignment, spacing: 0) {
            if !parts.lead.isEmpty {
                Text(parts.lead)
                    .font(.system(size: max(13, hero * 0.27), design: .serif).italic())
                    .foregroundStyle(ink.opacity(0.92))
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .frame(maxWidth: textWidth, alignment: onLeft ? .trailing : .leading)
            }
            StickerHeadlineRow(onLeft: onLeft, side: side, gap: 6) {
                Text(parts.hero.uppercased())
                    .font(.system(size: hero, weight: .black).width(.compressed))
                    .foregroundStyle(accent)
                    .lineLimit(1).minimumScaleFactor(0.3)
                    .id(identity)
                    .transition(.opacity)
                // Keep this mounted, and keep its lane even for a plain line:
                // outgoing art must finish without crossing newly arriving text.
                StickerStage(emoji: emoji,
                             timing: LyricChoreography.timing(span: held ?? span, words: MoodTreatment.wordCount(Lyrics.asides(line).sung)),
                             age: held == nil ? age : 0, side: side, height: side, onLeft: onLeft,
                             accent: accent, ink: ink, animated: animated, playing: playing)
                    .layoutValue(key: StickerHeadlineRow.Stage.self, value: true)
            }
            if !parts.trail.isEmpty {
                Text(parts.trail)
                    .font(.system(size: max(12, hero * 0.22), weight: .semibold))
                    .foregroundStyle(ink.opacity(0.9))
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .multilineTextAlignment(onLeft ? .trailing : .leading)
                    .frame(maxWidth: textWidth, alignment: onLeft ? .trailing : .leading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: onLeft ? .trailing : .leading)
    }

    /// How long the line has been showing: it appears `LyricTimeline.lead` before it's sung.
    private var age: Double {
        guard let songTime, let span else { return 0 }
        return max(0, songTime - (span.lowerBound - LyricTimeline.lead))
    }

    /// Leave room above and below the headline row for the rest of the lyric.
    static func side(for size: CGSize) -> CGFloat { max(24, min(size.height * 0.58, size.width * 0.24, 78)) }
}

/// Intrinsic headline width, capped by the space left for the scene. Both views
/// receive disjoint rectangles and the same vertical centre, in either direction.
private struct StickerHeadlineRow: Layout {
    let onLeft: Bool
    let side: CGFloat
    let gap: CGFloat

    /// Marks the stage. While a line changes, the outgoing headline is still fading out
    /// beside the new one, so the row can't count on two children in order.
    struct Stage: LayoutValueKey { static let defaultValue = false }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 300)
        let height = subviews.filter { !$0[Stage.self] }
            .map { $0.sizeThatFits(.init(width: max(0, width - side - gap), height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: max(side, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let available = max(0, bounds.width - side - gap)
        let texts = subviews.filter { !$0[Stage.self] }
        // The stage sits beside the widest headline showing, so it never crosses text.
        let width = min(available, texts.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0)
        let textX = onLeft ? bounds.maxX - width : bounds.minX
        let stageX = onLeft ? textX - gap - side : textX + width + gap
        for text in texts {
            text.place(at: CGPoint(x: textX, y: bounds.midY), anchor: .leading,
                       proposal: .init(width: width, height: bounds.height))
        }
        for stage in subviews where stage[Stage.self] {
            stage.place(at: CGPoint(x: stageX, y: bounds.midY), anchor: .leading,
                        proposal: .init(width: side, height: side))
        }
    }
}

/// QA captures pin the scene clock (seconds into the capture) and give lines a sung
/// length in place of `LyricTimeline`'s spans; the app never sets either.
@MainActor
final class StickerCapture: ObservableObject {
    static let shared = StickerCapture()

    /// nil runs live.
    @Published var pinnedTime: Double?
    @Published var spans: [String: TimeInterval] = [:]
    /// The debug harness prepares one emoji before recording to avoid recording
    /// disk/decode latency. Normal playback leaves this empty.
    @Published var images: [String: StickerImages] = [:]
}

extension LyricSubject {
    private static let cache = OSAllocatedUnfairLock(initialState: [String: LyricSubject?]())
    nonisolated(unsafe) private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// The subject a line is about: the word vote (`vote`) with the poster's headline,
    /// then, for words in no list, Apple's on-device word meanings ("lilac" is near
    /// "flower"), kept strict. Cached per line text, so a returning chorus is read once.
    static func match(_ rawLine: String) -> LyricSubject? {
        let line = Lyrics.asides(rawLine).sung
        guard !line.isEmpty else { return nil }
        if let known = cache.withLock({ $0[line] }) { return known }
        let hero = PosterLyric.split(line).hero
        let result = vote(line, hero: hero) ?? nearest(line, hero: hero)
        cache.withLock { lines in
            if lines.count > 2_000 { lines.removeAll() }
            lines[line] = result
        }
        return result
    }

    /// The closest subject by meaning for the line's longer unlisted words, headline first.
    static func nearest(_ line: String, hero: String) -> LyricSubject? {
        guard let embedding else { return nil }
        let candidates = (words(hero) + words(line)).filter {
            $0.count >= 5 && !listed($0) && !stopWords.contains($0) && !PosterLyric.filler.contains($0)
        }
        var best: (LyricSubject, Double)?
        for word in candidates where embedding.contains(word) {
            for subject in allCases where !meaningExcluded.contains(subject) {
                guard let anchor = anchors[subject], embedding.contains(anchor) else { continue }
                let distance = embedding.distance(between: word, and: anchor)
                if distance < (best?.1 ?? meaningCutoff) { best = (subject, distance) }
            }
        }
        return best?.0
    }
}

/// Which Fluent Emoji a line shows: `StickerMatch` over the whole catalog (curated
/// subjects first), then the meaning fallback for the curated subjects. Cached per
/// line text. Until the catalog has loaded, only the curated subjects show.
enum StickerChoice {
    private static let cache = OSAllocatedUnfairLock(initialState: [String: String?]())

    static func emoji(for rawLine: String) -> String? {
        let line = Lyrics.asides(rawLine).sung
        guard !line.isEmpty else { return nil }
        if let known = cache.withLock({ $0[line] }) { return known }
        guard let index = StickerStore.shared.indexIfLoaded else {
            return LyricSubject.match(rawLine).flatMap { StickerMatch.subjectEmoji[$0] }
        }
        let hero = PosterLyric.split(line).hero
        let result = StickerMatch.pick(line, hero: hero, in: index)
            ?? LyricSubject.nearest(line, hero: hero).flatMap { StickerMatch.subjectEmoji[$0] }
        cache.withLock { lines in
            if lines.count > 2_000 { lines.removeAll() }
            lines[line] = result
        }
        return result
    }

    /// A song's lyrics loaded: match every line off the main thread and fetch the
    /// stickers they'll show, so each is ready when its line arrives. Empty lines,
    /// or another style, stop the last song's fetches.
    @MainActor
    static func prefetch(_ lines: [String]) {
        let store = StickerStore.shared
        guard ThemeStore.shared.lyricStyle == .stickers, !lines.isEmpty, store.directory != nil else {
            store.cancelSong()
            return
        }
        let token = store.beginSong()
        // The headline is measured here; matching (the catalog, the tables) runs off-main.
        let pairs = lines.map { line -> (String, String) in
            let sung = Lyrics.asides(line).sung
            return (sung, PosterLyric.split(sung).hero)
        }
        DispatchQueue.global(qos: .utility).async {
            guard let index = store.index else { return }
            var names: [String] = [], seen = Set<String>()
            for (line, hero) in pairs where !line.isEmpty {
                guard let name = StickerMatch.pick(line, hero: hero, in: index) else { continue }
                // `emoji(for:)` makes the same choice; cached, the main thread only looks it up.
                // (Lines with no match keep the meaning fallback, whose shared model stays on main.)
                cache.withLock { lines in
                    if lines.count > 2_000 { lines.removeAll() }
                    lines[line] = name
                }
                if seen.insert(name).inserted { names.append(name) }
            }
            store.prefetch(names, song: token)
        }
    }
}

// MARK: Images

/// Decoded on a single worker. The playback cache retains at most three files,
/// each capped at 48 MiB; view/layer owners release their images when they leave.
struct StickerImages: @unchecked Sendable {
    let frames: [CGImage]
    /// Start of each frame, in seconds (including the first frame at zero).
    let starts: [Double]
    let duration: Double
    /// It had to be downloaded while its line showed, so it enters from the start.
    var late = false
    var animated: Bool { frames.count > 1 && duration > 0 }

    func frame(at time: Double) -> CGImage {
        guard time.isFinite, time < duration else { return frames[frames.count - 1] }
        let index = starts.lastIndex(where: { $0 <= max(0, time) }) ?? 0
        return frames[index]
    }

    /// The emoji, and on the worker the file it resolved to: a downloaded animation
    /// replaces its still.
    private struct Key: Hashable {
        let emoji: String
        let settledOnly: Bool
        var file = ""
    }
    private struct Cache {
        var images: [Key: StickerImages] = [:]
        var recent: [Key] = []
    }
    private final class Request: @unchecked Sendable {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        var isCancelled: Bool { cancelled.withLock { $0 } }
    }
    private static let cache = OSAllocatedUnfairLock(initialState: Cache())
    private static let worker = DispatchQueue(label: "dev.opensource.MacSpaces.scene-images", qos: .userInitiated)

    /// The emoji's frames: bundled or cached files at once; otherwise its download is
    /// started and given `wait` seconds, after which there is nothing for this line.
    static func load(_ emoji: String, settledOnly: Bool = false, waitingUpTo wait: Double = 0.3) async -> StickerImages? {
        if let images = await read(emoji, settledOnly: settledOnly) { return images }
        guard wait > 0, !Task.isCancelled, await StickerStore.shared.request(emoji, waitingUpTo: wait) != nil,
              !Task.isCancelled, var images = await read(emoji, settledOnly: settledOnly) else { return nil }
        images.late = true
        return images
    }

    private static func read(_ emoji: String, settledOnly: Bool) async -> StickerImages? {
        let key = Key(emoji: emoji, settledOnly: settledOnly)
        let request = Request()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<StickerImages?, Never>) in
                worker.async {
                    let images = autoreleasepool { read(key, request: request) }
                    continuation.resume(returning: images)
                }
            }
        } onCancel: {
            request.cancelled.withLock { $0 = true }
        }
    }

    /// Called only on the serial image queue, including cache hits.
    private static func read(_ wanted: Key, request: Request) -> StickerImages? {
        guard !request.isCancelled, let url = StickerStore.shared.localFile(wanted.emoji) else { return nil }
        let key = Key(emoji: wanted.emoji, settledOnly: wanted.settledOnly, file: url.path)
        let cached = cache.withLock { state -> StickerImages? in
            guard let images = state.images[key] else { return nil }
            state.recent.removeAll { $0 == key }
            state.recent.append(key)
            return images
        }
        if let cached { return cached }
        let images = decode(url, settledOnly: key.settledOnly, request: request)
        guard !request.isCancelled else { return nil }
        if let images {
            cache.withLock { state in
                state.images[key] = images
                state.recent.removeAll { $0 == key }
                state.recent.append(key)
                while state.recent.count > 3 {
                    state.images.removeValue(forKey: state.recent.removeFirst())
                }
            }
        }
        return images
    }

    #if DEBUG
    /// The synchronous capture harness waits for the worker before recording.
    /// Avoid a MainActor task here: its caller may already own the main executor.
    static func loadForCapture(_ emoji: String, settledOnly: Bool) -> StickerImages? {
        let result = OSAllocatedUnfairLock(initialState: Optional<StickerImages>.none)
        let finished = DispatchSemaphore(value: 0)
        let key = Key(emoji: emoji, settledOnly: settledOnly)
        worker.async {
            let images = autoreleasepool { read(key, request: Request()) }
            result.withLock { $0 = images }
            finished.signal()
        }
        finished.wait()
        return result.withLock { $0 }
    }
    #endif

    private static func decode(_ url: URL, settledOnly: Bool, request: Request) -> StickerImages? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        let count = CGImageSourceGetCount(source)
        func image(_ index: Int) -> CGImage? {
            CGImageSourceCreateImageAtIndex(source, index, options)
        }
        // Some older ImageIO WebP decoders expose only the first frame, or fail
        // on later frames. A still of the first frame remains a valid scene.
        guard let first = image(0) else { return nil }
        func still(_ frame: CGImage) -> StickerImages {
            StickerImages(frames: [frame], starts: [0], duration: 0)
        }
        guard count > 1 else { return still(first) }
        if settledOnly { return still(image(count - 1) ?? first) }
        let bytes = first.bytesPerRow * first.height
        guard bytes > 0, count <= (48 * 1_024 * 1_024) / bytes else { return still(first) }
        var frames: [CGImage] = [], starts: [Double] = []
        var elapsed = 0.0
        for index in 0..<count {
            guard !request.isCancelled else { return nil }
            guard let frame = index == 0 ? first : image(index) else { return still(first) }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            // Bundled WebP, cached HEIC sequences, or APNG where HEIC couldn't be written.
            let timing: [(CFString, CFString, CFString)] = [
                (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
                (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
                (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            ]
            let delay = timing.lazy.compactMap { dictionary, unclamped, clamped -> Double? in
                guard let values = properties?[dictionary] as? [CFString: Any] else { return nil }
                return (values[unclamped] as? NSNumber)?.doubleValue ?? (values[clamped] as? NSNumber)?.doubleValue
            }.first ?? 0.05
            starts.append(elapsed)
            frames.append(frame)
            // Preserve Microsoft's 20 fps timing even when a decoder omits delays.
            elapsed += delay.isFinite && delay > 0 ? delay : 0.05
        }
        return StickerImages(frames: frames, starts: starts, duration: elapsed)
    }
}

// MARK: Stage

private struct StickerStage: View {
    let emoji: String?
    let timing: LyricChoreography
    let age: Double
    let side: CGFloat
    let height: CGFloat
    let onLeft: Bool
    let accent: Color
    let ink: Color
    let animated: Bool
    let playing: Bool
    @ObservedObject private var capture = StickerCapture.shared
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var shown: StickerShowing?
    @State private var leaving: StickerShowing?

    private var scene: StickerScene? {
        emoji.map { StickerScene(emoji: $0, side: side, height: height, onLeft: onLeft) }
    }

    var body: some View {
        let built = scene
        let reduced = systemReduceMotion || theme.reduceMotion
        Group {
            if reduced {
                if let built { StickerFrame(scene: built, timing: timing, time: .infinity) }
            } else if animated, capture.pinnedTime == nil {
                StickerLayerScene(scene: built, timing: timing, age: age, playing: playing)
            } else if let pinned = capture.pinnedTime {
                ZStack {
                    if let leaving {
                        StickerFrame(scene: leaving.scene, timing: leaving.timing, time: pinned - leaving.start,
                                     leaving: pinned - (leaving.exitStart ?? pinned))
                    }
                    if let shown { StickerFrame(scene: shown.scene, timing: shown.timing, time: pinned - shown.start) }
                }
            } else if let built {
                StickerFrame(scene: built, timing: timing, time: .infinity)
            }
        }
        .frame(width: side, height: height)
        .mask(LinearGradient(stops: Self.edgeStops(onLeft: onLeft).map { .init(color: .black.opacity($0.1), location: $0.0) },
                             startPoint: .leading, endPoint: .trailing))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard let pinned = capture.pinnedTime else { return }
            shown = built.map { StickerShowing(scene: $0, timing: timing, start: pinned - age) }
        }
        .onChange(of: StickerArrival(scene: built, timing: timing, age: age)) { arrival in
            guard let pinned = capture.pinnedTime else { return }
            if let next = arrival.scene, shown?.scene.emoji == next.emoji {
                shown?.scene = next
                return
            }
            if var old = shown { old.exitStart = pinned; leaving = old }
            shown = arrival.scene.map { StickerShowing(scene: $0, timing: arrival.timing, start: pinned - arrival.age) }
        }
    }

    static func edgeStops(onLeft: Bool) -> [(Double, Double)] {
        let fromPoster: [(Double, Double)] = [(0, 0), (0.07, 1), (0.95, 1), (1, 0)]
        return onLeft ? fromPoster.reversed().map { (1 - $0.0, $0.1) } : fromPoster
    }
}

private struct StickerArrival: Equatable {
    let scene: StickerScene?
    let timing: LyricChoreography
    let age: Double
    static func == (a: StickerArrival, b: StickerArrival) -> Bool { a.scene?.key == b.scene?.key }
}

private struct StickerShowing {
    var scene: StickerScene
    var timing: LyricChoreography
    var start: Double
    var exitStart: Double?
}

// MARK: Shared motion

struct StickerScene {
    struct Key: Hashable {
        let emoji: String
        let side: CGFloat
        let height: CGFloat
        let onLeft: Bool
    }
    /// The Fluent Emoji's name in the catalog.
    let emoji: String
    let side: CGFloat
    let height: CGFloat
    let onLeft: Bool
    var key: Key { Key(emoji: emoji, side: side, height: height, onLeft: onLeft) }
    /// The curated subject drawn by this emoji, whose still has its own gesture.
    var subject: LyricSubject? { StickerMatch.bundledSubject[emoji] }
    var square: CGRect { CGRect(x: 0, y: (height - side) / 2, width: side, height: side) }
    var outward: Double { onLeft ? -1 : 1 }

    // Keep LyricChoreography's tempo and action budget; the emoji entrance is a
    // smaller pop than the old full scene's entrance. WebP playback stays natural.
    func entrance(_ timing: LyricChoreography) -> Double { min(0.4, max(0.25, 0.34 / timing.tempo)) }
    func exitDuration(_ timing: LyricChoreography) -> Double { min(0.3, max(0.18, timing.exit * 0.6)) }
    func settled(_ timing: LyricChoreography, images: StickerImages) -> Double {
        entrance(timing) + (images.animated ? images.duration : timing.action)
    }

    struct Pose {
        var x = 0.0, y = 0.0, scale = 1.0, rotation = 0.0, opacity = 1.0
        var transform: CATransform3D {
            var result = CATransform3DMakeTranslation(CGFloat(x), CGFloat(y), 0)
            result = CATransform3DRotate(result, CGFloat(rotation * .pi / 180), 0, 0, 1)
            return CATransform3DScale(result, CGFloat(scale), CGFloat(scale), 1)
        }
    }

    func pose(at time: Double, timing: LyricChoreography, animatedImage: Bool) -> Pose {
        guard time.isFinite else { return Pose() }
        let enter = entrance(timing)
        let p = min(1, max(0, time / enter))
        let eased = 1 - pow(1 - p, 3)
        var pose = Pose(x: outward * Double(side) * 0.08 * (1 - eased),
                        y: Double(side) * 0.09 * (1 - eased),
                        scale: 0.78 + 0.22 * eased, opacity: eased)
        if subject == .crown, !animatedImage {
            pose.y = -Double(side) * 0.16 * (1 - eased)
        }
        guard !animatedImage, time >= enter else { return pose }
        let a = min(1, max(0, (time - enter) / timing.action))
        // A single gesture with a quiet return to rest, never a repeating loop.
        let pulse = sin(a * .pi)
        switch subject {
        case .money:
            pose.rotation = sin(a * 2 * .pi) * 9 * (1 - a)
            pose.y = -Double(side) * 0.07 * pulse
        case .cards: pose.rotation = -7 * pulse
        case .dance: pose.x = Double(side) * 0.05 * pulse; pose.rotation = 7 * pulse
        case .rose: pose.rotation = -5 * pulse
        case .moon: pose.rotation = 5 * pulse
        case .phone: pose.rotation = sin(a * 2 * .pi) * 6 * (1 - a)
        case .city, .home: pose.scale = 1 + 0.035 * pulse
        case .crown: break // The entrance itself drops the crown into place.
        case .diamond: pose.scale = 1 + 0.09 * pulse
        case .drink, .cup: pose.rotation = -9 * pulse
        case .sneakers: pose.y = -Double(side) * 0.08 * pulse; pose.rotation = -5 * pulse
        case .guitar: pose.rotation = -12 * pulse
        case .microphone: pose.rotation = 10 * pulse
        case nil:
            // Any other still: a small lift and tilt toward the headline, then rest.
            pose.y = -Double(side) * 0.06 * pulse
            pose.rotation = -6 * outward * pulse
        default: break // WebP decoder fallback holds a still after the entrance.
        }
        return pose
    }

    func exitPose(at time: Double, timing: LyricChoreography) -> Pose {
        let p = min(1, max(0, time / exitDuration(timing)))
        return Pose(y: Double(side) * 0.04 * p * p, scale: 1 - 0.12 * p * p, opacity: 1 - p)
    }
}

// MARK: SwiftUI stills and pinned frames

private struct StickerFrame: View {
    let scene: StickerScene
    let timing: LyricChoreography
    let time: Double
    var leaving: Double?
    @State private var images: StickerImages?
    @State private var loadedEmoji: String?
    @ObservedObject private var capture = StickerCapture.shared

    var body: some View {
        let loaded = capture.images[scene.emoji] ?? (loadedEmoji == scene.emoji ? images : nil)
        Group {
            if let loaded {
                let pose = scene.pose(at: time, timing: timing, animatedImage: loaded.animated)
                let exit = scene.exitPose(at: leaving ?? 0, timing: timing)
                Image(decorative: loaded.frame(at: time - scene.entrance(timing)), scale: 1)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: scene.side, height: scene.side)
                    .rotationEffect(.degrees(pose.rotation))
                    .scaleEffect(pose.scale)
                    .offset(x: pose.x, y: pose.y)
                    .opacity(pose.opacity)
                    .scaleEffect(exit.scale)
                    .offset(x: exit.x, y: exit.y)
                    .opacity(exit.opacity)
                    .position(x: scene.square.midX, y: scene.square.midY)
            }
        }
        .frame(width: scene.side, height: scene.height)
        .task(id: scene.emoji) { [emoji = scene.emoji, settledOnly = !time.isFinite] in
            images = nil
            guard capture.images[emoji] == nil else { return }
            let loaded = await StickerImages.load(emoji, settledOnly: settledOnly)
            guard !Task.isCancelled else { return }
            loadedEmoji = emoji
            images = loaded
        }
    }
}

// MARK: Core Animation playback

private struct StickerLayerScene: NSViewRepresentable {
    let scene: StickerScene?
    let timing: LyricChoreography
    let age: Double
    let playing: Bool

    func makeNSView(context: Context) -> StageView { StageView() }
    func updateNSView(_ view: StageView, context: Context) { view.show(scene, timing: timing, age: age, playing: playing) }
    static func dismantleNSView(_ view: StageView, coordinator: ()) { view.clear() }

    final class StageView: NSView {
        private let stage = CALayer()
        private var requested: StickerScene?
        private var load: Task<Void, Never>?
        private var current: (scene: StickerScene, container: CALayer, timing: LyricChoreography)?
        private weak var outgoing: CALayer?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            stage.isGeometryFlipped = true
            layer?.addSublayer(stage)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            stage.frame = bounds
            CATransaction.commit()
        }

        func clear() {
            load?.cancel(); load = nil
            stage.sublayers?.forEach { $0.removeFromSuperlayer() }
            current = nil; requested = nil
        }

        func show(_ scene: StickerScene?, timing: LyricChoreography, age: Double, playing: Bool) {
            layer?.speed = Float(1 / Design.demoTimeScale)
            playing ? Self.resume(stage) : Self.pause(stage)
            let previous = requested
            requested = scene
            if scene?.emoji == previous?.emoji {
                // A new headline may put the same sticker on the opposite side.
                // Keep its original playback clock and settled pose in that lane.
                if let scene, let current {
                    CATransaction.begin(); CATransaction.setDisableActions(true)
                    current.container.frame = scene.square
                    current.container.sublayers?.first?.frame = current.container.bounds
                    CATransaction.commit()
                    self.current = (scene, current.container, current.timing)
                }
                return
            }
            load?.cancel(); load = nil
            outgoing?.removeFromSuperlayer()
            if let old = current { leave(old.scene, container: old.container, timing: old.timing) }
            current = nil
            guard let scene else { return }
            let started = stage.convertTime(CACurrentMediaTime(), from: nil)
            load = Task { @MainActor [weak self] in
                let images = await StickerImages.load(scene.emoji)
                guard !Task.isCancelled, let self, let latest = self.requested,
                      latest.emoji == scene.emoji, let images else { return }
                // A sticker that had to be downloaded enters from its start; otherwise
                // decoding time counts, so it stays in step with the line.
                let elapsed = images.late ? 0 : max(0, self.stage.convertTime(CACurrentMediaTime(), from: nil) - started)
                self.present(latest, images: images, timing: timing, age: age + elapsed)
            }
        }

        private func present(_ scene: StickerScene, images: StickerImages, timing: LyricChoreography, age: Double) {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let container = CALayer()
            container.frame = scene.square
            let image = CALayer()
            image.frame = container.bounds
            image.contentsGravity = .resizeAspect
            image.contentsScale = window?.backingScaleFactor ?? 2
            image.contents = images.frames[images.frames.count - 1]
            container.addSublayer(image)
            stage.addSublayer(container)
            let begin = image.convertTime(CACurrentMediaTime(), from: nil) - max(0, age)
            let enter = scene.entrance(timing)
            if images.animated {
                let animation = CAKeyframeAnimation(keyPath: "contents")
                animation.values = images.frames.map { $0 as Any } + [images.frames[images.frames.count - 1] as Any]
                animation.keyTimes = images.starts.map { NSNumber(value: $0 / images.duration) } + [1]
                animation.calculationMode = .discrete
                animation.beginTime = begin + enter
                animation.duration = images.duration
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                image.add(animation, forKey: "fluent-play-once")
            }
            // Sample only once while installing the animation, never per frame live.
            let length = images.animated ? enter : scene.settled(timing, images: images)
            let count = max(2, Int(ceil(length * 60)) + 1)
            var times: [NSNumber] = [], transforms: [NSValue] = [], opacities: [NSNumber] = []
            for index in 0..<count {
                let fraction = Double(index) / Double(count - 1)
                let pose = scene.pose(at: fraction * length, timing: timing, animatedImage: images.animated)
                times.append(NSNumber(value: fraction))
                transforms.append(NSValue(caTransform3D: pose.transform))
                opacities.append(NSNumber(value: pose.opacity))
            }
            func motion(_ path: String, values: [Any]) -> CAKeyframeAnimation {
                let animation = CAKeyframeAnimation(keyPath: path)
                animation.values = values; animation.keyTimes = times
                animation.duration = length; animation.beginTime = begin
                animation.fillMode = .both; animation.isRemovedOnCompletion = false
                animation.calculationMode = .linear
                return animation
            }
            image.add(motion("transform", values: transforms), forKey: "gesture")
            image.add(motion("opacity", values: opacities), forKey: "entrance")
            CATransaction.commit()
            current = (scene, container, timing)
        }

        private func leave(_ scene: StickerScene, container: CALayer, timing: LyricChoreography) {
            guard stage.speed != 0 else { container.removeFromSuperlayer(); return }
            outgoing = container
            let pose = scene.exitPose(at: .infinity, timing: timing)
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            move.toValue = NSValue(caTransform3D: pose.transform)
            move.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0
            let animation = CAAnimationGroup()
            animation.animations = [move, fade]
            animation.duration = scene.exitDuration(timing)
            // Explicit transaction duration keeps removal aligned with the exit.
            CATransaction.begin(); CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(animation.duration)
            CATransaction.setCompletionBlock { [weak container] in container?.removeFromSuperlayer() }
            container.transform = pose.transform; container.opacity = 0
            container.add(animation, forKey: "exit")
            CATransaction.commit()
        }

        private static func pause(_ layer: CALayer) {
            guard layer.speed != 0 else { return }
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0; layer.timeOffset = now
        }
        private static func resume(_ layer: CALayer) {
            guard layer.speed == 0 else { return }
            let paused = layer.timeOffset
            layer.speed = 1; layer.timeOffset = 0; layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        }
    }
}

#if DEBUG
/// One Fluent scene at a fixed moment of a medium-paced line.
struct StickerStill: View {
    let subject: LyricSubject
    let accent: Color
    var ink: Color = .white
    let time: Double
    var side: CGFloat = 60

    var body: some View {
        StickerFrame(scene: StickerScene(emoji: StickerMatch.subjectEmoji[subject]!, side: side, height: side, onLeft: false),
                     timing: LyricChoreography.timing(span: nil, words: 6), time: time)
            .frame(width: side, height: side)
    }
}
#endif
