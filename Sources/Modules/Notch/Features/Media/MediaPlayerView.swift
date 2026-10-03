import SwiftUI
import AppKit
import CoreImage

/// Theme-aware Nook player with artwork ambience, metadata, scrubbing, and
/// transport controls. The selected Nook theme remains the primary palette;
/// album artwork adds depth without replacing the user's color choices.
struct MediaPlayerView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    let style: WidgetVisualStyle
    var largeArtwork = false
    var lyricsService: TeleprompterService?
    @ObservedObject private var theme = ThemeStore.shared
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        Group {
            if largeArtwork { editorialLayout } else { classicLayout }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncScrubPosition() }
        .onChange(of: nowPlaying.info.elapsed) { _ in
            if !isScrubbing { syncScrubPosition() }
        }
        .onChange(of: nowPlaying.info.title) { _ in
            if !isScrubbing { syncScrubPosition() }
        }
        // Polls arrive roughly once a second; advance between them so the
        // scrubber glides instead of stepping.
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { now in
            guard !isScrubbing, nowPlaying.info.isPlaying, nowPlaying.info.duration > 0 else { return }
            scrubPosition = min(nowPlaying.estimatedElapsed(at: now), nowPlaying.info.duration)
        }
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
                progressView
                controls.frame(maxWidth: .infinity)
            }
    }

    /// The Home widget, styled like the Music page at a smaller scale: cover beside
    /// title, the current lyric in the accent colour, a slim scrubber and plain
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
                Spacer(minLength: 4)
                if let lyricsService, nowPlaying.info.hasTrack {
                    WidgetLyricLine(service: lyricsService)
                }
                Spacer(minLength: 4)
                editorialProgress
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
    private var editorialLayout: some View {
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
                    editorialProgress
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

    /// A slim bar with times underneath, like the system Now Playing view.
    @ViewBuilder
    private var editorialProgress: some View {
        if nowPlaying.info.duration > 0 {
            VStack(spacing: 5) {
                PlaybackScrubber(position: $scrubPosition, duration: nowPlaying.info.duration,
                                 enabled: nowPlaying.supports(.seek)) { editing in
                    isScrubbing = editing
                    if !editing { nowPlaying.seek(to: scrubPosition) }
                }
                HStack {
                    Text(timeText(scrubPosition))
                    Spacer()
                    Text("-\(timeText(max(nowPlaying.info.duration - scrubPosition, 0)))")
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
                .font(
                    .system(
                        size: 12,
                        weight: .semibold,
                        design: style == .terminal ? .monospaced : .default
                    )
                )
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 10, design: style == .terminal ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            progressView
            controls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrubber: some View {
        Slider(
            value: $scrubPosition,
            in: 0...max(nowPlaying.info.duration, 1),
            onEditingChanged: { editing in
                isScrubbing = editing
                if !editing {
                    nowPlaying.seek(to: scrubPosition)
                }
            }
        )
        .accessibilityLabel("Playback position")
        // The controller drops commands while one is in flight; dimming the
        // control for each round trip would make it flicker on every seek.
        .disabled(!nowPlaying.supports(.seek))
        .controlSize(.mini)
        .tint(theme.notch.accent)
    }

    @ViewBuilder
    private var progressView: some View {
        if nowPlaying.info.duration > 0 {
            scrubber

            HStack {
                Text(timeText(scrubPosition))
                Spacer()
                Text("-\(timeText(max(nowPlaying.info.duration - scrubPosition, 0)))")
            }
            .font(.system(size: 8, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
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

    private var artwork: some View {
        RecordArtwork(
            artwork: nowPlaying.info.artwork,
            accent: theme.notch.accent,
            control: theme.notch.control,
            size: 78
        )
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

    private func syncScrubPosition() {
        scrubPosition = min(max(nowPlaying.estimatedElapsed(at: Date()), 0), max(nowPlaying.info.duration, 0))
    }

    private func timeText(_ interval: TimeInterval) -> String {
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

            Group {
                if let artwork {
                    Image(nsImage: artwork)
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

/// Re-renders its content when lyrics appear or disappear.
private struct LyricsAware<Content: View>: View {
    @ObservedObject var service: TeleprompterService
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(!(service.currentText.isEmpty && service.statusText.isEmpty))
    }
}

/// The Home widget's single lyric line, in the accent colour. Stays mounted while
/// empty so lyrics keep loading, and shows nothing (not a status) until a line arrives.
private struct WidgetLyricLine: View {
    @ObservedObject var service: TeleprompterService
    @ObservedObject private var theme = ThemeStore.shared
    @State private var presentationID = UUID()

    var body: some View {
        ZStack(alignment: .leading) {
            Text(service.currentText.isEmpty ? " " : service.currentText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.notch.accent)
                .lineLimit(1).minimumScaleFactor(0.85)
                .id(service.currentText)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: service.currentText)
        // Lyrics load and advance only while a presentation is visible; without
        // this, Home kept the last song's line until the Music page was opened.
        // Registered on the container, which outlives each line's identity.
        .onAppear { service.setPresentationVisible(true, id: presentationID) }
        .onDisappear { service.setPresentationVisible(false, id: presentationID) }
    }
}

/// Current lyric in the accent colour with the next line beneath; a status
/// such as "Finding lyrics…" stays small so it never reads as a lyric.
private struct PlayerLyrics: View {
    @ObservedObject var service: TeleprompterService
    @ObservedObject private var theme = ThemeStore.shared
    @State private var presentationID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if service.currentText.isEmpty && service.statusText.isEmpty {
                // Nothing to show yet; stay mounted so lyrics keep loading.
                EmptyView()
            } else if service.currentText.isEmpty {
                Text(service.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(service.currentText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.notch.accent)
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .id(service.currentText)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                // A repeated line (a chorus hook) would otherwise show twice.
                if !service.upcomingText.isEmpty, service.upcomingText != service.currentText {
                    Text(service.upcomingText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.25), value: service.currentText)
        .onAppear { service.setPresentationVisible(true, id: presentationID) }
        .onDisappear { service.setPresentationVisible(false, id: presentationID) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(service.currentText.isEmpty ? service.statusText : "Lyrics: \(service.currentText)")
    }
}

/// A thin capsule that thickens and shows a knob while hovered or dragged.
private struct PlaybackScrubber: View {
    @Binding var position: Double
    let duration: Double
    let enabled: Bool
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
                    position = min(max(value.location.x / max(proxy.size.width, 1), 0), 1) * duration
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
struct ArtworkAmbience: View {
    let artwork: NSImage?

    var body: some View {
        GeometryReader { proxy in
            if let artwork, let wash = Self.wash(for: artwork) {
                Image(nsImage: wash)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 24)
                    .saturation(1.25)
                    .opacity(0.22)
                    .clipped()
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: artwork == nil)
    }

    private static let cache = NSCache<NSImage, NSImage>()

    /// A 48-pixel copy of the cover, Gaussian-blurred with Core Image, so the
    /// wash is already smooth wherever it is drawn (including captures).
    private static func wash(for artwork: NSImage) -> NSImage? {
        if let cached = cache.object(forKey: artwork) { return cached }
        let side: CGFloat = 48
        guard let cg = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        let scale = side / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(small.clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(7, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: small.extent),
              let rendered = CIContext().createCGImage(output, from: small.extent) else { return nil }
        let image = NSImage(cgImage: rendered, size: NSSize(width: side, height: side))
        cache.setObject(image, forKey: artwork)
        return image
    }
}
