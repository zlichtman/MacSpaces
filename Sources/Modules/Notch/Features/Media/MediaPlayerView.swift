import SwiftUI
import AppKit
import CoreImage

/// Theme-aware Nook player with artwork ambience, metadata, scrubbing, and
/// transport controls. The selected Nook theme remains the primary palette;
/// album artwork adds depth without replacing the user's color choices.
struct MediaPlayerView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    var largeArtwork = false
    var lyricsService: TeleprompterService?
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Group {
            if largeArtwork { editorialLayout } else { classicLayout }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Chosen by the tile's width only. Measuring content here made a long
    /// title (e.g. a live recording's name) flip the widget to the stacked
    /// layout; titles now truncate instead.
    private var classicLayout: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 230 {
                widgetLayout(proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                compactStack
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private var compactStack: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    sourceButton {
                        RecordArtwork(artwork: nowPlaying.info.artwork, accent: theme.notch.accent,
                                      control: theme.notch.control, size: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
                            .font(.system(size: 11, weight: .semibold)).lineLimit(2)
                        Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                PlaybackTimeline(nowPlaying: nowPlaying, compact: true)
                controls.frame(maxWidth: .infinity)
            }
    }

    /// The Home widget, styled like the Music page at a smaller scale: cover beside
    /// title, a slim scrubber and plain
    /// skip buttons around the play button. The tile's header is left out; the
    /// cover says what it is.
    private func widgetLayout(_ size: CGSize) -> some View {
        let side = max(64, min(size.height - 10, size.width * 0.4, 132))
        return HStack(alignment: .center, spacing: 14) {
            sourceButton {
                RecordArtwork(artwork: nowPlaying.info.artwork, accent: theme.notch.accent,
                              control: theme.notch.control, size: side)
            }
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
                        .font(.system(size: 15, weight: .bold)).lineLimit(1)
                    Text(editorialSubtitle)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                PlaybackTimeline(nowPlaying: nowPlaying)
                widgetControls.padding(.top, 6)
            }
            .frame(height: side)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
    }

    private var widgetControls: some View {
        HStack(spacing: 20) {
            Button { nowPlaying.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(PremiumPressButtonStyle()).disabled(!nowPlaying.supports(.previous)).accessibilityLabel("Previous")
            Button { nowPlaying.togglePlayPause() } label: {
                Image(systemName: nowPlaying.displayIsPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .background(theme.notch.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PremiumPressButtonStyle()).disabled(!nowPlaying.supports(.playPause))
            .accessibilityLabel(nowPlaying.displayIsPlaying ? "Pause" : "Play")
            Button { nowPlaying.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(PremiumPressButtonStyle()).disabled(!nowPlaying.supports(.next)).accessibilityLabel("Next")
        }
        .frame(maxWidth: .infinity)
    }

    /// The standalone Music page reserves the right column for lyrics. Transport
    /// sits beneath the cover, with the timeline beside it in the same bottom row.
    @ViewBuilder
    private var editorialLayout: some View {
        if !nowPlaying.info.hasTrack {
            // Nothing to show yet: no empty cover or dead controls, just a way to start.
            // (Blank until the first read, so a playing song never flashes this.)
            if nowPlaying.hasCompletedInitialRefresh { NothingPlayingView(accent: theme.notch.accent) }
        } else {
            playingLayout
        }
    }

    private var playingLayout: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 24
            let side = max(120, min(180, (proxy.size.width - 40 - gap) * 0.4,
                                    proxy.size.height - 56))
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: gap) {
                    sourceButton {
                        RecordArtwork(artwork: nowPlaying.info.artwork, accent: theme.notch.accent,
                                      control: theme.notch.control, size: side)
                    }
                    editorialColumn(lyrics: nowPlaying.info.hasTrack ? lyricsService : nil)
                        .frame(height: side)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .center, spacing: gap) {
                    editorialControls(width: side)
                        .frame(width: side)
                    PlaybackTimeline(nowPlaying: nowPlaying)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// Metadata stays anchored at the top while the remaining area forms a lyric
    /// canvas. The presentation remains mounted while lyrics are loading.
    private func editorialColumn(lyrics: TeleprompterService?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(editorialSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            if let lyrics {
                PlayerLyrics(service: lyrics)
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    /// Plain previous/next glyphs flank one prominent play button.
    private func editorialControls(width: CGFloat) -> some View {
        HStack(spacing: min(28, max(6, (width - 108) / 2))) {
            glyphButton("backward.fill", capability: .previous, label: "Previous") { nowPlaying.previousTrack() }
            Button { nowPlaying.togglePlayPause() } label: {
                Image(systemName: nowPlaying.displayIsPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(theme.notch.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PremiumPressButtonStyle())
            .disabled(!nowPlaying.supports(.playPause))
            .accessibilityLabel(nowPlaying.displayIsPlaying ? "Pause" : "Play")
            glyphButton("forward.fill", capability: .next, label: "Next") { nowPlaying.nextTrack() }
        }
        .frame(maxWidth: .infinity)
    }

    private func glyphButton(_ symbol: String, capability: PlaybackCapability, label: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .disabled(!nowPlaying.supports(capability))
        .accessibilityLabel(label)
    }

    /// Opens the playing app from its artwork, like the system Now Playing view.
    @ViewBuilder
    private func sourceButton<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if nowPlaying.canOpenSource {
            Button { nowPlaying.openSource() } label: { content() }
                .buttonStyle(PremiumPressButtonStyle())
                .help("Open \(nowPlaying.info.sourceName)")
                .accessibilityLabel("Open \(nowPlaying.info.sourceName)")
        } else {
            content()
        }
    }

    private var subtitle: String {
        if !nowPlaying.info.artist.isEmpty {
            return nowPlaying.info.artist
        }
        return nowPlaying.info.hasTrack ? nowPlaying.info.album : "Music or Spotify"
    }

    /// Artist, plus the album only when it adds something (singles are
    /// usually named after the song).
    private var editorialSubtitle: String {
        let info = nowPlaying.info
        guard info.hasTrack else { return "Play something in Music, Spotify or a browser" }
        let album = info.album.caseInsensitiveCompare(info.title) == .orderedSame
            || info.album.caseInsensitiveCompare(info.artist) == .orderedSame ? "" : info.album
        return [info.artist, album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            transportButton("backward.fill", capability: .previous) {
                nowPlaying.previousTrack()
            }
            transportButton(
                nowPlaying.displayIsPlaying ? "pause.fill" : "play.fill",
                capability: .playPause,
                prominent: true
            ) {
                nowPlaying.togglePlayPause()
            }
            transportButton("forward.fill", capability: .next) {
                nowPlaying.nextTrack()
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        capability: PlaybackCapability,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let diameter: CGFloat = largeArtwork ? (prominent ? 42 : 36) : (prominent ? 28 : 25)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: largeArtwork ? (prominent ? 17 : 14) : (prominent ? 13 : 10), weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.82) : Color.primary)
                .frame(width: diameter, height: diameter)
                .background(
                    prominent ? theme.notch.accent : theme.notch.control,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .disabled(!nowPlaying.supports(capability))
    }

}

/// The scrubber and its times. Only this small view redraws as the song plays:
/// it reads the controller's clock on a quarter-second timeline (no polls in
/// between), so the rest of the player stays still.
private struct PlaybackTimeline: View {
    @ObservedObject var nowPlaying: NowPlayingController
    /// The Home widget's narrow layout: the system slider and small times.
    var compact = false
    @ObservedObject private var theme = ThemeStore.shared
    /// Where the person is dragging; nil follows the song.
    @State private var dragPosition: Double?
    /// Counts drags, so a seek's hold never ends a newer drag.
    @State private var dragCount = 0
    @State private var watcherID = UUID()

    var body: some View {
        let info = nowPlaying.info
        Group {
            if info.duration > 0 {
                TimelineView(.periodic(from: .now, by: info.isPlaying && dragPosition == nil ? 0.25 : 3600)) { context in
                    let position = dragPosition ?? min(max(nowPlaying.estimatedElapsed(at: context.date), 0), info.duration)
                    content(position: position, duration: info.duration)
                }
            }
        }
        .onAppear { nowPlaying.watchPosition(true, id: watcherID) }
        .onDisappear { nowPlaying.watchPosition(false, id: watcherID) }
        .onChange(of: info.title) { _ in dragPosition = nil }
    }

    private var binding: Binding<Double> {
        Binding(get: { dragPosition ?? nowPlaying.estimatedElapsed(at: Date()) },
                set: { dragPosition = $0 })
    }

    private func editingChanged(_ editing: Bool) {
        if editing {
            dragCount &+= 1
            if dragPosition == nil { dragPosition = nowPlaying.estimatedElapsed(at: Date()) }
        } else if let target = dragPosition {
            nowPlaying.seek(to: target)
            // Keep showing the target until the player reports the seek.
            let drag = dragCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if dragCount == drag { dragPosition = nil } }
        }
    }

    @ViewBuilder
    private func content(position: Double, duration: Double) -> some View {
        if compact {
            Slider(value: binding, in: 0...max(duration, 1), onEditingChanged: editingChanged)
                .accessibilityLabel("Playback position")
                // The controller drops commands while one is in flight; dimming the
                // control for each round trip would make it flicker on every seek.
                .disabled(!nowPlaying.supports(.seek))
                .controlSize(.mini)
                .tint(theme.notch.accent)
            times(position: position, duration: duration)
                .font(.system(size: 8, design: .rounded))
        } else {
            VStack(spacing: 5) {
                PlaybackScrubber(position: position, duration: duration, enabled: nowPlaying.supports(.seek),
                                 onDrag: { dragPosition = $0 }, onEditing: editingChanged)
                times(position: position, duration: duration)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
        }
    }

    private func times(position: Double, duration: Double) -> some View {
        HStack {
            Text(Self.timeText(position))
            Spacer()
            Text("-\(Self.timeText(max(duration - position, 0)))")
        }
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    static func timeText(_ interval: TimeInterval) -> String {
        let seconds = interval.isFinite ? max(0, Int(min(interval, 86_400_000))) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// A compact, low-cost artwork treatment for the Nook player.
/// It deliberately avoids continuous rotation so live media never makes the
/// surrounding notch interaction feel heavy.
struct RecordArtwork: View {
    let artwork: NSImage?
    let accent: Color
    let control: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(control)

            HeldArtwork(artwork: artwork) { cover in
                if let cover {
                    Image(nsImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.30, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: size - 6, height: size - 6)
            .clipShape(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            )

        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(artwork == nil ? 0.18 : 0.32), radius: size * 0.08, y: size * 0.04)
    }
}

/// The Music page with nothing playing: one compact, centred invitation, with a
/// button for each music app on this Mac that opens it.
private struct NothingPlayingView: View {
    let accent: Color

    struct Player: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
    }

    /// Spotify and Music, whichever are installed.
    static let players: [Player] = [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")].compactMap { id, name in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return Player(id: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(accent.opacity(0.14)).frame(width: 64, height: 64)
                Circle().strokeBorder(accent.opacity(0.3), lineWidth: 1).frame(width: 64, height: 64)
                Image(systemName: "music.note").font(.system(size: 26, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(spacing: 4) {
                Text("Nothing playing").font(.system(size: 17, weight: .bold))
                Text("Start a song and it plays here, with its lyrics.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            if !Self.players.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Self.players) { player in
                        Button { open(player) } label: {
                            HStack(spacing: 6) {
                                Image(nsImage: player.icon).resizable().frame(width: 18, height: 18)
                                Text("Open \(player.name)").font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PremiumPressButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private func open(_ player: Player) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A song change clears the cover until the new one loads (usually a fraction
/// of a second). Keeping the last cover through that gap, then crossfading,
/// avoids flashing the placeholder on every skip; after `hold` with nothing
/// new, the placeholder shows.
struct HeldArtwork<Content: View>: View {
    let artwork: NSImage?
    var hold: TimeInterval = 1.5
    let content: (NSImage?) -> Content
    @State private var shown: NSImage?

    init(artwork: NSImage?, hold: TimeInterval = 1.5, @ViewBuilder content: @escaping (NSImage?) -> Content) {
        self.artwork = artwork
        self.hold = hold
        self.content = content
        _shown = State(initialValue: artwork)
    }

    var body: some View {
        ZStack {
            content(shown)
                .id(shown.map(ObjectIdentifier.init))
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.22), value: shown.map(ObjectIdentifier.init))
        .task(id: artwork.map(ObjectIdentifier.init)) {
            if let artwork { shown = artwork; return }
            guard shown != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            if !Task.isCancelled, artwork == nil { shown = nil }
        }
    }
}

/// Show only resolved lyric text. Loading, missing lyrics and provider failures
/// stay silent, including for VoiceOver; the mounted view keeps lookup active.
private struct PlayerLyrics: View {
    @ObservedObject var service: TeleprompterService
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentationID = UUID()

    /// The system's Reduce Motion or the app's own.
    private var animated: Bool { !reduceMotion && !theme.reduceMotion }

    var body: some View {
        Group {
            if service.currentText.isEmpty {
                // Stay mounted while lookup runs; never show status placeholders.
                Color.clear
            } else if animated, service.lineSpan != nil, theme.lyricStyle.followsSong {
                // Karaoke fills and Typewriter types with the song itself, so this one
                // timeline runs only for them, only while the song plays.
                TimelineView(.periodic(from: .now, by: service.isPlaying ? 1.0 / 30 : 3600)) { context in
                    lyric(at: service.elapsed(at: context.date))
                }
            } else {
                lyric(at: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Keyed by line, so a repeated line (a chorus hook) still turns over.
        .animation(animated ? Design.timed(.easeOut(duration: 0.18)) : nil, value: service.lineID)
        .onAppear { service.setPresentationVisible(true, id: presentationID) }
        .onDisappear { service.setPresentationVisible(false, id: presentationID) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(service.currentText.isEmpty ? "" : "Lyrics: \(service.currentText)")
        .accessibilityHidden(service.currentText.isEmpty)
    }

    private func lyric(at elapsed: TimeInterval?) -> some View {
        let span = service.lineSpan
        // Untimed lyrics have no sung span: Karaoke shows them filled and readable.
        let progress = elapsed.map { LyricTimeline.progress(of: span, at: $0) } ?? (span == nil ? 1 : 0)
        let typed = elapsed.flatMap { now in span.map { TypewriterTiming.typed(at: now, span: $0) } }
        return StyledLyricView(style: theme.lyricStyle, current: service.currentText,
                               upcoming: service.upcomingText, accent: theme.notch.accent, ink: theme.nookForeground,
                               animated: animated, sequence: service.lineID, progress: progress, typed: typed)
    }
}

/// A thin capsule that thickens and shows a knob while hovered or dragged.
private struct PlaybackScrubber: View {
    let position: Double
    let duration: Double
    let enabled: Bool
    let onDrag: (Double) -> Void
    let onEditing: (Bool) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            let active = enabled && (hovering || dragging)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                Capsule().fill(Color.primary.opacity(active ? 0.95 : 0.75))
                    .frame(width: max(proxy.size.width * fraction, active ? 6 : 4))
            }
            .frame(height: active ? 6 : 4)
            // The knob floats over the track so it never thickens the bar.
            .overlay(alignment: .leading) {
                Circle().fill(Color.primary)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: proxy.size.width * fraction - 6)
                    .opacity(active ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard enabled else { return }
                    if !dragging { dragging = true; onEditing(true) }
                    onDrag(min(max(value.location.x / max(proxy.size.width, 1), 0), 1) * duration)
                }
                .onEnded { _ in
                    guard dragging else { return }
                    dragging = false
                    onEditing(false)
                })
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(position)) of \(Int(duration)) seconds")
    }
}

/// The cover, blurred and faint, so each album tints the Music page. The
/// panel draws it inside its own shape, so it follows the panel's corners.
/// It draws a small pre-blurred copy of the cover, so it costs almost nothing.
struct MusicArtworkAmbience: View {
    // Prepared as artwork arrives, even while this page is closed.
    let nowPlaying: NowPlayingController
    @ObservedObject private var wash = ArtworkWashStore.shared
    var body: some View { ArtworkAmbience(artwork: wash.image) }
}

struct ArtworkAmbience: View {
    let artwork: NSImage?
    var body: some View {
        GeometryReader { proxy in
            if let artwork {
                Image(nsImage: artwork).resizable().interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .saturation(1.25).opacity(0.22).clipped()
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}

@MainActor
final class ArtworkWashStore: ObservableObject {
    static let shared = ArtworkWashStore()
    @Published private(set) var image: NSImage?
    private var original: NSImage?
    private var generation = UUID()
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.artwork-wash", qos: .utility)
    private let renderer = ArtworkWashRenderer()

    func prepare(_ artwork: NSImage?) {
        guard artwork !== original else { return }
        original = artwork
        generation = UUID()
        let requested = generation
        guard let artwork else {
            // A skip clears the cover until the next one loads; keep the wash
            // through that gap (like the cover itself) instead of blinking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.generation == requested else { return }
                self.image = nil
            }
            return
        }
        let renderer = renderer
        queue.async { [weak self] in
            let image = renderer.wash(for: artwork)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == requested else { return }
                self.image = image
            }
        }
    }
}

/// Context and bounded cache are confined to ArtworkWashStore.queue.
private final class ArtworkWashRenderer: @unchecked Sendable {
    private lazy var context = CIContext()
    private let cache: NSCache<NSImage, NSImage> = {
        let cache = NSCache<NSImage, NSImage>(); cache.countLimit = 8; return cache
    }()
    func wash(for artwork: NSImage) -> NSImage? {
        if let image = cache.object(forKey: artwork) { return image }
        let side: CGFloat = 48
        guard let cg = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        let scale = side / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(small.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(7, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: small.extent),
              let rendered = context.createCGImage(output, from: small.extent) else { return nil }
        let image = NSImage(cgImage: rendered, size: NSSize(width: side, height: side))
        cache.setObject(image, forKey: artwork)
        return image
    }
}

/// Controls belong to the active Music page's dock capsule, below its content.
struct MusicDockControls: View {
    @ObservedObject var nowPlaying: NowPlayingController
    @State private var showingPlaylist = false
    static func hasPlaylist(for info: NowPlayingInfo) -> Bool {
        if let id = info.sourceBundleID { return id == "com.apple.Music" }
        return info.sourceName == "Music"
    }
    var body: some View {
        Group {
            if Self.hasPlaylist(for: nowPlaying.info) {
                Button { showingPlaylist.toggle() } label: {
                    Image(systemName: "list.bullet").font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30).contentShape(Circle())
                }
                .help("Music playlist").accessibilityLabel("Music playlist")
                .popover(isPresented: $showingPlaylist) { MusicQueueView(sourceBundleID: "com.apple.Music") }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: nowPlaying.info.sourceBundleID) { _ in showingPlaylist = false }
        .onChange(of: nowPlaying.info.sourceName) { _ in showingPlaylist = false }
    }
}
