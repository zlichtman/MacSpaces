import SwiftUI
import AppKit

/// The Music page's Terminal look (Settings → Appearance → Album art → Look): drawn straight on
/// the page, like the standard look, with the cover as ASCII art on the left and everything else in Menlo on the
/// right: the title in capitals, "Artist // Album", the current lyric line in the accent, a text
/// progress bar that scrubs like the standard page's, bracketed transport buttons and a status
/// line made only of what's known (the source app, play state, the kind of lyrics).
struct TerminalMusicView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    var lyricsService: TeleprompterService?
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        GeometryReader { proxy in
            let padding: CGFloat = 18
            let side = max(110, min(240, proxy.size.height - padding * 2, (proxy.size.width - padding * 2) * 0.4))
            HStack(alignment: .center, spacing: 22) {
                cover(side)
                Group {
                    if let lyricsService {
                        LyricsReader(service: lyricsService) { column(lyrics: $0) }
                    } else {
                        column(lyrics: .none)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(padding)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: - Cover

    @ViewBuilder private func cover(_ side: CGFloat) -> some View {
        let art = AsciiCover(artwork: nowPlaying.info.artwork, size: side, style: options.asciiStyle,
                             scene: options.asciiScene, detail: options.asciiDetail,
                             position: { [nowPlaying] in
                                 let info = nowPlaying.info
                                 return info.elapsed + (info.isPlaying ? Date().timeIntervalSince(nowPlaying.elapsedReadAt) : 0)
                             },
                             playing: nowPlaying.info.isPlaying,
                             colouring: options.asciiColours,
                             song: "\(nowPlaying.info.title)|\(nowPlaying.info.artist)|\(nowPlaying.info.album)")
        if nowPlaying.canOpenSource {
            Button { nowPlaying.openSource() } label: { art }
                .buttonStyle(PremiumPressButtonStyle())
                .help("Open \(nowPlaying.info.sourceName)")
                .accessibilityLabel("Open \(nowPlaying.info.sourceName)")
        } else {
            art
        }
    }

    // MARK: - Text column

    private var metadata: TrackMetadata {
        TrackMetadata(title: nowPlaying.info.title, artist: nowPlaying.info.artist, album: nowPlaying.info.album)
    }

    private func column(lyrics: TerminalLyrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.song.uppercased())
                    .font(TerminalFont.menlo(18, bold: true))
                    .lineLimit(2).minimumScaleFactor(0.75)
                if !byline.isEmpty {
                    Text(byline)
                        .font(TerminalFont.menlo(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .help([nowPlaying.info.title, nowPlaying.info.artist, nowPlaying.info.album]
                .filter { !$0.isEmpty }.joined(separator: " — "))
            .padding(.bottom, 10)
            Text(lyrics.line)
                .font(TerminalFont.menlo(15))
                .foregroundStyle(theme.notch.accent)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(lyrics.lineID)
                .transition(.opacity)
                .animation(animated ? Design.timed(.easeOut(duration: 0.18)) : nil, value: lyrics.lineID)
                .accessibilityLabel(lyrics.line.isEmpty ? "" : "Lyrics: \(lyrics.line)")
                .accessibilityHidden(lyrics.line.isEmpty)
            Spacer(minLength: 8)
            TerminalProgress(nowPlaying: nowPlaying, onScrub: { lyricsService?.scrub(to: $0) })
                .padding(.bottom, 10)
            controls
                .padding(.bottom, 7)
            Text(status(lyrics: lyrics))
                .font(TerminalFont.menlo(10))
                .foregroundStyle(.secondary)
                .opacity(0.7)
                .lineLimit(1)
        }
    }

    private var animated: Bool { !reduceMotion && !theme.reduceMotion }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// "Artist // Album", either side left out when the player doesn't give it.
    private var byline: String {
        [metadata.artistLine, metadata.album ?? ""].filter { !$0.isEmpty }.joined(separator: " // ")
    }

    /// Only what's known: "spotify · playing · synced lyrics".
    private func status(lyrics: TerminalLyrics) -> String {
        var parts: [String] = []
        let source = nowPlaying.info.sourceName.trimmingCharacters(in: .whitespaces)
        if !source.isEmpty { parts.append(source.lowercased()) }
        parts.append(nowPlaying.displayIsPlaying ? "playing" : "paused")
        if let kind = lyrics.kind { parts.append(kind) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 8) {
            bracketButton("|◀", capability: .previous, label: "Previous", width: 44) { nowPlaying.previousTrack() }
            bracketButton(nowPlaying.displayIsPlaying ? "❚❚ pause" : "▶ play", capability: .playPause,
                          label: nowPlaying.displayIsPlaying ? "Pause" : "Play", width: nil, prominent: true) {
                nowPlaying.togglePlayPause()
            }
            bracketButton("▶|", capability: .next, label: "Next", width: 44) { nowPlaying.nextTrack() }
        }
    }

    private func bracketButton(_ text: String, capability: PlaybackCapability, label: String, width: CGFloat?,
                               prominent: Bool = false, action: @escaping () -> Void) -> some View {
        let ink = prominent ? theme.notch.accent : theme.nookForeground
        return Button(action: action) {
            Text(text)
                .font(TerminalFont.menlo(12, bold: prominent))
                .foregroundStyle(ink)
                .lineLimit(1)
                .frame(width: width, height: 28)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .overlay(Rectangle().strokeBorder(ink.opacity(prominent ? 0.9 : 0.45), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(TerminalBracketStyle(ink: ink))
        .disabled(!nowPlaying.supports(capability))
        .accessibilityLabel(label)
    }
}

/// A bracket button's hover and press: its own box filled faintly in its ink, so the whole
/// box is the target and nothing round shows behind it.
private struct TerminalBracketStyle: ButtonStyle {
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        BracketBody(configuration: configuration, ink: ink)
    }

    private struct BracketBody: View {
        let configuration: ButtonStyleConfiguration
        let ink: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .background(Rectangle().fill(ink.opacity(configuration.isPressed ? 0.22 : hovering && isEnabled ? 0.1 : 0)))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

/// Menlo, the monospaced face the Terminal look is set in.
private enum TerminalFont {
    static func menlo(_ size: CGFloat, bold: Bool = false) -> Font {
        if NSFont(name: "Menlo", size: size) != nil {
            return .custom(bold ? "Menlo-Bold" : "Menlo-Regular", size: size)
        }
        return .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
    }

    /// Menlo's advance is 0.602 em; a little over keeps the bar inside its width.
    static func cellWidth(_ size: CGFloat) -> CGFloat { size * 0.61 }
}

/// What the Terminal look shows from the lyrics service.
private struct TerminalLyrics {
    var line = ""
    var lineID = 0
    /// "synced lyrics", "plain lyrics", "captions", "no lyrics", or nil while still looking.
    var kind: String?

    static let none = TerminalLyrics()
}

/// Reads the lyrics service and keeps its lookup running while the page shows.
private struct LyricsReader<Content: View>: View {
    @ObservedObject var service: TeleprompterService
    let content: (TerminalLyrics) -> Content
    @State private var presentationID = UUID()

    var body: some View {
        content(lyrics)
            .onAppear { service.setPresentationVisible(true, id: presentationID) }
            .onDisappear { service.setPresentationVisible(false, id: presentationID) }
    }

    private var lyrics: TerminalLyrics {
        let kind: String?
        if service.hasLyrics {
            if service.source == .subtitles { kind = "captions" }
            else if service.canNudgeTiming || service.lineSpan != nil { kind = "synced lyrics" }
            else { kind = "plain lyrics" }
        } else if service.showsNoLyrics {
            kind = "no lyrics"
        } else {
            kind = nil
        }
        return TerminalLyrics(line: service.currentText, lineID: service.lineID, kind: kind)
    }
}

/// "1:19 [█████░░░░░░░░░] 3:44": as many cells as fit the width. Dragging across the bar seeks,
/// as the standard page's scrubber does, and the lyrics follow the drag.
private struct TerminalProgress: View {
    @ObservedObject var nowPlaying: NowPlayingController
    var onScrub: ((Double?) -> Void)?
    @ObservedObject private var theme = ThemeStore.shared
    @State private var dragPosition: Double?
    @State private var dragCount = 0
    @State private var watcherID = UUID()
    private let size: CGFloat = 11

    var body: some View {
        let info = nowPlaying.info
        Group {
            if info.duration > 0 {
                TimelineView(.periodic(from: .now, by: info.isPlaying && dragPosition == nil ? 0.25 : 3600)) { context in
                    let position = dragPosition ?? min(max(nowPlaying.estimatedElapsed(at: context.date), 0), info.duration)
                    row(position: position, duration: info.duration)
                }
            }
        }
        .onAppear { nowPlaying.watchPosition(true, id: watcherID) }
        .onDisappear { nowPlaying.watchPosition(false, id: watcherID) }
        .onChange(of: info.title) { _ in dragPosition = nil }
        .onChange(of: dragPosition) { onScrub?($0) }
    }

    private func row(position: Double, duration: Double) -> some View {
        HStack(spacing: 6) {
            Text(Self.timeText(position)).foregroundStyle(.secondary)
            GeometryReader { proxy in
                bar(width: proxy.size.width, fraction: duration > 0 ? min(max(position / duration, 0), 1) : 0)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(drag(width: proxy.size.width, duration: duration))
            }
            .frame(height: size * 1.4)
            Text(Self.timeText(duration)).foregroundStyle(.secondary)
        }
        .font(TerminalFont.menlo(size))
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Self.timeText(position)) of \(Self.timeText(duration))")
    }

    private func bar(width: CGFloat, fraction: Double) -> some View {
        let cells = max(4, Int(width / TerminalFont.cellWidth(size)) - 2)
        let filled = min(cells, max(0, Int((fraction * Double(cells)).rounded())))
        return Text("[").foregroundColor(.secondary)
            + Text(String(repeating: "█", count: filled)).foregroundColor(theme.nookForeground)
            + Text(String(repeating: "░", count: cells - filled)).foregroundColor(theme.nookForeground.opacity(0.4))
            + Text("]").foregroundColor(.secondary)
    }

    private func drag(width: CGFloat, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard nowPlaying.supports(.seek), width > 0 else { return }
                if dragPosition == nil { dragCount &+= 1 }
                dragPosition = min(max(Double(value.location.x / width), 0), 1) * duration
            }
            .onEnded { _ in
                guard let target = dragPosition else { return }
                nowPlaying.seek(to: target)
                // Keep showing the target until the player reports the seek.
                let drag = dragCount
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if dragCount == drag { dragPosition = nil } }
            }
    }

    static func timeText(_ interval: TimeInterval) -> String {
        let seconds = interval.isFinite ? max(0, Int(min(interval, 86_400_000))) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
