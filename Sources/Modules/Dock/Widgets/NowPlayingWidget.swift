import SwiftUI

/// Adaptive Now Playing card for both bottom and side Dock orientations.
/// Artwork provides quiet ambient color while the configured Dock theme owns
/// controls, progress, typography, and contrast.
struct NowPlayingWidget: View {
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject private var theme = ThemeStore.shared
    let isVertical: Bool
    let style: WidgetVisualStyle

    var body: some View {
        Group {
            if style == .signal {
                signalLayout
            } else if style == .mono {
                monoLayout
            } else if style == .frame {
                frameLayout
            } else if isVertical {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var signalLayout: some View {
        HStack(spacing: 7) {
            artwork(size: isVertical ? 42 : 44)
            VStack(alignment: .leading, spacing: 3) {
                title
                artist
                HStack {
                    controls
                    Spacer(minLength: 3)
                    DockSignalBars(isPlaying: nowPlaying.info.isPlaying)
                        .frame(width: 25, height: 18)
                }
            }
        }
        .padding(8)
    }

    private var monoLayout: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(theme.dock.accent)
                .frame(width: 4)
            artwork(size: isVertical ? 38 : 42)
            VStack(alignment: .leading, spacing: 3) {
                title
                    .fontDesign(.monospaced)
                artist
                    .fontDesign(.monospaced)
                HStack(spacing: 5) {
                    controls
                    Spacer(minLength: 2)
                    DockSignalBars(isPlaying: nowPlaying.info.isPlaying)
                        .frame(width: 24, height: 16)
                }
            }
        }
        .padding(7)
    }

    private var frameLayout: some View {
        HStack(spacing: 9) {
            artwork(size: isVertical ? 44 : 48)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    title
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.dock.accent)
                }
                artist
                progress
                controls
            }
        }
        .padding(8)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 8) {
            artwork(size: 48)

            VStack(alignment: .leading, spacing: 2) {
                title
                artist
                progress
                    .padding(.top, 2)
                controls
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    private var verticalLayout: some View {
        VStack(spacing: 5) {
            artwork(size: 52)

            VStack(spacing: 1) {
                title
                artist
            }

            progress
                .frame(maxWidth: 82)

            controls
        }
        .padding(9)
    }

    private var title: some View {
        Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
            .font(.system(size: isVertical ? 10 : 11, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: isVertical ? .center : .leading)
    }

    private var artist: some View {
        Text(subtitle)
            .font(.system(size: isVertical ? 8.5 : 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: isVertical ? .center : .leading)
    }

    private var subtitle: String {
        if !nowPlaying.info.artist.isEmpty {
            return nowPlaying.info.artist
        }
        return nowPlaying.info.hasTrack ? nowPlaying.info.album : "Music or Spotify"
    }

    private var progress: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(theme.dock.accent)
                    .frame(width: proxy.size.width * progressFraction)
            }
        }
        .frame(height: 3)
    }

    private var progressFraction: CGFloat {
        guard nowPlaying.info.duration > 0 else { return 0 }
        return CGFloat(min(max(nowPlaying.info.elapsed / nowPlaying.info.duration, 0), 1))
    }

    private func artwork(size: CGFloat) -> some View {
        RecordArtwork(
            artwork: nowPlaying.info.artwork,
            accent: theme.dock.accent,
            control: theme.dock.control,
            size: size
        )
    }

    private var controls: some View {
        HStack(spacing: isVertical ? 9 : 7) {
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
                .font(.system(size: prominent ? 9.5 : 8, weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.82) : Color.primary)
                .frame(width: prominent ? 22 : 18, height: 18)
                .background(
                    prominent ? theme.dock.accent : theme.dock.control,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(PremiumPressButtonStyle())
    }
}

private struct DockSignalBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.14, paused: !isPlaying)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(ThemeStore.shared.dock.accent)
                        .frame(
                            width: 3,
                            height: isPlaying
                                ? 5 + abs(sin(phase * 3 + Double(index))) * 11
                                : 5
                        )
                }
            }
        }
    }
}
