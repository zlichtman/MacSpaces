import SwiftUI
import AppKit

/// Theme-aware Nook player with artwork ambience, metadata, scrubbing, and
/// transport controls. The selected Nook theme remains the primary palette;
/// album artwork adds depth without replacing the user's color choices.
struct MediaPlayerView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    let style: WidgetVisualStyle
    @ObservedObject private var theme = ThemeStore.shared
    @State private var scrubPosition: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        Group {
            if style == .signal {
                signalLayout
            } else if style == .mono {
                monoLayout
            } else if style == .frame {
                frameLayout
            } else {
                classicLayout
            }
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
    }

    private var classicLayout: some View {
        HStack(spacing: 11) {
            artwork
            metadata
        }
    }

    private var signalLayout: some View {
        HStack(spacing: 10) {
            artwork
                .scaleEffect(0.88)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                        Text(subtitle.uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    LiveSignalBars(isPlaying: nowPlaying.info.isPlaying)
                        .frame(width: 28, height: 22)
                }
                progressView
                controls
            }
        }
    }

    private var monoLayout: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(theme.notch.accent)
                .frame(width: 4)

            RecordArtwork(
                artwork: nowPlaying.info.artwork,
                accent: theme.notch.accent,
                control: theme.notch.control,
                size: 54
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(nowPlaying.info.hasTrack ? nowPlaying.info.title.uppercased() : "NOTHING PLAYING")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                Text(subtitle.uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    controls
                    Spacer(minLength: 4)
                    LiveSignalBars(isPlaying: nowPlaying.info.isPlaying)
                        .frame(width: 28, height: 18)
                }
            }
        }
    }

    private var frameLayout: some View {
        HStack(spacing: 12) {
            RecordArtwork(
                artwork: nowPlaying.info.artwork,
                accent: theme.notch.accent,
                control: .clear,
                size: 66
            )
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "waveform")
                        .foregroundStyle(theme.notch.accent)
                }
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                progressView
                controls
            }
        }
        .padding(5)
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

    @ViewBuilder
    private var progressView: some View {
        if nowPlaying.info.duration > 0 {
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
            .controlSize(.mini)
            .tint(theme.notch.accent)

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
            transportButton("backward.fill") {
                nowPlaying.previousTrack()
            }
            transportButton(
                nowPlaying.info.isPlaying ? "pause.fill" : "play.fill",
                prominent: true
            ) {
                nowPlaying.togglePlayPause()
            }
            transportButton("forward.fill") {
                nowPlaying.nextTrack()
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 13 : 10, weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.82) : Color.primary)
                .frame(width: prominent ? 28 : 25, height: 25)
                .background(
                    prominent ? theme.notch.accent : theme.notch.control,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(PremiumPressButtonStyle())
    }

    private func syncScrubPosition() {
        scrubPosition = min(max(nowPlaying.info.elapsed, 0), max(nowPlaying.info.duration, 0))
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct LiveSignalBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(ThemeStore.shared.notch.accent)
                        .frame(
                            width: 3,
                            height: isPlaying
                                ? 7 + abs(sin(phase * 3.2 + Double(index) * 0.9)) * 14
                                : 6
                        )
                }
            }
        }
    }
}

/// A compact, low-cost artwork treatment shared by Nook and Dock players.
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
        .shadow(color: accent.opacity(artwork == nil ? 0.14 : 0.22), radius: size * 0.15, y: size * 0.05)
    }
}
